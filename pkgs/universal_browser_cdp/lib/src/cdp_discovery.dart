import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import 'automation_exceptions_export.dart';

const _utf8Decoder = Utf8Decoder(allowMalformed: true);

/// `GET /json/version` response.
class CdpVersionInfo {
  /// Creates version info.
  const CdpVersionInfo({
    required this.browser,
    required this.protocolVersion,
    required this.webSocketDebuggerUrl,
  });

  /// Restores version info from a `/json/version` payload.
  factory CdpVersionInfo.fromJson(Map<String, Object?> json) => CdpVersionInfo(
    browser: json['Browser'] as String? ?? 'unknown',
    protocolVersion: json['Protocol-Version'] as String? ?? '',
    webSocketDebuggerUrl: json['webSocketDebuggerUrl'] as String? ?? '',
  );

  /// `Browser` string, e.g. `Chrome/141.0.0.0`.
  final String browser;

  /// `Protocol-Version` string.
  final String protocolVersion;

  /// Browser-level debugger WebSocket URL.
  final String webSocketDebuggerUrl;

  @override
  String toString() => 'CdpVersionInfo($browser)';
}

/// One entry of `GET /json/list`.
class CdpTargetInfo {
  /// Creates target info.
  const CdpTargetInfo({
    required this.id,
    required this.type,
    required this.url,
    required this.title,
    required this.webSocketDebuggerUrl,
  });

  /// Restores target info from a `/json/list` entry.
  factory CdpTargetInfo.fromJson(Map<String, Object?> json) => CdpTargetInfo(
    id: json['id']! as String,
    type: json['type'] as String? ?? 'page',
    url: json['url'] as String? ?? '',
    title: json['title'] as String? ?? '',
    webSocketDebuggerUrl: json['webSocketDebuggerUrl'] as String? ?? '',
  );

  /// Target id (CDP `targetId`).
  final String id;

  /// Target type: `page`, `iframe`, `worker`, …
  final String type;

  /// Current target URL.
  final String url;

  /// Current target title.
  final String title;

  /// Page-level debugger WebSocket URL.
  final String webSocketDebuggerUrl;

  @override
  String toString() => 'CdpTargetInfo($id, $type, $url)';
}

/// Picks one page target out of a browser's open tabs.
///
/// A browser session usually has several tabs open, and the CDP endpoint
/// lists them all. Attaching to "the first page" is a guess: a real
/// Chrome exposes every open tab as a `page` target, so the first one is
/// an arbitrary tab rather than the one the user means. A selector makes
/// the choice explicit and fails loudly when it cannot be resolved —
/// never silently attaching to the wrong tab.
@immutable
class CdpTargetSelector {
  /// Creates a selector. Every field is optional; when more than one is
  /// set they must all match.
  const CdpTargetSelector({this.id, this.urlContains, this.titleContains});

  /// The exact CDP target id.
  final String? id;

  /// A substring the target's URL must contain.
  final String? urlContains;

  /// A substring the target's title must contain.
  final String? titleContains;

  /// The query-parameter names this selector is encoded as.
  ///
  /// The selector rides in the endpoint URI's *fragment*, the same place
  /// the OS tier encodes its app anchor (`ax://pid/123`): the fragment is
  /// never sent to the browser, so the debug endpoint's own HTTP probes
  /// (`/json/version`, `/json/list`) stay untouched while the choice
  /// travels with the address.
  /// The query-parameter name the target id is encoded as.
  static const String idParam = 'targetId';

  /// The query-parameter name the URL criterion is encoded as.
  static const String urlParam = 'targetUrl';

  /// The query-parameter name the title criterion is encoded as.
  static const String titleParam = 'targetTitle';

  /// Reads a selector from [uri]'s fragment, or `null` when it carries
  /// none.
  ///
  /// The fragment is parsed as query-style parameters, so a selector can
  /// combine criteria: `#targetId=ABC&targetUrl=example.com`.
  static CdpTargetSelector? fromUri(Uri uri) {
    final fragment = uri.fragment;
    if (fragment.isEmpty) {
      return null;
    }
    final params = Uri.splitQueryString(fragment);
    final id = params[idParam];
    final url = params[urlParam];
    final title = params[titleParam];
    if (id == null && url == null && title == null) {
      return null;
    }
    return CdpTargetSelector(id: id, urlContains: url, titleContains: title);
  }

  /// A copy of [base] carrying this selector in its fragment.
  Uri applyTo(Uri base) {
    final params = <String, String>{
      idParam: ?id,
      urlParam: ?urlContains,
      titleParam: ?titleContains,
    };
    if (params.isEmpty) {
      return base;
    }
    return base.replace(fragment: Uri(queryParameters: params).query);
  }

