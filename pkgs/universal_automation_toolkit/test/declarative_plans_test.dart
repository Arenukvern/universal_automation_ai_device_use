import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_automation_toolkit/universal_automation_toolkit.dart';
import 'package:universal_driver_linux/universal_driver_linux.dart';
import 'package:universal_driver_macos/universal_driver_macos.dart';

import 'support/fake_ax_bridge.dart';

Future<ResolvedSession> _hermeticOsAccessibilityFactory(
  SessionBinding binding,
  Uri endpoint,
  Duration attachTimeout,
) async {
  final pid = endpoint.scheme == 'ax' && endpoint.host == 'pid'
      ? int.tryParse(
          endpoint.path.startsWith('/')
              ? endpoint.path.substring(1)
              : endpoint.path,
        )
      : null;
  return _PlanTestSession(
    binding,
    BehavioralMacosDriver(
      bridge: FakeAxDriverBridge(),
      targetPid: pid,
    ),
  );
}

final class _PlanTestSession implements ResolvedSession {
  _PlanTestSession(this.binding, this._behavioral) : driver = _behavioral;

  @override
  final SessionBinding binding;

  final BehavioralMacosDriver _behavioral;

  @override
  final AutomationDriver driver;

  @override
  Uri? get url => null;

  @override
  BehavioralDriver? asBehavioral() => _behavioral;

  @override
  Future<void> detach() => driver.close();
}

void main() {
  test('every committed declarative plan loads and validates', () async {
    final plansDir = Directory('plans');
    final files =
        plansDir
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.yaml'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    expect(files, isNotEmpty, reason: 'the declarative suite must not empty');

    for (final file in files) {
      final plan = await AutomationPlan.load(file.path);
      expect(
        plan.scenarios,
        isNotEmpty,
        reason: '${file.path} declares no scenario',
      );
      for (final scenario in plan.scenarios.values) {
        expect(scenario.steps, isNotEmpty);
      }
    }
  });

  test('handle-bound sessions take their anchor from the --set override; '
      'without one they fall back to the focused app', () async {
    final plan = await AutomationPlan.load('plans/desktop-smoke.yaml');
    final anchored = SessionRegistry(
      bindings: plan.sessions,
      overrides: const {'app': 'ax://pid/999999999'},
      factories: {
        AutomationTransport.osAccessibility: _hermeticOsAccessibilityFactory,
      },
    );
    final session = await anchored.attach('app');
    // The pid anchor binds directly (no running-apps probe); the driver
    // carries it as the ADR 0064 anchor.
    expect(
      (session.asBehavioral()! as MacosDriver).targetPid,
      999999999,
      reason: 'the environment override supplies the anchor',
    );
    await session.detach();

    final fallback = SessionRegistry(
      bindings: plan.sessions,
      factories: {
        AutomationTransport.osAccessibility: _hermeticOsAccessibilityFactory,
      },
    );
    if (Platform.isMacOS) {
      final unfocused = await fallback.attach('app');
      expect(
        (unfocused.asBehavioral()! as MacosDriver).targetPid,
        isNull,
        reason: 'no override = focused-app binding, never a silent guess',
      );
      await unfocused.detach();
    } else {
      expect(
        fallback.attach('app'),
        throwsA(isA<EndpointUnreachableException>()),
        reason: 'non-macOS hosts require an explicit OS endpoint override',
      );
    }
  });

  test(
    'the semantic-write wire forms round-trip through the plan model',
    () async {
      final plan = await AutomationPlan.load('plans/semantic-write.yaml');
      final steps = plan.onlyScenario!.steps;
      final act = steps.whereType<ActStep>().toList();
      expect(act, hasLength(1));
      final action = act.single.action;
      expect(action, isA<SetValueAction>());
      final setValue = action as SetValueAction;
      expect(setValue.value, 'declarative write');
      expect(setValue.role, 'textbox');
    },
  );

  test(
    'desktopOsAccessibilityFactory selects the host desktop driver',
    () async {
      final registry = SessionRegistry(
        bindings: const {},
        factories: {
          AutomationTransport.osAccessibility: desktopOsAccessibilityFactory,
        },
      );
      final session = await registry.attachApp(
        AutomationTransport.osAccessibility,
        pid: 4242,
      );
      if (Platform.isLinux) {
        expect(session.driver, isA<AtspiDriver>());
      } else if (Platform.isMacOS) {
        expect(session.driver, isA<MacosDriver>());
        expect((session.driver as MacosDriver).targetPid, 4242);
      }
      await session.detach();
    },
    tags: ['os-integration'],
  );
}
