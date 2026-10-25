import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:kazumi/utils/crypto.dart';
import 'package:kazumi/utils/file_system.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PortableUpdateException implements Exception {
  const PortableUpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PreparedWindowsUpdate {
  PreparedWindowsUpdate._(this.workspace);
  final Directory workspace;

  /// Called only after the preparation dialog completed without cancellation.
  Future<void> requestInstall() => File(
    p.join(workspace.path, 'install.request'),
  ).writeAsString('install', flush: true);
}

/// The helper prepares the archive while this process is alive, then waits for
/// our exact PID to exit before replacing any file. Paths are JSON data, never
/// interpolated into shell commands.
class WindowsPortableUpdater {
  static String get currentDirectory =>
      File(Platform.resolvedExecutable).parent.path;

  static String get powershell => p.join(
    Platform.environment['SystemRoot'] ?? r'C:\Windows',
    'System32',
    'WindowsPowerShell',
    'v1.0',
    'powershell.exe',
  );

  static Future<void> checkTarget(String directory) async {
    final absolute = p.normalize(p.absolute(directory));
    if (p.dirname(absolute) == absolute) {
      throw const PortableUpdateException('请选择软件目录，不要选择磁盘根目录');
    }
    final target = Directory(absolute);
    if (!await target.exists()) {
      throw const PortableUpdateException('所选目录不存在');
    }
    var ancestor = absolute;
    while (true) {
      if (await FileSystemEntity.isLink(ancestor)) {
        throw const PortableUpdateException('请选择实际目录，不要选择符号链接或目录联接');
      }
      final parent = p.dirname(ancestor);
      if (parent == ancestor) break;
      ancestor = parent;
    }
    // The PowerShell helper also checks every existing ancestor and file for
    // junctions, directory conflicts, and the Tomoe product identity.
    if (!await target.list().isEmpty &&
        !await File(p.join(absolute, 'tomoe.exe')).exists()) {
      throw const PortableUpdateException('请选择空目录或已有的同映目录');
    }
    await ensureDirectoryWritable(absolute);
  }

  static Future<PreparedWindowsUpdate> prepare({
    required String archivePath,
    required String expectedHash,
    required String targetDirectory,
  }) async {
    if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(expectedHash)) {
      throw const PortableUpdateException('更新包缺少有效的 SHA-256 校验值，请重新检查更新');
    }
    if ((await calculateFileHash(File(archivePath))).toLowerCase() !=
        expectedHash.toLowerCase()) {
      throw const PortableUpdateException('更新包校验失败，请重新下载');
    }
    await checkTarget(targetDirectory);
    final temporary = await getTemporaryDirectory();
    final workspace = await temporary.createTemp('tomoe-update-');
    final script = File(p.join(workspace.path, 'update.ps1'));
    // A BOM allows Windows PowerShell 5.1 to read UTF-8 consistently.
    await script.writeAsString(
      '\uFEFF${await rootBundle.loadString('assets/update/windows_update.ps1')}',
      flush: true,
    );
    final config = File(p.join(workspace.path, 'config.json'));
    await config.writeAsString(
      jsonEncode({
        'archivePath': p.absolute(archivePath),
        'expectedHash': expectedHash,
        'targetDirectory': p.absolute(targetDirectory),
        'parentPid': pid,
        'originalExecutable': Platform.resolvedExecutable,
        'restart': true,
        'showError': true,
      }),
      flush: true,
    );
    final helper = await Process.start(powershell, [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-WindowStyle',
      'Hidden',
      '-File',
      script.path,
      '-ConfigPath',
      config.path,
    ], mode: ProcessStartMode.detached);
    final statusFile = File(p.join(workspace.path, 'status.json'));
    final timer = Stopwatch()..start();
    while (timer.elapsed < const Duration(seconds: 60)) {
      if (await statusFile.exists()) {
        final state = jsonDecode(await statusFile.readAsString()) as Map;
        if (state['state'] == 'ready') {
          return PreparedWindowsUpdate._(workspace);
        }
        throw PortableUpdateException(
          '更新准备失败，软件未退出。请手动解压覆盖，或查看日志：${workspace.path}',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    // No application exit occurs on preparation failure or timeout.
    Process.killPid(helper.pid);
    throw PortableUpdateException('更新准备超时，软件未退出。可手动解压覆盖。日志：${workspace.path}');
  }
}
