import 'dart:typed_data';

import 'package:universal_driver_macos/universal_driver_macos.dart';

/// Records every bridge call and replays scripted observations — the
/// macOS-driver test's FakeBridge pattern, trimmed to what the anchor
/// and focus-contract paths touch.
final class FakeAxDriverBridge implements AxDriverBridge {
  FakeAxDriverBridge();

  BridgeJsonResult snapshotResult = (code: 0, json: appJsonFixture);
  BridgeJsonResult snapshotAppResult = (code: 0, json: appJsonFixture);
  BridgeJsonResult appsResult = (code: 0, json: appsJsonFixture);
  BridgeJsonResult frontmostResult = (code: 0, json: safariJsonFixture);
  int activateResult = 0;

  final calls = <String>[];
  final pressed = <int>[];
  final setValues = <(int, String)>[];
  final elementActionCalls = <(int, String)>[];
  int? lastSnapshotPid;
  int? lastActivatedPid;

  @override
  String version() => 'xs-ax-driver/1';

  @override
  bool axTrusted() => true;

  @override
  bool requestTrust() => true;

  @override
  BridgeJsonResult snapshotJson({
    required int maxDepth,
    required int maxNodes,
  }) {
    calls.add('snapshot');
    return snapshotResult;
  }

  @override
  BridgeJsonResult snapshotAppJson({
    required int maxDepth,
    required int maxNodes,
    required int pid,
    int preferWebContent = 1,
  }) {
    calls.add('snapshotApp(pid=$pid)');
    lastSnapshotPid = pid;
    return snapshotAppResult;
  }

  @override
  BridgeJsonResult appsJson() {
    calls.add('apps');
    return appsResult;
  }

  @override
  BridgeJsonResult frontmostJson() {
    calls.add('frontmost');
    return frontmostResult;
  }

  @override
  int activateApp(int pid) {
    calls.add('activate($pid)');
    lastActivatedPid = pid;
    frontmostResult = (code: 0, json: finderJsonFixture);
    return activateResult;
  }

  @override
  int launchApp(String bundleId) => 4242;

  @override
  int terminateApp(int pid) => 0;

  @override
  BridgeJsonResult elementAtPositionJson({
    required double x,
    required double y,
  }) => (code: 4, json: '');

  @override
  int press(int handle) {
    calls.add('press($handle)');
    pressed.add(handle);
    return 0;
  }

  @override
  int focus(int handle) => 0;

  @override
  int setValue(int handle, String value) {
    calls.add('setValue($handle)');
    setValues.add((handle, value));
    return 0;
  }

  @override
  int performElementAction(int handle, String action) {
    calls.add('elementAction($handle,$action)');
    elementActionCalls.add((handle, action));
    return 0;
  }

  @override
  int typeText(String text) => 0;

  @override
  int keyPress(String key) => 0;

  @override
  int scroll(double dx, double dy) => 0;

  @override
  int pointerMove({
    required double x,
    required double y,
    Iterable<String> modifiers = const [],
  }) => 0;

  @override
  int pointerButton({
    required double x,
    required double y,
    required String button,
    required bool down,
    int clickCount = 1,
    Iterable<String> modifiers = const [],
  }) => 0;

  @override
  int keyDown(String key) => 0;

  @override
  int keyUp(String key) => 0;

  @override
  int typeTextToPid(int pid, String text) {
    pidTypedText.add((pid: pid, text: text));
    return 0;
  }

  final pidTypedText = <({int pid, String text})>[];
  final scrollToPidCalls = <({int pid, double dx, double dy})>[];

  @override
  int keyPressToPid(int pid, String key) => 0;

  @override
  int keyDownToPid(int pid, String key) => 0;

  @override
  int keyUpToPid(int pid, String key) => 0;

  @override
  int pointerMoveToPid(
    int pid, {
    required double x,
    required double y,
    Iterable<String> modifiers = const [],
  }) => 0;

  @override
  int pointerButtonToPid(
    int pid, {
    required double x,
    required double y,
    required String button,
    required bool down,
    int clickCount = 1,
    Iterable<String> modifiers = const [],
  }) => 0;

  @override
  int scrollToPid(int pid, {required double dx, required double dy}) {
    scrollToPidCalls.add((pid: pid, dx: dx, dy: dy));
    return 0;
  }

  @override
  void releaseAll() {}

  @override
  BridgeBytesResult screenshotPng({int displayId = 0, int maxPx = 0}) =>
      (code: 0, bytes: Uint8List.fromList([1]));

  @override
  BridgeBytesResult screenshotWindowPng({
    required int windowId,
    int maxPx = 0,
  }) => (code: 0, bytes: Uint8List.fromList([1]));

  @override
  BridgeJsonResult windowsJson({int pid = 0}) => (code: 0, json: '[]');
}

const appJsonFixture =
    '{"role":"application","name":"Finder",'
    '"attributes":{"axid":"0","pid":"42"},'
    '"children":['
    '{"role":"button","name":"Save","attributes":{"axid":"2"}},'
    '{"role":"textbox","name":"Search","value":"","attributes":{"axid":"3"}}'
    ']}';

const appsJsonFixture =
    '[{"pid":42,"bundleId":"com.apple.finder","name":"Finder",'
    '"active":false,"hidden":false},'
    '{"pid":1234,"bundleId":"com.apple.Safari","name":"Safari",'
    '"active":true,"hidden":false}]';

const safariJsonFixture =
    '{"pid":1234,"bundleId":"com.apple.Safari","name":"Safari",'
    '"active":true,"hidden":false}';

const finderJsonFixture =
    '{"pid":42,"bundleId":"com.apple.finder","name":"Finder",'
    '"active":false,"hidden":false}';
