import 'dart:convert';

import 'package:universal_automation_toolkit/compose.dart';

import 'flow.dart';

/// The declared parameter types a command codec knows.
const _paramTypes = ['string', 'int', 'double', 'bool', 'uri'];

/// A declared command parameter: name, type, requiredness, default, doc.
///
/// The codec is the declaration, not a parser: [CommandArgs] reads values
/// that were already validated against these params at expansion time.
final class CommandParam {
  /// Declares a parameter. [type] is one of `string`, `int`, `double`,
  /// `bool`, `uri`; [defaultValue] must match [type].
  const CommandParam(
    this.name, {
    required this.type,
    this.required = false,
    this.defaultValue,
    this.doc,
  });

  /// Parameter name inside the args map.
  final String name;

  /// One of `string`, `int`, `double`, `bool`, `uri`.
  final String type;

  /// Whether a caller must supply the value.
  final bool required;

  /// Used when the caller omits the value.
  final Object? defaultValue;

  /// One-line explanation carried in explain() and the declaration.
  final String? doc;

  /// Whether [value] satisfies the declared type.
  bool accepts(Object? value) => switch (type) {
    'string' => value is String,
    'int' => value is int,
    'double' => value is num,
    'bool' => value is bool,
    'uri' => value is Uri || (value is String && Uri.tryParse(value) != null),
    _ => false,
  };

  /// Canonical declaration shape (drives the revision hash).
  Map<String, Object?> toJson() => {
    'name': name,
    'type': type,
    if (required) 'required': true,
    if (defaultValue != null) 'default': defaultValue,
    if (doc != null) 'doc': doc,
  };
}

/// Validated command arguments: every value was checked against its
/// declared [CommandParam] before [CommandSpec.build] ran. Typed getters
/// throw [StateError] on a spec bug — never a silent wrong value.
final class CommandArgs {
  CommandArgs._(this._values);

  final Map<String, Object?> _values;

  /// The string value for [name].
  String string(String name) => _values[name] as String;

  /// The int value for [name].
  int integer(String name) => _values[name] as int;

  /// The num value for [name], as a double.
  double decimal(String name) => (_values[name] as num).toDouble();

  /// The bool value for [name].
  bool flag(String name) => _values[name] as bool;

  /// The Uri value for [name] (string forms parse at validation).
  Uri uri(String name) => _values[name] is Uri
      ? _values[name] as Uri
      : Uri.parse(_values[name] as String);
}

/// Builds a command's step tree from validated args.
typedef CommandBody = List<Object> Function(CommandArgs args);

/// A versioned command spec (the supervisor ADR 0041 pattern: codec +
/// revision identity). Commands are templates over plan steps — the
/// identical compiled artifact CLI, serve, and an in-app agent execute.
///
/// Bump [revision] whenever the step shape or params change observably;
/// [revisionHash] pins the declared surface so a recorded compile can be
/// checked against the spec that produced it.
final class CommandSpec {
  /// Declares a command. [build]'s steps must be plain plan steps —
  /// nested [CommandRef]s are refused (commands compose through steps
  /// and ordinary Dart; re-entry would make cycles undecidable).
  const CommandSpec({
    required this.name,
    required this.revision,
    this.params = const [],
    required this.build,
    this.doc,
  });

  /// Stable command name, unique within a registry.
  final String name;

  /// Monotonic revision; identity is `name@revision`.
  final int revision;

  /// Declared parameters, validated at expansion.
  final List<CommandParam> params;

  /// The step template.
  final CommandBody build;

  /// One-line explanation of what the command does.
  final String? doc;

  /// `name@revision` — the compile-time identity.
  String get id => '$name@$revision';

  /// Stable non-cryptographic hash (FNV-1a, 63-bit masked so it is
  /// always a positive literal) over the declared surface: name,
  /// revision, params, doc. It travels in declarations and explain() so
  /// a consumer can verify a recorded compile against this spec.
  String get revisionHash {
    final canonical = jsonEncode({
      'name': name,
      'revision': revision,
      'params': [for (final param in params) param.toJson()],
      if (doc != null) 'doc': doc,
    });
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(canonical)) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0x7FFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  /// Canonical declaration shape.
  Map<String, Object?> toJson() => {
    'name': name,
    'revision': revision,
    'revisionHash': revisionHash,
    if (doc != null) 'doc': doc,
    'params': [for (final param in params) param.toJson()],
  };
}

