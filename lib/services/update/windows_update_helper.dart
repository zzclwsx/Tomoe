import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class PortableUpdateException implements Exception {
  const PortableUpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Start the helper as a normal child: on Windows a detached PowerShell can
/// exit before executing its script. Windows keeps this child alive when the
/// parent exits; the helper waits for that exit before touching the program.
Future<void> startWindowsUpdateHelper({
  required Directory workspace,
  required String powershell,
  Duration timeout = const Duration(minutes: 3),
}) async {
  final process = await Process.start(powershell, [
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-WindowStyle',
    'Hidden',
    '-File',
    p.join(workspace.path, 'update.ps1'),
    '-ConfigPath',
    p.join(workspace.path, 'config.json'),
  ]);
  unawaited(process.stdout.drain<void>());
  final stderr = process.stderr
      .transform(const Utf8Decoder(allowMalformed: true))
      .fold<StringBuffer>(StringBuffer(), (buffer, text) {
        if (buffer.length < 32768) buffer.write(text);
        return buffer;
      });
  int? exitCode;
  unawaited(
    process.exitCode.then((value) {
      exitCode = value;
    }),
  );
  final statusFile = File(p.join(workspace.path, 'status.json'));
  final timer = Stopwatch()..start();
  while (timer.elapsed < timeout) {
    if (await statusFile.exists()) {
      final state = jsonDecode(await statusFile.readAsString()) as Map;
      if (state['state'] == 'ready') return;
      throw PortableUpdateException(
        '更新准备失败，软件未退出。请手动解压覆盖，或查看日志：${workspace.path}',
      );
    }
    if (exitCode != null) {
      final output = await stderr;
      await File(
        p.join(workspace.path, 'startup.log'),
      ).writeAsString('Helper exit code: $exitCode\n$output');
      throw PortableUpdateException(
        '更新助手启动失败（退出码 $exitCode），软件未退出。请手动解压覆盖，日志：${workspace.path}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  process.kill();
  throw PortableUpdateException('更新准备超时，软件未退出。可手动解压覆盖。日志：${workspace.path}');
}
