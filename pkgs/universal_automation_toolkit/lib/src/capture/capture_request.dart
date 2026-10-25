import 'dart:typed_data';

import 'package:universal_automation_interface/universal_automation_interface.dart';

/// Resolves the capture options an agent asked for, and captures with them.
///
/// The family's rule is that a tier which cannot honor an option refuses
/// loudly. This helper is where that refusal is *translated* for the
/// agent-facing surfaces: a tier's own [DriverUnsupportedException]
/// already names the route out, so the surfaces add the tier name and
/// re-throw — they never substitute a cheaper capture.
class CaptureRequest {
  /// Creates a capture request.
  const CaptureRequest(this.options);

  /// The requested options.
  final CaptureOptions options;

  /// Reads the options from tool arguments.
  ///
  /// `maxPx` is `null` (no cap) or a positive integer; `0` means "no cap"
  /// for symmetry with the CLI's `--max-px 0` convention. A negative
  /// value is a caller mistake and is refused.
  factory CaptureRequest.fromArguments(Map<String, Object?> arguments) {
    final maxPx = switch (arguments['maxPx']) {
      null => null,
      final int value when value > 0 => value,
      final int value when value == 0 => null,
      final Object value => throw FormatException(
        'capture.maxPx must be a positive integer (got $value)',
      ),
    };
    final format = switch (arguments['format']) {
      null => CaptureFormat.png,
      'png' => CaptureFormat.png,
      'jpeg' || 'jpg' => CaptureFormat.jpeg,
      final Object value => throw FormatException(
        'capture.format must be "png" or "jpeg" (got $value)',
      ),
    };
    final quality = switch (arguments['quality']) {
      null => null,
      final int value => value,
      final Object value => throw FormatException(
        'capture.quality must be an integer (got $value)',
      ),
    };
    return CaptureRequest(
      CaptureOptions(
        fullPage: arguments['fullPage'] == true,
        maxPx: maxPx,
        format: format,
        quality: quality,
      ),
    );
  }

  /// Whether the request asks for anything beyond the plain frame.
  bool get isPlain =>
      !options.fullPage &&
      options.maxPx == null &&
      options.format == CaptureFormat.png;

  /// Captures with [driver], honoring the requested options.
  ///
  /// A driver that implements [ConfigurableCapture] receives the options
  /// as given, so it can honor them natively (scaling at capture time
  /// rather than resampling afterwards) or refuse them. A driver that
  /// does not can only serve the plain frame, so anything beyond it is
  /// refused here — never silently downgraded.
  Future<Uint8List> capture(AutomationDriver driver) async {
    if (isPlain) {
      if (!driver.capabilities.screenshot) {
        throw const DriverUnsupportedException(
          'this transport cannot capture screenshots',
        );
      }
      return driver.screenshot();
    }
    if (driver is! ConfigurableCapture) {
      throw const DriverUnsupportedException(
        'this transport cannot honor the requested capture options '
        '(full page, a size cap, or a chosen encoding)',
      );
    }
    // The check above is the capability test; the cast is the promotion.
    return (driver as ConfigurableCapture).capture(options);
  }
}
