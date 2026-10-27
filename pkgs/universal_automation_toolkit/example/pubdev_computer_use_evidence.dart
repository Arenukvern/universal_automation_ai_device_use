/// Live evidence for Gate 5: Chrome (no CDP), Cursor (or any app) may stay
/// frontmost; `automation_computer` plumbing via [MacosDriver] window bind,
/// scale metadata, and pid pixel click on the pub.dev admin surface.
///
/// Prereqs: Accessibility + Screen Recording; Chrome logged into pub.dev if
/// you expect the admin form (vision/form completion is agent/human).
///
/// `dart run example/pubdev_computer_use_evidence.dart <evidence-dir>`
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_driver_macos/universal_driver_macos.dart';

const _adminUrl =
    'https://pub.dev/packages/oka/admin#github-actions';

Future<void> main(List<String> args) async {
  final evidenceDir = args.isNotEmpty
      ? args[0]
      : 'build/pubdev-computer-evidence';
  Directory(evidenceDir).createSync(recursive: true);
  final driver = MacosDriver(snapshotMaxNodes: 4000);
  final evidence = <String, Object?>{
    'schema': 'pubdev-computer-use-evidence/v1',
    'date': DateTime.now().toUtc().toIso8601String(),
    'adminUrl': _adminUrl,
    'transport': 'osAccessibility',
    'cdp': false,
  };
  final failures = <String>[];

  void check(String name, bool ok, [Object? detail]) {
    evidence[name] = {'ok': ok, if (detail != null) 'detail': detail};
    if (!ok) failures.add(name);
    stderr.writeln('${ok ? "PASS" : "FAIL"} $name');
  }

  if (!driver.axTrusted) {
    stderr.writeln('Grant Accessibility.');
    exit(2);
  }
  if (!driver.screenCaptureTrusted) {
    driver.requestScreenCaptureConsent();
  }
  evidence['screenCaptureTrusted'] = driver.screenCaptureTrusted;

  final frontmostBefore = await driver.frontmost();
  evidence['frontmostBefore'] = {
    'name': frontmostBefore.name,
    'pid': frontmostBefore.pid,
    'bundleId': frontmostBefore.bundleId,
  };

  final opened = await Process.run('open', [
    '-g',
    '-a',
    'Google Chrome',
    _adminUrl,
  ]);
  check('openChromeBackground', opened.exitCode == 0, opened.stderr.toString());

  int? chromePid;
  MacosWindow? window;
  final deadline = DateTime.now().add(const Duration(seconds: 25));
  while (DateTime.now().isBefore(deadline) &&
      (chromePid == null || window == null)) {
    final apps = await driver.runningApps();
    chromePid = apps
        .where((a) => a.bundleId == 'com.google.Chrome' && a.pid > 0)
        .map((a) => a.pid)
        .firstOrNull;
    if (chromePid == null) {
      final pg = await Process.run('pgrep', ['-x', 'Google Chrome']);
      final text = '${pg.stdout}'.trim();
      if (pg.exitCode == 0 && text.isNotEmpty) {
        chromePid = int.tryParse(text.split('\n').first);
      }
    }
    if (chromePid != null) {
      final anchored = MacosDriver(
        bridge: driver.bridge,
        targetPid: chromePid,
        snapshotMaxNodes: 4000,
      );
      final windows = await anchored.windows(pid: 0, onScreenOnly: false);
      final chromeWindows =
          windows.where((w) => w.pid == chromePid).toList();
      window = chromeWindows
          .where((w) => (w.bounds?.width ?? 0) > 200)
          .fold<MacosWindow?>(
        null,
        (best, w) {
          final area = (w.bounds?.width ?? 0) * (w.bounds?.height ?? 0);
          final bestArea = best == null
              ? 0.0
              : (best.bounds?.width ?? 0) * (best.bounds?.height ?? 0);
          return area > bestArea ? w : best;
        },
      );
    }
    if (window == null) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }
  check('chromePid', chromePid != null);
  check('chromeWindow', window != null, window?.windowId);
  if (chromePid == null || window == null) {
    _write(evidenceDir, evidence, failures);
    exit(1);
  }

  final anchored = MacosDriver(
    bridge: driver.bridge,
    targetPid: chromePid,
    snapshotMaxNodes: 4000,
  );
  anchored.preferWebContent = true;

  try {
    ({
      Uint8List bytes,
      int width,
      int height,
      double scale,
    })? frame;
    MacosWindow? live;
    for (final candidate in (await anchored.windows(pid: 0, onScreenOnly: false))
        .where((w) => w.pid == chromePid)) {
      try {
        frame = await anchored.windowCaptureFrame(candidate.windowId);
        live = candidate;
        break;
      } on Object {
        continue;
      }
    }
    check('screenshotMeta', frame != null && frame!.width > 0);
    if (frame != null && live != null) {
      evidence['bind'] = {
        'windowId': live.windowId,
        'pid': chromePid,
        'width': frame.width,
        'height': frame.height,
        'scale': frame.scale,
      };
      File('$evidenceDir/chrome-admin.png').writeAsBytesSync(frame.bytes);

      await anchored.perform(
        ClickAtAction(
          frame.width * 0.5,
          frame.height * 0.35,
          windowId: live.windowId,
          pixelInjection: true,
        ),
      );
      check('pidClickCenter', true);

      final frameAfter = await anchored.windowCaptureFrame(live.windowId);
      File('$evidenceDir/chrome-admin-after-click.png')
          .writeAsBytesSync(frameAfter.bytes);
      check('screenshotAfterClick', frameAfter.bytes.isNotEmpty);
    }
  } on Object catch (error) {
    check('computerLoop', false, '$error');
  }

  final frontmostAfter = await driver.frontmost();
  evidence['frontmostAfter'] = {
    'name': frontmostAfter.name,
    'pid': frontmostAfter.pid,
  };
  check(
    'noFocusSteal',
    frontmostBefore.pid == frontmostAfter.pid,
    {
      'before': frontmostBefore.pid,
      'after': frontmostAfter.pid,
    },
  );

  _write(evidenceDir, evidence, failures);
  exit(failures.isEmpty ? 0 : 1);
}

void _write(
  String dir,
  Map<String, Object?> evidence,
  List<String> failures,
) {
  evidence['ok'] = failures.isEmpty;
  if (failures.isNotEmpty) evidence['failures'] = failures;
  File('$dir/evidence.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(evidence),
  );
}
