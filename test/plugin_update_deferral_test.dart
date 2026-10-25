import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/plugin/plugin_http_module.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';

Plugin rule(String name, String version) => Plugin.fromTemplate()
  ..name = name
  ..version = version;

void main() {
  test('room sessions defer downloads and retry works after leaving', () async {
    var inRoom = true;
    var downloads = 0;
    var writes = 0;
    final controller = PluginsController(
      shouldDeferRemoteUpdates: () => inRoom,
      pluginLoader: (name) async {
        downloads++;
        return rule(name, '2.0');
      },
      pluginJsonWriter: (_) async {
        writes++;
      },
    )..pluginList.add(rule('test', '1.0'));
    expect(
      await controller.tryUpdatePluginByName('test'),
      PluginUpdateResult.deferred,
    );
    expect(downloads, 0);
    expect(writes, 0);
    inRoom = false;
    expect(
      await controller.tryUpdatePluginByName('test'),
      PluginUpdateResult.updated,
    );
    expect(controller.pluginList.single.version, '2.0');
    expect(writes, 1);
  });

  test('joining a room during download preserves the installed rule', () async {
    var inRoom = false;
    var writes = 0;
    final downloading = Completer<void>();
    final remote = Completer<Plugin>();
    final controller = PluginsController(
      shouldDeferRemoteUpdates: () => inRoom,
      pluginLoader: (_) {
        downloading.complete();
        return remote.future;
      },
      pluginJsonWriter: (_) async {
        writes++;
      },
    )..pluginList.add(rule('test', '1.0'));
    final pending = controller.tryUpdatePluginByName('test');
    await downloading.future;
    inRoom = true;
    remote.complete(rule('test', '2.0'));
    expect(await pending, PluginUpdateResult.deferred);
    expect(controller.pluginList.single.version, '1.0');
    expect(writes, 0);
  });

  test(
    'batch updates defer during a room and unsupported APIs retain old rules',
    () async {
      var inRoom = true;
      var writes = 0;
      final controller = PluginsController(
        shouldDeferRemoteUpdates: () => inRoom,
        catalogLoader: () async => [
          PluginHTTPItem(
            name: 'test',
            version: '2.0',
            useNativePlayer: true,
            author: '',
            lastUpdate: 0,
          ),
        ],
        pluginLoader: (name) async => rule(name, '2.0')..api = '10',
        pluginJsonWriter: (_) async {
          writes++;
        },
      )..pluginList.add(rule('test', '1.0'));
      final deferred = await controller.tryUpdateAllPlugin();
      expect(deferred.deferred, 1);
      expect(deferred.updated, 0);
      inRoom = false;
      expect(
        await controller.tryUpdatePluginByName('test'),
        PluginUpdateResult.requiresNewerClient,
      );
      expect(controller.pluginList.single.version, '1.0');
      expect(writes, 0);
    },
  );
}
