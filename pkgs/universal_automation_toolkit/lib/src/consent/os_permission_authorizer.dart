import 'package:xsoulspace_permission_core/xsoulspace_permission_core.dart';

import 'consent_gated_driver.dart';

/// Shared [PermissionGate] runner for OS-tier surfaces (gated driver,
/// `automation_computer`, future plan steps).
final class OsPermissionAuthorizer {
  /// Creates an authorizer bound to one gate and attribution.
  OsPermissionAuthorizer({
    required PermissionGate gate,
    required String origin,
    String? subject,
  }) : _gate = gate,
       _origin = origin,
       _subject = subject;

  final PermissionGate _gate;
  final String _origin;
  final String? _subject;
  var _sequence = 0;
  final _allowed = <PermissionKind>{};

  /// Refuses with [ConsentRequiredException] when the gate denies.
  Future<void> require(PermissionKind kind, {required String title}) async {
    if (_allowed.contains(kind)) return;
    final decision = await _gate.resolve(
      PermissionRequest(
        id: 'consent-${++_sequence}',
        title: title,
        kind: kind,
        origin: _origin,
        subject: _subject,
        requestedAt: DateTime.now().toUtc(),
      ),
    );
    switch (decision) {
      case PermissionAllow(scope: PermissionGrantScope.once):
        return;
      case PermissionAllow():
        _allowed.add(kind);
        return;
      case PermissionDeny(:final reason):
        throw ConsentRequiredException(kind, reason: reason);
      case PermissionEscalate(:final reason):
        throw ConsentRequiredException(
          kind,
          reason: reason ?? 'unresolved escalation',
        );
    }
  }
}
