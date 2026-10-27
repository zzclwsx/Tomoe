import 'dart:convert';
import 'dart:io';

import 'package:kazumi/services/update/windows_update_helper.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> arguments) async {
  final workspace = Directory(arguments[0]);
  final config = File(p.join(workspace.path, 'config.json'));
  final values =
      jsonDecode(await config.readAsString()) as Map<String, dynamic>;
  values['parentPid'] = pid;
  await config.writeAsString(jsonEncode(values), flush: true);
  await startWindowsUpdateHelper(
    workspace: workspace,
    powershell: arguments[1],
  );
  await File(
    p.join(workspace.path, 'install.request'),
  ).writeAsString('install', flush: true);
  exit(0);
}
