import 'dart:io';

import 'automation_exceptions.dart';

/// URI schemes a desktop driver will hand to the OS shell (ADR 0003).
/// Everything else — notably `javascript:` and `data:` — refuses loudly:
/// the opener asks the operating system to handle the URL, and the
/// allowlist keeps that surface inert.
const systemOpenUrlSchemes = <String>{'http', 'https', 'file', 'mailto'};

/// The scheme allowlist gate (ADR 0003), shared by every desktop
/// driver's NavigateAction lowering: [openUrlViaSystem] applies it
/// before spawning, and drivers apply it before their injected opener
/// seam — an injected no-op must not bypass the guard.
void validateOpenableUrl(Uri url) {
  if (!systemOpenUrlSchemes.contains(url.scheme)) {
    throw DriverUnsupportedException(
      'refusing to open "${url.scheme}:" URLs in the system browser '
      '(allowlist: ${systemOpenUrlSchemes.join(", ")}); use an '
      'instrumented tier for custom schemes',
      details: const {
        'remedy': 'use an http/https/file/mailto URL',
      },
    );
  }
}

/// Opens [url] through the platform's default handler (`open` on macOS,
/// `xdg-open` on Linux, `cmd /c start` on Windows) — the desktop-tier
/// lowering of `NavigateAction` (ADR 0003). The opened browser is an
/// untracked surface: the OS owns the process; this call never inspects
/// or drives it.
///
/// The scheme allowlist is checked before anything is spawned. Test
/// seams inject a recording no-op instead of this function.
Future<void> openUrlViaSystem(Uri url) async {
  validateOpenableUrl(url);
  if (Platform.isMacOS) {
    await _run('open', [url.toString()]);
  } else if (Platform.isLinux) {
    await _run('xdg-open', [url.toString()]);
  } else if (Platform.isWindows) {
    await _run('cmd', ['/c', 'start', '', url.toString()]);
  } else {
    throw const DriverUnsupportedException(
      'no system URL opener on this platform',
    );
  }
}

Future<void> _run(String executable, List<String> arguments) async {
  final result = await Process.run(executable, arguments);
  if (result.exitCode != 0) {
    throw DriverUnsupportedException(
      'system URL opener "$executable" failed '
      '(exit ${result.exitCode}): ${result.stderr}',
      details: {'executable': executable},
    );
  }
}
