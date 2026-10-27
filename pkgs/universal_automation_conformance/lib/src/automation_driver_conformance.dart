import 'dart:async';

import 'package:test/test.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';

/// Contract suite for [AutomationDriver] implementations.
///
/// Adopt it with one call; every test builds a fresh driver via
/// [createDriver]. Tests are skipped automatically when the driver's
/// capability set excludes the exercised feature.
void automationDriverConformanceTests(
  String scenario, {
  required Future<AutomationDriver> Function() createDriver,
}) {
  group('$scenario driver conformance', () {
    test('declares attach and does not lie about capabilities', () async {
      final driver = await createDriver();
      addTearDown(driver.close);
      expect(driver.capabilities.attach, isTrue);
    });

    test('snapshot returns a valid semantic tree', () async {
      final driver = await createDriver();
      addTearDown(driver.close);
      if (!driver.capabilities.a11yTree) {
        return;
      }
      final snapshot = await driver.snapshot();
      expect(snapshot.roots, isNotEmpty);
      expect(snapshot.capturedAt.isBefore(DateTime.now()), isTrue);
      expect(snapshot.revision, greaterThanOrEqualTo(0));
      for (final node in snapshot.nodes) {
        expect(node.role, isNotEmpty);
      }
    });

    test(
      'navigate refuses non-allowlisted schemes loudly (universal)',
      () async {
        final driver = await createDriver();
        addTearDown(driver.close);
        // ADR 0003: the scheme allowlist binds NavigateAction on every
        // tier — desktop drivers refuse before the system-browser seam,
        // protocol drivers refuse before the navigation command. What is
        // never allowed is silent success.
        await expectLater(
          driver.perform(NavigateAction(Uri.parse('javascript:alert(1)'))),
          throwsA(isA<DriverUnsupportedException>()),
        );
      },
    );

    test('navigate capability performs allowlisted navigation', () async {
      final driver = await createDriver();
      addTearDown(driver.close);
      if (!driver.capabilities.navigate) {
        return;
      }
      // A navigate-capable driver drives an allowlisted navigation
      // without error — protocol tiers navigate their fake endpoints in
      // conformance; desktop tiers route through the injected no-op
      // opener seam (ADR 0003). No side effects here either way.
      await driver.perform(
        NavigateAction(Uri.parse('https://conformance.invalid/blank')),
      );
    });

    test('screenshot returns encoded bytes', () async {
      final driver = await createDriver();
      addTearDown(driver.close);
      if (!driver.capabilities.screenshot) {
        return;
      }
      final bytes = await driver.screenshot();
      expect(bytes, isNotEmpty);
    });

    test('close is idempotent', () async {
      final driver = await createDriver();
      await driver.close();
      await driver.close();
    });
  });
}
