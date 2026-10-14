import 'dart:convert';
import 'dart:typed_data';

import 'package:universal_driver_macos/universal_driver_macos.dart';

/// Captures only the launched process's window, including other Spaces.
/// Avoids the offscreen Flutter capture path implicated in glyph corruption.
Future<Uint8List> captureOwnedNativeWindow(
  int ownerPid, {
  int? windowId,
  void Function(Map<String, Object?> observation)? onObserved,
}) async {
  final driver = MacosDriver(targetPid: ownerPid);
  try {
    final windows = (await driver.windows(
      pid: ownerPid,
      onScreenOnly: false,
    )).where((window) => window.pid == ownerPid).toList();
    final ids = windows.map((window) => window.windowId).toList();
    final metadata = windows.map((window) => window.toJson()).toList();
    final selected = windowId == null
        ? ids
        : ids.where((id) => id == windowId).toList();
    if (selected.length != 1)
      throw StateError(
        'Expected one addressed normal window for PID $ownerPid '
        '(windowId=$windowId); got $ids; '
        'observed windows: ${jsonEncode(metadata)}',
      );
    onObserved?.call({
      'ownerPid': ownerPid,
      'selectedWindowId': selected.single,
      'selection': windowId == null
          ? 'unique-owned-normal-window'
          : 'explicit-owned-window',
      'windows': metadata,
      'scope': 'Existing MacosDriver/CoreGraphics confirms exact window belongs to addressed PID at layer0; no activation or size/title ranking',
    });
    return await driver.windowScreenshot(selected.single);
  } finally {
    await driver.close();
  }
}
