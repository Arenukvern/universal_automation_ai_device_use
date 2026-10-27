import 'package:meta/meta.dart';

import 'automation_endpoint.dart';
import 'automation_exceptions.dart';
import 'behavior/behavioral_driver.dart';
import 'driver.dart';

/// Whether a session is started by us or adopted from someone else.
enum StartMode {
  /// We own bring-up (oka `start`).
  start,

  /// Something else started it and we attach to the published handle
  /// (oka `attach`).
  attach,
}

/// Ownership of a session's process lease, mirroring oka's
/// `LeaseOwnership`.
enum LeaseOwnership {
  /// We are allowed — and expected — to stop the process on teardown.
  owned,

  /// The process belongs to someone else; it is reported, never stopped.
  borrowed,
}

/// Declarative description of an automation session.
///
/// Validation invariants (fail closed): a borrowed session can never be
/// [StartMode.start] — you do not launch what you only borrow.
@immutable
class SessionDescriptor {
  /// Creates a descriptor after validating its invariants.
  SessionDescriptor({
    required this.name,
    this.startMode = StartMode.attach,
    this.ownership = LeaseOwnership.owned,
  }) {
    ensureValid();
  }

  /// Session name, used in handle artifact ids.
  final String name;

  /// How the session comes to exist.
  final StartMode startMode;

  /// Who owns the underlying process lease.
  final LeaseOwnership ownership;

  /// Invariants; empty means valid.
  List<String> validate() {
    if (name.trim().isEmpty) {
      return const ['session name must not be empty'];
    }
    if (ownership == LeaseOwnership.borrowed && startMode == StartMode.start) {
      const message =
          'a borrowed session cannot have start mode `start`; '
          'borrowing means attaching to an existing process';
      return [message];
    }
    return const [];
  }

  /// Throws [SpecViolationException] when invariants are violated.
  void ensureValid() {
    final violations = validate();
    if (violations.isNotEmpty) {
      throw SpecViolationException(violations);
    }
  }

  /// Serializes the descriptor.
  Map<String, Object?> toJson() => {
    'name': name,
    'startMode': startMode.name,
    'ownership': ownership.name,
  };

  @override
  String toString() =>
      'SessionDescriptor($name, ${startMode.name}, ${ownership.name})';
}

/// One plan-or-ad-hoc session binding: a named transport pointing at a
/// live [uri], or at a [handle] (`session-<name>`-style artifact) the
/// caller resolves via overrides. Borrowed sessions are detached from,
/// never stopped.
///
/// Promoted from the toolkit's plan model (ADR 0004): an embedder binds
/// and resolves sessions against the interface alone.
@immutable
class SessionBinding {
  /// Creates a binding; exactly one of [uri] / [handle] must be set.
  const SessionBinding({
    required this.name,
    required this.transport,
    this.uri,
    this.handle,
  }) : assert(uri != null || handle != null, 'uri or handle required');

  /// Restores a binding from its plan shape.
  factory SessionBinding.fromJson(String name, Object? json) {
    if (json is! Map<Object?, Object?>) {
      throw FormatException('session "$name" must be a map');
    }
    final transportName = json['transport'];
    if (transportName is! String) {
      throw FormatException('session "$name" needs a transport');
    }
    final transport = AutomationTransport.values
        .where((value) => value.name == transportName)
        .firstOrNull;
    if (transport == null) {
      throw FormatException(
        'session "$name" has unknown transport "$transportName"',
      );
    }
    final uriValue = json['uri'];
    final handleValue = json['handle'];
    if ((uriValue == null) == (handleValue == null)) {
      throw FormatException(
        'session "$name" needs exactly one of uri or handle',
      );
    }
    Uri? uri;
    if (uriValue != null) {
      if (uriValue is! String) {
        throw FormatException('session "$name" uri must be a string');
      }
      uri = Uri.tryParse(uriValue);
      if (uri == null) {
        throw FormatException('session "$name" uri does not parse: $uriValue');
      }
    }
    if (handleValue != null && handleValue is! String) {
      throw FormatException('session "$name" handle must be a string');
    }
    return SessionBinding(
      name: name,
      transport: transport,
      uri: uri,
      handle: handleValue as String?,
    );
  }

  /// Session name (the plan's sessions map key).
  final String name;

  /// The tier this session attaches over.
  final AutomationTransport transport;

  /// The live endpoint, when the binding points at one directly.
  final Uri? uri;

  /// The handle artifact name, when the binding resolves via overrides
  /// or a handles directory.
  final String? handle;

  /// The endpoint to attach to: [uri], or the `oka:focused` sentinel
  /// for the endpoint-free desktop tier.
  Uri? resolveUri(Map<String, String> overrides) {
    if (uri != null) return uri;
    final handle = this.handle;
    if (handle == null) return null;
    final override = overrides[handle];
    if (override == null) return null;
    return Uri.tryParse(override);
  }

  /// Serializes the binding (without the name — it is the map key).
  Map<String, Object?> toJson() => {
    'transport': transport.name,
    if (uri != null) 'uri': '$uri',
    if (handle != null) 'handle': handle,
  };

  @override
  String toString() =>
      'SessionBinding($name, ${transport.name}, ${uri ?? handle})';
}

/// A resolved, live session: a driver over an attached endpoint.
///
/// Promoted from the toolkit (ADR 0004): embedders implement drivers and
/// factories against the interface alone — the toolkit's registry,
/// runner, and MCP face compose them.
abstract interface class ResolvedSession {
  /// The binding this session resolved.
  SessionBinding get binding;

  /// The attached driver.
  AutomationDriver get driver;

  /// The surface URL, when the transport exposes one.
  Uri? get url;

  /// The behavioral face of the driver, when the tier can honor ADR 0044
  /// profiles; `null` means profiled dispatches must fail loudly.
  BehavioralDriver? asBehavioral();

  /// Detaches: drops this client's connection, never stops the process
  /// behind it (attach-only teardown).
  Future<void> detach();
}

/// Builds a live session over one resolved endpoint — the extension
/// seam of every session registry. Composition roots (the instrumented
/// Flutter tier, a mobile self-widget-tree driver, a WebView tier)
/// register factories without touching the toolkit.
typedef DriverFactory = Future<ResolvedSession> Function(
  SessionBinding binding,
  Uri endpoint,
  Duration attachTimeout,
);
