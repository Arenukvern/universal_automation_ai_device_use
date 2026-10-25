import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'automation_exceptions.dart';
import 'automation_os_driver.dart';
import 'driver.dart';

/// The image encoding a capture is delivered in.
///
/// Both tiers that can produce pixels natively (CDP's
/// `Page.captureScreenshot`, the macOS CoreGraphics bridge) can emit PNG
/// (lossless) or JPEG (lossy, far smaller). The family never transcodes
/// between them on the far side: a tier that cannot honor the requested
/// format refuses loudly rather than silently shipping a different one.
enum CaptureFormat {
  /// Lossless PNG — the default; every tier can produce it.
  png,

  /// Lossy JPEG — much smaller for photographic/UI content, at the cost
  /// of artifacts around sharp edges. Requires a quality setting.
  jpeg,
}

/// How one capture should be produced.
///
/// The family is explicit about *not* degrading silently: every option
/// here is a request, and a tier that cannot honor one refuses with
/// [DriverUnsupportedException] rather than quietly returning something
/// else.
///
/// The two levers that keep a vision conversation usable are both here:
///
/// - [maxPx] caps the *long side* at capture time, before the bytes
///   exist. This is quality-preserving, not lossy: a vision model
///   downsamples large images to its own input budget anyway, so capping
///   at that budget keeps every pixel the model would have seen while
///   discarding the ones it would have thrown away. Cap *after* the fact
///   (transcode-and-resize) would resample twice.
/// - [format] and [quality] choose the encoding. PNG is lossless and
///   the default; JPEG is far smaller but lossy, so it is opt-in and
///   carries an explicit quality.
///
/// A tier that cannot honor an option refuses loudly. It never silently
/// substitutes a cheaper capture, and it never upscales to reach a
/// requested size.
@immutable
class CaptureOptions {
  /// Creates capture options.
  const CaptureOptions({
    this.fullPage = false,
    this.maxPx,
    this.format = CaptureFormat.png,
    this.quality,
  });

  /// Capture beyond the visible viewport — the whole scrollable surface.
  ///
  /// Meaningful for a scrolling document (a browser page). A tier whose
  /// surface has no scroll extent (a native window, a display) refuses
  /// this: there is no "beyond" to capture.
  final bool fullPage;

  /// Cap the long side of the image, in device pixels.
  ///
  /// `null` means no cap. This is the agent-facing image budget: a vision
  /// model resizes large images down before looking at them, so sending
  /// the full-resolution frame costs bytes without adding what the model
  /// can see. Capping at the model's own ceiling is therefore quality-
  /// preserving, not lossy.
  ///
  /// The cap applies to the *long* side, matching the OS tier's
  /// long-side convention. It never enlarges: an image already smaller
  /// than the cap is left alone.
  final int? maxPx;

  /// The encoding to deliver.
  final CaptureFormat format;

  /// JPEG quality, 1–100. `null` means "the tier's default".
  ///
  /// Only meaningful for [CaptureFormat.jpeg]; ignored for PNG (which is
  /// lossless and has no quality knob).
  final int? quality;

  /// Whether [quality] applies to this request.
  bool get hasQuality => format == CaptureFormat.jpeg && quality != null;

  /// Validates the option set; empty means valid.
  ///
  /// The violations are named so a caller can act on them instead of
  /// guessing which value was wrong.
  List<String> validate() {
    final violations = <String>[];
    final px = maxPx;
    if (px != null && px <= 0) {
      violations.add('capture.maxPx must be positive (got $px)');
    }
    final q = quality;
    if (q != null && (q < 1 || q > 100)) {
      violations.add('capture.quality must be 1..100 (got $q)');
    }
    if (q != null && format != CaptureFormat.jpeg) {
      violations.add(
        'capture.quality applies to jpeg only; ${format.name} is lossless',
      );
    }
    return violations;
  }

  /// Throws [SpecViolationException] when the option set is invalid.
  void ensureValid() {
    final violations = validate();
    if (violations.isNotEmpty) {
      throw SpecViolationException(violations);
    }
  }

  /// A copy with the given fields replaced.
  CaptureOptions copyWith({
    bool? fullPage,
    int? maxPx,
    CaptureFormat? format,
    int? quality,
  }) => CaptureOptions(
    fullPage: fullPage ?? this.fullPage,
    maxPx: maxPx ?? this.maxPx,
    format: format ?? this.format,
    quality: quality ?? this.quality,
  );

  /// Serializes the options (JSON-encodable).
  Map<String, Object?> toJson() => {
    'fullPage': fullPage,
    if (maxPx != null) 'maxPx': maxPx,
    'format': format.name,
    if (quality != null) 'quality': quality,
  };

  @override
  String toString() => 'CaptureOptions(${toJson()})';
}

/// A driver that can honor [CaptureOptions] the base
/// [AutomationDriver.screenshot] contract cannot express.
///
/// The base contract captures *one frame of the visible surface* — the
/// plain viewport PNG. Everything else (beyond the viewport, a size cap, a
/// lossy encoding) is an explicit request that only some tiers can serve,
/// so it lives on its own facade. This mirrors the OS tier's
/// [OsWindowCapture] / [OsDisplayCapture] facades: a caller casts to the
/// facade it needs and gets a loud refusal when the tier does not
/// implement it.
///
/// Implementations must refuse options they cannot honor — never
/// downgrade them to a cheaper capture.
// The facade is one method by design: it is the OPT-IN capture surface,
// cast to only when a caller asks for options the base contract cannot
// express (the same capability-granular pattern as the OS facades).
// ignore: one_member_abstracts
abstract interface class ConfigurableCapture {
  /// Captures one frame honoring [options].
  ///
  /// Throws [DriverUnsupportedException] when the tier cannot honor an
  /// option, and [SpecViolationException] when the option set is invalid.
  Future<Uint8List> capture(CaptureOptions options);
}
