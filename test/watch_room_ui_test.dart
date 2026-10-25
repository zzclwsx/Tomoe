import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/player/syncplay_sheet.dart';
import 'package:kazumi/services/player/watch_room_service.dart';

class _PreviewRoom extends WatchRoomService {
  _PreviewRoom() : super.forEndpoint(() => 'syncplay.pl:8996') {
    snapshot = const RoomSnapshot(
      host: 'Kazumi',
      mode: WatchRoomMode.hostOnly,
      content: RoomContent(
        id: 'preview',
        bangumiId: 42,
        name: '葬送的芙莉莲',
        pluginName: '示例播放源',
        pluginVersion: '1',
        source: '/anime/42',
        roadName: '线路一',
        road: 0,
        episode: 3,
        episodeName: '第 3 集',
        pageUrl: '/play/3',
      ),
    );
    members.addAll({'Kazumi': true, 'Friend': false});
  }
  @override
  bool get hasSession => true;
  @override
  bool get connected => true;
  @override
  String get room => '+12345678:0123456789ab';
  @override
  int get rtt => 82;
  @override
  String get username => 'Kazumi';
  @override
  bool get isHost => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('NotoSansSC')
      ..addFont(rootBundle.load('assets/fonts/NotoSansSC.ttf'));
    await loader.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final size in [
    const Size(390, 844),
    const Size(900, 680),
    const Size(844, 390),
  ]) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets('room management fits $size $brightness', (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final service = _PreviewRoom();
        addTearDown(service.dispose);
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                useMaterial3: true,
                fontFamily: 'NotoSansSC',
                colorSchemeSeed: Colors.green,
                brightness: brightness,
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: FilledButton(
                      onPressed: () =>
                          showSyncPlaySheet(context, room: service),
                      child: const Text('一起看'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('一起看'));
        await tester.pumpAndSettle();
        expect(find.text('房间控制'), findsOneWidget);
        expect(find.text('房主控制'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (size.width == 900) {
          expect(find.text('跟随播放').hitTestable(), findsOneWidget);
          expect(find.text('同步房间进度').hitTestable(), findsOneWidget);
        }
        if (size.width == 900) {
          await tester.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            await File(
              '.dart_tool/watch-room-${brightness.name}.png',
            ).writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
