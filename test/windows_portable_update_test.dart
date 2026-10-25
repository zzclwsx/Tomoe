import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/update/windows_portable_updater.dart';
import 'package:path/path.dart' as p;

void main() {
  group('Windows portable update helper', () {
    late Directory root;
    late Directory target;
    late File executable;
    late Directory workspace;
    late File archive;
    late String originalExecutable;
    Process? parent;
    Process? helper;
    Process? lock;
    final output = StringBuffer();
    final fixture = p.absolute('test/support/portable_update_fixture.ps1');

    Future<ProcessResult> powershell(List<String> arguments) =>
        Process.run(WindowsPortableUpdater.powershell, [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-WindowStyle',
          'Hidden',
          ...arguments,
        ]);
    Future<void> eventually(Future<bool> Function() check) async {
      final elapsed = Stopwatch()..start();
      while (!await check()) {
        if (elapsed.elapsed > const Duration(seconds: 25)) {
          fail('Update helper did not settle: $output');
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }

    Future<Map<String, dynamic>?> state() async {
      final file = File(p.join(workspace.path, 'status.json'));
      if (!await file.exists()) return null;
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    }

    Future<void> zip({Map<String, List<int>>? entries}) async {
      final spec = File(p.join(root.path, 'entries.json'));
      await spec.writeAsString(
        jsonEncode(
          (entries ??
                  {
                    'tomoe.exe': await executable.readAsBytes(),
                    'flutter_windows.dll': utf8.encode('new flutter'),
                    'data/app.so': utf8.encode('new application'),
                    'new-file.txt': utf8.encode('added'),
                    'locked.txt': utf8.encode('new locked'),
                  })
              .entries
              .map(
                (entry) => {
                  'name': entry.key,
                  'base64': base64Encode(entry.value),
                },
              )
              .toList(),
        ),
      );
      final result = await powershell([
        '-File',
        fixture,
        '-ZipSpec',
        spec.path,
        '-ZipPath',
        archive.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    }

    Future<void> start({
      String? hash,
      bool restart = false,
      bool approve = true,
    }) async {
      parent = await Process.start(WindowsPortableUpdater.powershell, [
        '-NoProfile',
        '-NonInteractive',
        '-WindowStyle',
        'Hidden',
        '-Command',
        'Start-Sleep -Seconds 90',
      ]);
      unawaited(parent!.stdout.drain<void>());
      unawaited(parent!.stderr.drain<void>());
      final script = File(p.join(workspace.path, 'update.ps1'));
      await script.writeAsString(
        '\uFEFF${await File('assets/update/windows_update.ps1').readAsString()}',
      );
      final config = File(p.join(workspace.path, 'config.json'));
      await config.writeAsString(
        jsonEncode({
          'archivePath': archive.path,
          'expectedHash':
              hash ?? sha256.convert(await archive.readAsBytes()).toString(),
          'targetDirectory': target.path,
          'parentPid': parent!.pid,
          'originalExecutable': originalExecutable,
          'restart': restart,
          'showError': false,
        }),
      );
      if (approve) {
        await File(
          p.join(workspace.path, 'install.request'),
        ).writeAsString('install');
      }
      helper = await Process.start(WindowsPortableUpdater.powershell, [
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
      ]);
      helper!.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(output.write);
      helper!.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(output.write);
      await eventually(() async => await state() != null);
      output.write(await state());
    }

    Future<int> finish() => helper!.exitCode.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        helper!.kill();
        fail('Helper did not exit: $output');
      },
    );
    setUp(() async {
      output.clear();
      root = await Directory(
        p.absolute('.dart_tool'),
      ).createTemp('portable-update-tests-');
      target = await Directory(
        p.join(root.path, "同映 空格 [v1] & O'Neil"),
      ).create();
      workspace = await Directory(
        p.join(root.path, 'tomoe-update-fixture'),
      ).create();
      archive = File(p.join(root.path, 'package.zip'));
      executable = File(p.join(root.path, 'fixture.exe'));
      final compiled = await powershell([
        '-File',
        fixture,
        '-ExecutablePath',
        executable.path,
      ]);
      expect(
        compiled.exitCode,
        0,
        reason: '${compiled.stdout}\n${compiled.stderr}',
      );
      await executable.copy(p.join(target.path, 'tomoe.exe'));
      originalExecutable = p.join(target.path, 'tomoe.exe');
      await File(
        p.join(target.path, 'flutter_windows.dll'),
      ).writeAsString('old flutter');
      await Directory(p.join(target.path, 'data')).create();
      await File(
        p.join(target.path, 'data', 'app.so'),
      ).writeAsString('old application');
      await File(p.join(target.path, 'locked.txt')).writeAsString('old locked');
      await File(
        p.join(target.path, 'personal-note.txt'),
      ).writeAsString('keep me');
    });
    tearDown(() async {
      for (final process in [parent, helper, lock]) {
        if (process != null) {
          process.kill();
          await process.exitCode;
        }
      }
      parent = helper = lock = null;
      expect(p.isWithin(p.absolute('.dart_tool'), root.path), isTrue);
      expect(p.basename(root.path), startsWith('portable-update-tests-'));
      await root.delete(recursive: true);
    });
    test(
      'waits for old process, replaces the current directory and preserves unrelated files',
      () async {
        await zip();
        await start();
        expect((await state())!['state'], 'ready', reason: output.toString());
        expect(
          await File(p.join(target.path, 'data', 'app.so')).readAsString(),
          'old application',
        );
        parent!.kill();
        expect(await finish(), 0, reason: output.toString());
        expect((await state())!['state'], 'success');
        expect(
          await File(p.join(target.path, 'data', 'app.so')).readAsString(),
          'new application',
        );
        expect(
          await File(p.join(target.path, 'personal-note.txt')).readAsString(),
          'keep me',
        );
        expect(
          await Directory(p.join(workspace.path, 'backup')).exists(),
          isFalse,
        );
      },
    );
    test(
      'starts the updated application with the installation working directory',
      () async {
        await zip();
        await start(restart: true);
        expect((await state())!['state'], 'ready', reason: output.toString());
        parent!.kill();
        expect(await finish(), 0, reason: output.toString());
        expect(
          await File(p.join(target.path, 'started.txt')).readAsString(),
          target.path,
        );
        await Future<void>.delayed(const Duration(seconds: 3));
      },
    );
    test(
      'rejects a checksum mismatch before changing or closing the old application',
      () async {
        await zip();
        await start(hash: '0' * 64);
        expect(await finish(), 1);
        expect((await state())!['state'], 'failed');
        expect(
          await File(p.join(target.path, 'data', 'app.so')).readAsString(),
          'old application',
        );
      },
    );
    test(
      'can install into a chosen empty directory without moving user data',
      () async {
        final original = target;
        target = await Directory(p.join(root.path, '选择的新目录')).create();
        await zip();
        await start();
        expect((await state())!['state'], 'ready', reason: output.toString());
        parent!.kill();
        expect(await finish(), 0, reason: output.toString());
        expect(
          await File(p.join(target.path, 'data', 'app.so')).readAsString(),
          'new application',
        );
        expect(
          await File(p.join(original.path, 'data', 'app.so')).readAsString(),
          'old application',
        );
        expect(
          await File(p.join(original.path, 'personal-note.txt')).readAsString(),
          'keep me',
        );
      },
    );
    test('rejects incomplete packages before the application exits', () async {
      await zip(entries: {'tomoe.exe': await executable.readAsBytes()});
      await start();
      expect(await finish(), 1);
      expect((await state())!['state'], 'failed');
      expect(
        await File(p.join(target.path, 'data', 'app.so')).readAsString(),
        'old application',
      );
    });
    test('rejects case-insensitive duplicate paths', () async {
      await zip(
        entries: {
          'tomoe.exe': await executable.readAsBytes(),
          'TOMOE.EXE': await executable.readAsBytes(),
        },
      );
      await start();
      expect(await finish(), 1);
      expect((await state())!['state'], 'failed');
      expect((await state())!['message'], contains('duplicate'));
    });
    test(
      'rejects ZIP traversal without writing outside the staging directory',
      () async {
        await zip(entries: {'../escaped.txt': utf8.encode('unsafe')});
        await start();
        expect(await finish(), 1);
        expect((await state())!['state'], 'failed');
        expect(
          await File(p.join(workspace.path, 'escaped.txt')).exists(),
          isFalse,
        );
        expect(
          await File(p.join(target.path, 'data', 'app.so')).readAsString(),
          'old application',
        );
      },
    );
    test('an invalid workspace cannot clean unrelated directories', () async {
      workspace = await Directory(
        p.join(root.path, 'unrelated-workspace'),
      ).create();
      final sentinel = File(p.join(workspace.path, 'stage', 'keep.txt'));
      await sentinel.parent.create();
      await sentinel.writeAsString('keep');
      await zip();
      await start();
      expect(await finish(), 1);
      expect(await sentinel.readAsString(), 'keep');
      expect((await state())!['state'], 'failed');
    });
    test(
      'cancelling preparation never installs on a later application exit',
      () async {
        await zip();
        await start(approve: false);
        expect((await state())!['state'], 'ready', reason: output.toString());
        parent!.kill();
        expect(await finish(), 1);
        expect((await state())!['state'], 'failed');
        expect(
          await Directory(p.join(workspace.path, 'stage')).exists(),
          isFalse,
        );
        expect(
          await File(p.join(target.path, 'data', 'app.so')).readAsString(),
          'old application',
        );
      },
    );
    test(
      'a write failure rolls back changed files and removes newly added files',
      () async {
        await zip();
        await start();
        expect((await state())!['state'], 'ready', reason: output.toString());
        final lockReady = File(p.join(root.path, 'locked.ready'));
        lock = await Process.start(WindowsPortableUpdater.powershell, [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-WindowStyle',
          'Hidden',
          '-File',
          fixture,
          '-LockPath',
          p.join(target.path, 'locked.txt'),
          '-LockReady',
          lockReady.path,
        ]);
        unawaited(lock!.stdout.drain<void>());
        unawaited(lock!.stderr.drain<void>());
        await eventually(lockReady.exists);
        parent!.kill();
        expect(await finish(), 1, reason: output.toString());
        expect(
          (await state())!['state'],
          'rolledBack',
          reason: output.toString(),
        );
        expect(
          await File(p.join(target.path, 'data', 'app.so')).readAsString(),
          'old application',
        );
        expect(
          await File(p.join(target.path, 'flutter_windows.dll')).readAsString(),
          'old flutter',
        );
        expect(
          await File(p.join(target.path, 'new-file.txt')).exists(),
          isFalse,
        );
        expect(
          await File(p.join(target.path, 'personal-note.txt')).readAsString(),
          'keep me',
        );
      },
    );
  }, skip: !Platform.isWindows);
}
