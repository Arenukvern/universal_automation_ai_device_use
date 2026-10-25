import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'snapshot.dart';

/// One running, anchorable OS application — the discovery record the
/// app-catalog surface returns and every targeting call consumes
/// (ADR 0004: the neutral shape behind the per-OS driver records).
@immutable
abstract interface class OsAppRecord {
  /// Process id — the handle every app-targeted call takes.
  int get pid;

  /// Display name (`localizedName` and equivalents).
  String get name;

  /// Bundle identifier (`com.apple.Safari`), when the app has one.
  String? get bundleId;

  /// Whether the app currently owns the frontmost, key window.
  bool get active;

  /// Whether the app is hidden.
  bool get hidden;
}

/// One on-screen OS window — the record window-scoped capture consumes.
@immutable
abstract interface class OsWindowRecord {
  /// The platform window id capture addresses (CGWindow number and
  /// equivalents).
  int get windowId;

  /// The owning application's pid.
  int get pid;

  /// The window title.
  String get name;

  /// On-screen bounds, when known.
  AxBounds? get bounds;
}

/// Lists the running, anchorable applications (ADR 0004 facades —
/// capability-granular OS surfaces so compositions cast to contracts,
/// never to concrete drivers). Today macOS AX provides this; the
/// Android AccessibilityService tier is the planned second source.
// Single-method by design: capability granularity lets a platform
// implement exactly the surfaces it has (Android: catalog + activator,
// no window capture).
// ignore: one_member_abstracts
abstract interface class OsAppCatalog {
  /// The running, anchorable applications.
  Future<List<OsAppRecord>> runningApps();
}

/// Brings an application to the front — the explicit focus handoff the
/// ADR 0064 ladder performs after a `foreground: true` opt-in.
// ignore: one_member_abstracts
abstract interface class OsActivator {
  /// Activates the application with [pid].
  Future<void> activate(int pid);
}

/// Window discovery and window-scoped capture (needs the OS screen
/// recording consent where applicable).
abstract interface class OsWindowCapture {
  /// The windows owned by [pid] (0 = every regular application).
  Future<List<OsWindowRecord>> windows({int pid});

  /// Captures one window's PNG; [maxPx] caps the long side when set.
  Future<Uint8List> windowScreenshot(int windowId, {int? maxPx});
}

/// Whole-display capture with a long-side cap; drivers whose base
/// `screenshot()` cannot resize declare this to opt into `maxPx`.
// ignore: one_member_abstracts
abstract interface class OsDisplayCapture {
  /// Captures the display; [maxPx] caps the long side.
  Future<Uint8List> screenshot({int? maxPx});
}

/// Requests the operating system's consent prompts for a tier's
/// capabilities.
///
/// The OS owns these grants (macOS: Accessibility and Screen Recording in
/// System Settings → Privacy & Security). A driver that needs a grant
/// detects its absence and refuses; this facade is how the *ask* is
/// expressed, so the request stays an explicit, user-initiated action
/// rather than something a capture silently triggers.
///
/// Implementations must not prompt on their own: the caller asks.
abstract interface class OsConsentRequester {
  /// Whether the Accessibility grant is currently held (never prompts).
  bool get accessibilityTrusted;

  /// Whether the Screen Recording grant is currently held (never prompts).
  bool get screenCaptureTrusted;

  /// Raises the system Accessibility prompt; returns the resulting status.
  ///
  /// A `true` result means the grant is now held. A `false` result means
  /// the prompt was shown and the user has not granted it yet (the user
  /// may still grant it in System Settings).
  bool requestAccessibilityConsent();

  /// Raises the system Screen Recording prompt; returns the resulting
  /// status.
  ///
  /// A `true` result means the grant is now held. A `false` result means
  /// the prompt was shown and the user has not granted it yet.
  bool requestScreenCaptureConsent();
}
