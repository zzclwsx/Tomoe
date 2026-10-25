import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/plugins/api_rule_config.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/services/player/watch_room_models.dart';
import 'package:kazumi/services/plugin/api_rule_engine.dart';
import 'package:kazumi/services/plugin/plugin_import_parser.dart';
import 'package:kazumi/utils/encoding.dart';

void main() {
  const engine = ApiRuleStrategy();
  final raw = jsonEncode({
    'items': [
      {'name': '测试番剧', 'id': '番剧/a?b'},
    ],
  });
  ApiSearchConfig config(String template) => ApiSearchConfig(
    listPath: r'$.items[*]',
    namePath: r'$.name',
    sourcePath: r'$.id',
    sourceTemplate: template,
  );

  test(
    'API 9 detail template encodes source and supports adjacent literals',
    () {
      final results = engine.parseSearch(
        raw,
        config(' https://example.com/GV@source '),
      );
      expect(
        results.items.single.src,
        'https://example.com/GV${Uri.encodeComponent('番剧/a?b')}',
      );
      expect(engine.parseSearch(raw, config('')).items.single.src, '番剧/a?b');
      expect(
        () => engine.validateSearchConfig(config('https://example.com/detail')),
        throwsA(isA<ApiRuleFormatException>()),
      );
    },
  );

  test(
    'API 9 templates survive JSON and shared-link import; newer API is rejected',
    () {
      final rule = Plugin.fromJson({
        'api': '9',
        'name': 'API9',
        'version': '1.0',
        'baseURL': 'https://example.com',
        'searchMode': 'api',
        'chapterMode': 'api',
        'searchApiConfig': config('https://example.com/GV@source').toJson(),
        'chapterApiConfig': {
          'request': {'url': 'https://example.com/detail?source=@source'},
        },
      });
      expect(ApiEndpoints.apiLevel, 9);
      final imported = PluginImportParser.parse(
        jsonToKazumiBase64(jsonEncode(rule.toJson())),
      );
      expect(imported.failureCount, 0);
      expect(
        imported.plugins.single.searchApiConfig.sourceTemplate,
        'https://example.com/GV@source',
      );
      expect(imported.plugins.single.toJson(), rule.toJson());
      final newer = PluginImportParser.parse(
        jsonEncode({...rule.toJson(), 'api': '10'}),
      );
      expect(newer.plugins, isEmpty);
      expect(newer.failureCount, 1);
    },
  );

  test('room snapshots retain API search IDs and templated detail URLs', () {
    for (final source in [
      '22639',
      engine
          .parseSearch(raw, config('https://example.com/GV@source'))
          .items
          .single
          .src,
    ]) {
      final content = RoomContent(
        id: 'api9',
        bangumiId: 42,
        name: '测试番剧',
        pluginName: 'API9',
        pluginVersion: '1.0',
        source: source,
        roadName: '线路一',
        road: 0,
        episode: 1,
        episodeName: '第1集',
        pageUrl: 'https://example.com/play/1',
      );
      final snapshot = RoomSnapshot(
        host: 'host',
        mode: WatchRoomMode.everyone,
        content: content,
      );
      expect(RoomSnapshot.decode(snapshot.encode())!.content!.source, source);
    }
  });
}
