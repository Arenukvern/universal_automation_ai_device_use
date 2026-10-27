/// Live probe for ADR 0008 computer-use parity: anchors TextEdit, keeps
/// the user's frontmost app unchanged, captures window scale metadata,
/// and pid-clicks a window-local point.
///
/// `dart run example/computer_use_parity_probe.dart <evidence-dir>`
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_driver_macos/universal_driver_macos.dart';

Future<void> main(List<String> args) async {
  final evidenceDir = args.isNotEmpty ? args[0] : 'build/computer-use-evidence';
  Directory(evidenceDir).createSync(recursive: true);
  final driver = MacosDriver(snapshotMaxNodes: 2000);
  final evidence = <String, Object?>{
    'schema': 'computer-use-parity-evidence/v1',
    'date': DateTime.now().toUtc().toIso8601String(),
  };
  final failures = <String>[];

  void check(String name, bool ok, [Object? detail]) {
    evidence[name] = {'ok': ok, if (detail != null) 'detail': detail};
    if (!ok) failures.add(name);
    stderr.writeln('${ok ? "PASS" : "FAIL"} $name');
  }

  if (!driver.axTrusted) {
    stderr.writeln('Grant Accessibility, then re-run.');
    exit(2);
  }
  if (!driver.screenCaptureTrusted) {
    stderr.writeln(
      'Requesting Screen Recording consent (approve the system dialog once)…',
    );
    driver.requestScreenCaptureConsent();
  }
  evidence['screenCaptureTrusted'] = driver.screenCaptureTrusted;

  final frontmostBefore = await driver.frontmost();
  evidence['frontmostBefore'] = frontmostBefore.name;

  final doc = File('/tmp/uat-computer-use.txt');
  doc.writeAsStringSync('computer-use probe\n');
  final open = await Process.run('open', ['-a', 'TextEdit', doc.path]);
  check('launchTextEdit', open.exitCode == 0);
  int? pid;
  MacosWindow? target;
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(deadline) && (pid == null || target == null)) {
    final apps = await driver.runningApps();
    pid = apps
        .where((a) => a.bundleId == 'com.apple.TextEdit' && a.pid > 0)
        .map((a) => a.pid)
        .firstOrNull;
    if (pid == null) {
      final pg = await Process.run('pgrep', ['-x', 'TextEdit']);
      final text = '${pg.stdout}'.trim();
      if (pg.exitCode == 0 && text.isNotEmpty) {
        pid = int.tryParse(text.split('\n').first);
      }
    }
    if (pid != null && pid! > 0) {
      final anchored = MacosDriver(
        bridge: driver.bridge,
        targetPid: pid,
        snapshotMaxNodes: 2000,
      );
      final windows = await anchored.windows(pid: 0, onScreenOnly: false);
      target = windows.where((w) => w.pid == pid).firstOrNull;
    }
    if (target == null) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
  }
  check('textEditPid', pid != null);
  check('textEditWindow', target != null, target?.windowId);
  if (pid == null || target == null) exit(1);

  final anchored = MacosDriver(
    bridge: driver.bridge,
    targetPid: pid,
    snapshotMaxNodes: 2000,
  );
  try {
    final freshWindows = await anchored.windows(pid: 0, onScreenOnly: false);
    final candidates = freshWindows.where((w) => w.pid == pid).toList();
    Object? captureError;
    MacosWindow? live;
    ({
      Uint8List bytes,
      int width,
      int height,
      double scale,
    })? frame;
    for (final window in candidates) {
      try {
        frame = await anchored.windowCaptureFrame(window.windowId);
        live = window;
        break;
      } on Object catch (error) {
        captureError = error;
      }
    }
    check('screenshotMeta', frame != null && frame!.width > 0, captureError);
    if (frame == null || live == null) {
      check('computerLoop', false, 'no capturable window for pid $pid');
    } else {
      evidence['screenshot'] = {
        'width': frame.width,
        'height': frame.height,
        'scale': frame.scale,
        'windowId': live.windowId,
      };
      File('$evidenceDir/window.png').writeAsBytesSync(frame.bytes);

      await anchored.perform(
        ClickAtAction(
          40,
          40,
          windowId: live.windowId,
          pixelInjection: true,
        ),
      );
      check('pidClick', true);
    }
  } on ScreenRecordingPermissionRequiredException {
    check('screenRecording', false, 'call automation_request_consent');
  } on Object catch (error) {
    check('computerLoop', false, '$error');
  }

  final frontmostAfter = await driver.frontmost();
  evidence['frontmostAfter'] = frontmostAfter.name;
  check(
    'noFocusSteal',
    frontmostBefore.pid == frontmostAfter.pid,
    {'before': frontmostBefore.pid, 'after': frontmostAfter.pid},
  );

  File('$evidenceDir/evidence.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(evidence),
  );
  exit(failures.isEmpty ? 0 : 1);
}