/// A set of command specs; duplicate names fail at construction (the
/// registry is a value, not a mutable registry).
final class CommandRegistry {
  /// Builds the registry; duplicate command names throw [FormatException].
  CommandRegistry(Iterable<CommandSpec> commands)
    : _commands = _named(commands);

  static Map<String, CommandSpec> _named(Iterable<CommandSpec> commands) {
    final map = <String, CommandSpec>{};
    for (final command in commands) {
      if (map.containsKey(command.name)) {
        throw FormatException('command "${command.name}" declared twice');
      }
      map[command.name] = command;
    }
    return Map.unmodifiable(map);
  }

  final Map<String, CommandSpec> _commands;

  /// The spec for [name], when declared.
  CommandSpec? named(String name) => _commands[name];

  /// Every declared spec, in declaration order.
  Iterable<CommandSpec> get all => _commands.values;

  /// Declaration-level violations: unknown param types, defaults that do
  /// not match their declared type, duplicate param names. The assembly
  /// folds these into its fail-closed compile list.
  List<String> get declarationViolations => [
    for (final command in _commands.values) ..._paramViolations(command),
  ];

  List<String> _paramViolations(CommandSpec command) {
    final violations = <String>[];
    final seen = <String>{};
    for (final param in command.params) {
      if (!seen.add(param.name)) {
        violations.add(
          'command "${command.name}": param "${param.name}" declared twice',
        );
      }
      if (!_paramTypes.contains(param.type)) {
        violations.add(
          'command "${command.name}": param "${param.name}" has unknown '
          'type "${param.type}"',
        );
      }
      if (param.defaultValue != null && !param.accepts(param.defaultValue)) {
        violations.add(
          'command "${command.name}": param "${param.name}" default value '
          'does not match its declared type',
        );
      }
    }
    return violations;
  }

  /// Expands [reference] into plan steps, validating args against the
  /// spec's codec. Unknown commands, missing/unknown/mis-typed params,
  /// and nested command references come back as violations — the caller
  /// folds them into the assembly's fail-closed list, so one bad
  /// reference never hides the rest.
  (List<PlanStep>, List<String>) expand(CommandRef reference) {
    final spec = _commands[reference.name];
    if (spec == null)
      return (const [], ['unknown command "${reference.name}"']);
    final args = <String, Object?>{};
    final violations = <String>[];
    for (final param in spec.params) {
      final value = reference.args[param.name] ?? param.defaultValue;
      if (value == null) {
        if (param.required) {
          violations.add(
            'command "${reference.name}": missing required param '
            '"${param.name}"',
          );
        }
        continue;
      }
      if (!param.accepts(value)) {
        violations.add(
          'command "${reference.name}": param "${param.name}" does not '
          'accept ${value.runtimeType}',
        );
        continue;
      }
      args[param.name] = value;
    }
    for (final key in reference.args.keys) {
      if (!spec.params.any((param) => param.name == key)) {
        violations.add('command "${reference.name}": unknown param "$key"');
      }
    }
    if (violations.isNotEmpty) return (const [], violations);
    final built = spec.build(CommandArgs._(args));
    final steps = <PlanStep>[];
    for (final entry in built) {
      if (entry is CommandRef) {
        violations.add(
          'command "${reference.name}": nested command reference '
          '"${entry.name}" is not allowed (commands compose through '
          'steps and Dart, not re-entry)',
        );
        continue;
      }
      if (entry is! PlanStep) {
        violations.add(
          'command "${reference.name}": build returned a non-step '
          '(${entry.runtimeType})',
        );
        continue;
      }
      steps.add(
        entry.withCommon(
          session: reference.session ?? entry.session,
          continueOnFailure: reference.soft || entry.continueOnFailure,
        ),
      );
    }
    return (steps, violations);
  }
}