  /// Whether [target] satisfies this selector.
  bool matches(CdpTargetInfo target) {
    final wantedId = id;
    if (wantedId != null && target.id != wantedId) {
      return false;
    }
    final wantedUrl = urlContains;
    if (wantedUrl != null && !target.url.contains(wantedUrl)) {
      return false;
    }
    final wantedTitle = titleContains;
    if (wantedTitle != null && !target.title.contains(wantedTitle)) {
      return false;
    }
    return true;
  }

  /// The targets this selector accepts, in endpoint order.
  List<CdpTargetInfo> selectFrom(List<CdpTargetInfo> targets) => [
    for (final target in targets)
      if (matches(target)) target,
  ];

  /// A human-readable description of what this selector asks for.
  String describe() {
    final parts = <String>[
      if (id != null) 'id=$id',
      if (urlContains != null) 'url~$urlContains',
      if (titleContains != null) 'title~$titleContains',
    ];
    return parts.isEmpty ? 'any target' : parts.join(', ');
  }

  @override
  String toString() => 'CdpTargetSelector(${describe()})';
}

/// HTTP-side discovery against a CDP endpoint's debug server.
///
/// This is the same readiness contract oka uses for borrowed-lease identity
/// (`GET /json/version` must answer before attach is attempted) plus
/// target enumeration. It is discovery only — the wire protocol lives in
/// [CdpConnection] (see `cdp_connection.dart`).
abstract final class CdpDiscovery {
  /// Probes `/json/version`; `null` when the endpoint is silent or slow.
  static Future<CdpVersionInfo?> version(
    Uri httpBase, {
    Duration timeout = const Duration(seconds: 5),
    HttpClient? client,
  }) async {
    final owned = client == null;
    final http = client ?? HttpClient();
    try {
      final request = await http
          .getUrl(httpBase.replace(path: '/json/version'))
          .timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) return null;
      final body = await response
          .transform(_utf8Decoder)
          .join()
          .timeout(timeout);
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, Object?>) return null;
      return CdpVersionInfo.fromJson(decoded);
    } on Object {
      return null;
    } finally {
      if (owned) http.close();
    }
  }

  /// Requires the endpoint to answer; throws otherwise. Use this before
  /// attaching to a borrowed browser: the identity check is what keeps a
  /// stale port from being mistaken for a live session.
  static Future<CdpVersionInfo> requireAlive(
    Uri httpBase, {
    Duration timeout = const Duration(seconds: 5),
    HttpClient? client,
  }) async {
    final info = await version(httpBase, timeout: timeout, client: client);
    if (info == null) {
      throw EndpointUnreachableException(
        'no CDP endpoint answered at $httpBase; borrowed-lease identity '
        'check failed',
        details: {'httpBase': httpBase.toString()},
      );
    }
    return info;
  }

  /// Lists targets (`/json/list`); empty when unreachable.
  ///
  /// With a [selector], only the targets it accepts are returned.
  static Future<List<CdpTargetInfo>> listTargets(
    Uri httpBase, {
    String type = 'page',
    CdpTargetSelector? selector,
    Duration timeout = const Duration(seconds: 5),
    HttpClient? client,
  }) async {
    final owned = client == null;
    final http = client ?? HttpClient();
    try {
      final request = await http
          .getUrl(httpBase.replace(path: '/json/list'))
          .timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) return const [];
      final body = await response
          .transform(_utf8Decoder)
          .join()
          .timeout(timeout);
      final decoded = jsonDecode(body);
      if (decoded is! List<Object?>) return const [];
      final targets = decoded
          .whereType<Map<String, Object?>>()
          .map(CdpTargetInfo.fromJson)
          .toList(growable: false);
      if (selector == null) {
        return targets;
      }
      return selector.selectFrom(targets);
    } on Object {
      return const [];
    } finally {
      if (owned) http.close();
    }
  }

  /// First target of [type], or `null`.
  ///
  /// With a [selector], the first target *matching the selector* is
  /// returned; a selector that matches nothing yields `null` so the
  /// caller can refuse loudly.
  static Future<CdpTargetInfo?> findTarget(
    Uri httpBase, {
    String type = 'page',
    CdpTargetSelector? selector,
    Duration timeout = const Duration(seconds: 5),
    HttpClient? client,
  }) async {
    final targets = await listTargets(
      httpBase,
      type: type,
      selector: selector,
      timeout: timeout,
      client: client,
    );
    for (final target in targets) {
      if (target.type == type) return target;
    }
    return null;
  }
}
