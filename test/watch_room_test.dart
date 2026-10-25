import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/services/player/watch_room_service.dart';
import 'package:kazumi/services/player/syncplay_client.dart';
import 'package:kazumi/services/player/watch_room_playback_coordinator.dart';
import 'support/syncplay_test_server.dart';

RoomContent content(
  String id, {
  int bangumi = 42,
  int episode = 2,
  String source = '/anime/42',
}) => RoomContent(
  id: id,
  bangumiId: bangumi,
  name: '测试番剧 {星空}',
  pluginName: '测试源',
  pluginVersion: '1',
  source: source,
  roadName: '线路二',
  road: 1,
  episode: episode,
  episodeName: '第 $episode 集',
  pageUrl: 'https://example.com/play/$episode',
);

RoomPlaybackBinding binding({
  RoomContent? Function()? getContent,
  bool Function()? ready,
  Future<void> Function(RoomContent)? onSwitch,
  Future<void> Function(RoomTimeline, bool)? apply,
}) => RoomPlaybackBinding(
  content: getContent ?? () => content('local'),
  ready: ready ?? () => true,
  position: () => 120,
  playing: () => true,
  apply: apply ?? (_, _) async {},
  switchContent: onSwitch ?? (_) async {},
);

void main() {
  test('native protocol handshake', () async {
    final server = SyncplayTestServer();
    await server.start();
    final client = SyncplayClient(
      host: '127.0.0.1',
      port: int.parse(server.endpoint.split(':').last),
    );
    final errors = <Object>[];
    client.onGeneralMessage.listen((_) {}, onError: errors.add);
    try {
      await client.connect(enableTLS: false);
      await client.joinRoom('12345678', 'Host');
      final managed = await client.createControlledRoom(
        '12345678',
        'AB-123-456',
      );
      await client.switchRoom(managed);
      await client.authenticateController('AB-123-456');
      expect(errors, isEmpty);
    } finally {
      await client.disconnect();
      await server.close();
    }
  });
  test(
    'snapshot round trips Unicode/braces and rejects unknown or malformed payloads',
    () {
      final encoded = RoomSnapshot(
        host: 'Host',
        mode: WatchRoomMode.hostOnly,
        content: content('a'),
      ).encode();
      expect(RoomSnapshot.decode(encoded)!.content!.name, '测试番剧 {星空}');
      expect(RoomSnapshot.decode('other-client'), isNull);
      expect(RoomSnapshot.decode('${RoomSnapshot.prefix}{'), isNull);
      expect(
        RoomSnapshot.decode(
          '${RoomSnapshot.prefix}{"host":"x","mode":"new-mode"}',
        ),
        isNull,
      );
    },
  );
  test('playlist confirmation is cancelled cleanly on disconnect', () async {
    final server = SyncplayTestServer();
    await server.start();
    final client = SyncplayClient(
      host: '127.0.0.1',
      port: int.parse(server.endpoint.split(':').last),
    );
    client.onGeneralMessage.listen((_) {}, onError: (_) {});
    try {
      await client.connect(enableTLS: false);
      await client.joinRoom('+12345678:0123456789ab', 'Guest');
      final pending = expectLater(
        client.setPlaylistAndWaitForEcho(['not-authorized']),
        throwsA(isA<SyncplayConnectionException>()),
      );
      await Future<void>.delayed(Duration.zero);
      await client.disconnect();
      await pending;
    } finally {
      await client.disconnect();
      await server.close();
    }
  });
  test(
    'timeline adds only local elapsed time, never advances a paused sample',
    () {
      var elapsed = const Duration(milliseconds: 350);
      final playing = RoomTimeline(
        position: 120,
        paused: false,
        elapsed: () => elapsed,
      );
      final paused = RoomTimeline(
        position: 120,
        paused: true,
        elapsed: () => elapsed,
      );
      expect(playing.target, closeTo(120.35, 0.001));
      elapsed = const Duration(seconds: 3);
      expect(playing.target, 123);
      expect(paused.target, 120);
    },
  );
  test(
    'episode matching survives reordered roads and episodes; missing episodes fail',
    () {
      final roads = [
        Road(name: '线路二', data: ['/play/2', '/play/1'], identifier: ['2', '1']),
      ];
      expect(resolveRoomEpisode(roads, content('a'), 'https://example.com'), (
        episode: 1,
        road: 0,
      ));
      expect(
        () => resolveRoomEpisode(
          roads,
          content('b', episode: 3),
          'https://example.com',
        ),
        throwsStateError,
      );
    },
  );

  group('TCP room lifecycle', () {
    late SyncplayTestServer server;
    late WatchRoomService host;
    late WatchRoomService guest;
    setUp(() async {
      server = SyncplayTestServer();
      await server.start();
      host = WatchRoomService.forEndpoint(() => server.endpoint);
      guest = WatchRoomService.forEndpoint(() => server.endpoint);
    });
    tearDown(() async {
      await host.leave();
      await guest.leave();
      host.dispose();
      guest.dispose();
      await server.close();
    });
    test(
      'API 9 raw IDs and detail templates survive TCP selection broadcasts',
      () async {
        await host.create('12345678', 'Host', WatchRoomMode.everyone);
        final followed = <RoomContent>[];
        guest.openContent = (value) async {
          followed.add(value);
        };
        await guest.join(host.room, 'Guest');
        await eventually(() => guest.snapshot != null);
        final sources = [
          '22639',
          'https://example.com/GV%E7%95%AA%E5%89%A7%2Fa',
        ];
        for (var index = 0; index < sources.length; index++) {
          expect(
            await host.select(content('api9-$index', source: sources[index])),
            isTrue,
          );
          await eventually(() => followed.length == index + 1);
          expect(followed.last.source, sources[index]);
        }
      },
    );
    test(
      'host-only authenticates natively, denies guests and restores late-join content',
      () async {
        await host.create('12345678', 'Host', WatchRoomMode.hostOnly);
        expect(host.connected, isTrue, reason: host.error);
        expect(host.room, startsWith('+12345678:'));
        expect(host.canControl, isTrue);
        host.attach(binding());
        await host.select(content('first'));
        RoomContent? followed;
        guest.openContent = (value) async {
          followed = value;
        };
        await guest.join(host.room, 'Guest');
        await eventually(() => followed != null);
        expect(followed!.id, 'first');
        expect(guest.canControl, isFalse);
        expect(await guest.select(content('denied')), isFalse);
        expect(host.snapshot!.content!.id, 'first');
      },
    );
    test(
      'content broadcasts before readiness, loading follower catches up, detach never pauses room',
      () async {
        await host.create('12345678', 'Host', WatchRoomMode.everyone);
        await guest.join(host.room, 'Guest');
        await eventually(() => guest.snapshot != null);
        var ready = false;
        var switches = 0;
        final applied = <double>[];
        final local = binding(
          ready: () => ready,
          onSwitch: (_) async {
            switches++;
          },
          apply: (state, _) async {
            applied.add(state.target);
          },
        );
        host.attach(binding());
        guest.attach(local);
        expect(await host.select(content('early')), isTrue);
        await eventually(() => switches == 1);
        expect(applied, isEmpty);
        await host.publish(position: 120, paused: false, doSeek: true);
        await eventually(() => guest.timeline?.position == 120);
        await Future<void>.delayed(const Duration(milliseconds: 40));
        ready = true;
        await guest.playerReady();
        await eventually(() => applied.isNotEmpty);
        expect(applied.last, greaterThan(120.02));
        final before = server.controls;
        guest.detach(local);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(guest.connected, isTrue);
        expect(server.controls, before);
        expect(server.states[host.room]!.paused, isFalse);
      },
    );
    test(
      'same episode in a different anime is still a content change',
      () async {
        await host.create('12345678', 'Host', WatchRoomMode.everyone);
        await guest.join(host.room, 'Guest');
        await eventually(() => guest.snapshot != null);
        final seen = <int>[];
        guest.openContent = (item) async {
          seen.add(item.bangumiId);
        };
        host.attach(binding());
        await host.select(content('a'));
        await eventually(() => seen.length == 1);
        await host.select(content('b', bangumi: 99));
        await eventually(() => seen.length == 2);
        expect(seen, [42, 99]);
      },
    );
    test(
      'playing an existing local video in an empty room announces its content',
      () async {
        await host.create('12345678', 'Host', WatchRoomMode.everyone);
        RoomContent? followed;
        host.openContent = (value) async {
          followed = value;
        };
        guest.attach(binding());
        await guest.join(host.room, 'Guest');
        await eventually(() => guest.snapshot != null);
        await guest.publish(position: 120, paused: false);
        await eventually(() => followed != null);
        expect(followed!.bangumiId, 42);
        expect(guest.snapshot!.content, isNotNull);
      },
    );
    test(
      'delayed own playlist echoes cannot replace a newer local selection',
      () async {
        await host.create('12345678', 'Host', WatchRoomMode.everyone);
        host.attach(binding());
        expect(await host.select(content('first')), isTrue);
        expect(await host.select(content('second')), isTrue);
        expect(host.snapshot!.content!.id, 'second');
        await eventually(() {
          final files = server.playlists[host.room];
          return files != null &&
              RoomSnapshot.decode(files.single)?.content?.id == 'second';
        });
        expect(host.snapshot!.content!.id, 'second');
      },
    );
    test(
      'repeated mode migrations retain membership and revoke guest control',
      () async {
        await host.create('12345678', 'Host', WatchRoomMode.everyone);
        await guest.join(host.room, 'Guest');
        await eventually(() => guest.canControl);
        Future<void> settled(
          int round,
          String stage,
          bool Function() check,
        ) async {
          try {
            await eventually(check);
          } catch (_) {
            fail(
              'round $round $stage: '
              'host=${host.room}/${host.snapshot?.mode}/${host.error}, '
              'guest=${guest.room}/${guest.snapshot?.mode}/${guest.error}, '
              'members=${guest.members.keys}, hostOnline=${guest.hostOnline}',
            );
          }
        }

        for (var round = 0; round < 12; round++) {
          final oldRoom = host.room;
          await host.changeMode(WatchRoomMode.hostOnly);
          await settled(
            round,
            'host-only',
            () =>
                guest.connected &&
                guest.room == host.room &&
                guest.room != oldRoom,
          );
          expect(host.canControl, isTrue);
          expect(guest.canControl, isFalse);
          await host.changeMode(WatchRoomMode.everyone);
          await settled(
            round,
            'everyone',
            () =>
                guest.connected && guest.room == host.room && guest.canControl,
          );
        }
      },
    );
    test(
      'manual reconnect retains owner authentication and does not reopen an exited player',
      () async {
        await host.create('12345678', 'Host', WatchRoomMode.hostOnly);
        final room = host.room;
        await host.reconnect();
        expect(host.connected, isTrue);
        expect(host.room, room);
        expect(host.canControl, isTrue);
      },
    );
    test(
      'TCP frame preserves split UTF-8 and braces inside chat strings',
      () async {
        await host.create('12345678', 'Host', WatchRoomMode.everyone);
        final received = host.chatStream.first;
        await server.fragmentedChat('你好 {');
        expect(
          (await received.timeout(const Duration(seconds: 2))).message,
          '你好 {',
        );
        expect(host.error, isNull);
      },
    );
  });
}
