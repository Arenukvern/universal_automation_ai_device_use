import 'dart:convert';
import 'dart:io';

/// What kind of guidance an envelope carries.
enum RuleKind { rule, guide }

/// The typed carrier for rules and guides (ADR 0004 §4): the harness
/// moves them and says what they are — it never interprets [content].
/// Content is world data (realm commons, memory tiers, repo docs),
/// loaded in like intents, never baked into the package.
final class RuleEnvelope {
  /// Creates an envelope; [id] and [content] must be non-empty.
  const RuleEnvelope({
    required this.id,
    required this.kind,
    required this.content,
    required this.source,
  });

  /// Restores an envelope from its JSON shape; malformed input throws
  /// [FormatException] naming the field (fail closed, loudly).
  factory RuleEnvelope.fromJson(Map<Object?, Object?> json) {
    final id = json['id'];
    if (id is! String || id.trim().isEmpty) {
      throw const FormatException('envelope needs a non-empty "id"');
    }
    final kindName = json['kind'];
    final kind = RuleKind.values
        .where((value) => value.name == kindName)
        .firstOrNull;
    if (kind == null) {
      throw FormatException(
        'envelope "$id" needs kind "rule" or "guide" (got $kindName)',
      );
    }
    final content = json['content'];
    if (content is! String || content.trim().isEmpty) {
      throw FormatException('envelope "$id" needs non-empty "content"');
    }
    final source = json['source'];
    if (source is! String || source.isEmpty) {
      throw FormatException('envelope "$id" needs a "source"');
    }
    return RuleEnvelope(id: id, kind: kind, content: content, source: source);
  }

  /// Stable envelope id (`automation.<name>` style); unique per bundle.
  final String id;

  /// Whether this is a hard [RuleKind.rule] or a soft [RuleKind.guide].
  final RuleKind kind;

  /// The carried world data — opaque to the harness.
  final String content;

  /// Where the content came from (a path, a commons address, a URI).
  final String source;

  /// Canonical shape.
  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'content': content,
    'source': source,
  };
}

/// Loads envelopes from JSON files (one object or a top-level list, the
/// intent-manifest loading shape). Duplicate ids inside one bundle are a
/// [FormatException]; `source` is stamped with the file path when the
/// document omits it.
List<RuleEnvelope> loadRuleEnvelopes(Iterable<String> paths) {
  final envelopes = <RuleEnvelope>[];
  final seen = <String>{};
  for (final path in paths) {
    final decoded = jsonDecode(File(path).readAsStringSync());
    final list = decoded is List<Object?> ? decoded : [decoded];
    for (final entry in list) {
      if (entry is! Map<Object?, Object?>) {
        throw FormatException('envelope file $path holds a non-object entry');
      }
      final envelope = RuleEnvelope.fromJson({
        'source': path,
        ...entry.map((key, value) => MapEntry('$key', value)),
      });
      if (!seen.add(envelope.id)) {
        throw FormatException(
          'envelope "${envelope.id}" declared twice (bundle)',
        );
      }
      envelopes.add(envelope);
    }
  }
  return envelopes;
}
