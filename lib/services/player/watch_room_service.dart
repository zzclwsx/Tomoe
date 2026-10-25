import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/player/controller/player_models.dart';
import 'package:kazumi/services/player/syncplay_client.dart';
import 'package:kazumi/services/player/syncplay_endpoint.dart';
import 'package:kazumi/services/player/watch_room_models.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:mobx/mobx.dart';

export 'watch_room_models.dart';

class RoomPlaybackBinding {
  RoomPlaybackBinding({
    required this.content,
    required this.ready,
    required this.position,
    required this.playing,
    required this.apply,
    required this.switchContent,
    this.prepare,
  });
  final RoomContent? Function() content;
  final bool Function() ready;
  final double Function() position;
  final bool Function() playing;
  final Future<void> Function(RoomTimeline timeline, bool forceSeek) apply;
  final Future<void> Function(RoomContent content) switchContent;
  final Future<void> Function()? prepare;
  bool following = true;
  String? contentId;
  Object? route;
}

/// Application-owned connection; route bindings can detach without leaving.
class WatchRoomService extends ChangeNotifier implements Disposable {
  WatchRoomService()
    : this.forEndpoint(
        () => GStorage.getSetting(SettingsKeys.syncPlayEndPoint),
      );
  @visibleForTesting
  WatchRoomService.forEndpoint(this._endpoint);
  final String Function() _endpoint;
  String get endpoint => _endpoint();
  final _client = Observable<SyncplayClient?>(null);
  final _room = Observable('');
  final _rtt = Observable(0);
  SyncplayClient? get client => _client.value;
  String get room => _room.value;
  int get rtt => _rtt.value;
  bool get hasSession => client != null || reconnecting;
  bool get connected => room.isNotEmpty && client?.isConnected == true;
  bool connecting = false;
  final _reconnecting = Observable(false);
  bool get reconnecting => _reconnecting.value;
  set reconnecting(bool value) =>
      runInAction(() => _reconnecting.value = value);
  bool hostOnline = true;
  String? error;
  RoomSnapshot? snapshot;
  RoomTimeline? timeline;
  final Map<String, bool> members = {};
  RoomPlaybackBinding? binding;
  Future<void> Function(RoomContent content)? openContent;
  final _chat = StreamController<SyncPlayChatMessage>.broadcast();
  Stream<SyncPlayChatMessage> get chatStream => _chat.stream;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final _random = Random.secure();
  String? _ownerPassword;
  String _requestedUser = '';
  String _lastRoom = '';
  int _connection = 0;
  int _selection = 0;
  bool _disposed = false;
  bool _migrating = false;
  Timer? _retry;
  Timer? _readyPoll;
  RoomPlaybackBinding? _announcedBinding;
  String? _announcedContent;
  bool _snapshotReceived = false;
  String? _pendingLocalContentId;
  int _retryCount = 0;
  int _applyVersion = 0;
  RoomContent? _pendingFollow;
  RoomSnapshot? _pendingMigration;
  String? _waitingForReset;
  Future<void> _applyTail = Future.value();
  String newContentId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${_random.nextInt(1 << 30).toRadixString(36)}';
  int get playbackRevision => _selection;
  String get username => client?.username ?? _requestedUser;
  bool get isHost => _ownerPassword != null && snapshot?.host == username;
  bool get canControl =>
      !hasSession ||
      (connected &&
          snapshot != null &&
          (snapshot!.mode == WatchRoomMode.everyone || (isHost && hostOnline)));

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void reportError(Object value) {
    error = value.toString();
    _changed();
  }

  Future<void> create(
    String roomNumber,
    String user,
    WatchRoomMode mode,
  ) async {
    await leave();
    _requestedUser = user;
    _ownerPassword = SyncplayClient.generateControllerPassword();
    await _connect(roomNumber, createMode: mode);
  }

  Future<void> join(String roomName, String user) async {
    await leave();
    _requestedUser = user;
    await _connect(roomName);
  }

  Future<void> _connect(String target, {WatchRoomMode? createMode}) async {
    final savedTimeline = timeline;
    _snapshotReceived = false;
    final generation = ++_connection;
    connecting = true;
    error = null;
    _lastRoom = target;
    final endpoint = parseSyncPlayEndPoint(_endpoint());
    if (endpoint == null) {
      connecting = false;
      reportError('服务器地址无效');
      return;
    }
    final connection = SyncplayClient(host: endpoint.host, port: endpoint.port);
    runInAction(() => _client.value = connection);
    bool current() =>
        !_disposed &&
        generation == _connection &&
        identical(client, connection);
    _subscriptions.add(
      connection.onGeneralMessage.listen(
        (_) {},
        onError: (Object e) {
          if (!current()) return;
          if (e is SyncplayConnectionException && !connecting) {
            unawaited(_lostConnection());
          } else {
            reportError(e);
          }
        },
      ),
    );
    _subscriptions.add(
      connection.onRoomMessage.listen((message) {
        if (current()) _roomMessage(message);
      }),
    );
    _subscriptions.add(
      connection.onPositionChangedMessage.listen((message) {
        if (!current()) return;
        if (_migrating &&
            (message['setBy'] == 'Nobody' ||
                message['setBy'] == '' ||
                message['setBy'] == null)) {
          return;
        }
        runInAction(
          () => _rtt.value = ((message['clientRtt'] as num) * 1000).round(),
        );
        if (_waitingForReset != null) {
          if (message['setBy'] != _waitingForReset ||
              message['doSeek'] != true) {
            return;
          }
          _waitingForReset = null;
        }
        timeline = RoomTimeline(
          position: (message['calculatedPositon'] as num).toDouble(),
          paused: message['paused'] == true,
          contentId: snapshot?.content?.id,
        );
        _lastActor = message['setBy'] as String?;
        // Detached/loading clients echo the room clock, never a stopped local player.
        _applyTimeline(message['doSeek'] == true);
        _changed();
      }),
    );
    _subscriptions.add(
      connection.onChatMessage.listen((message) {
        if (!current()) return;
        _chat.add(
          SyncPlayChatMessage(
            username: '${message['username']}',
            message: '${message['message']}',
            fromRemote: message['username'] != username,
          ),
        );
      }),
    );
    _changed();
    try {
      await connection.connect(enableTLS: isOfficialSyncPlayEndPoint(endpoint));
      if (!current()) return;
      await connection.joinRoom(target, _requestedUser);
      if (!current()) return;
      if (_ownerPassword != null &&
          snapshot != null &&
          connection.username != snapshot!.host) {
        throw SyncplayConnectionException('等待旧房主连接释放后重连');
      }
      _requestedUser = connection.username!;
      if (createMode != null) {
        if (createMode == WatchRoomMode.hostOnly) {
          if (connection.serverFeatures['managedRooms'] != true) {
            throw SyncplayProtocolException('此服务器不支持房主控制模式');
          }
          final managed = await connection.createControlledRoom(
            target,
            _ownerPassword!,
          );
          if (!current()) return;
          await connection.switchRoom(managed);
          await connection.authenticateController(_ownerPassword!);
          target = managed;
        }
        snapshot = RoomSnapshot(host: username, mode: createMode);
        await connection.setPlaylist([snapshot!.encode()]);
      } else if (_ownerPassword != null && target.startsWith('+')) {
        await connection.authenticateController(_ownerPassword!);
      }
      if (!current()) return;
      _lastRoom = target;
      runInAction(() => _room.value = target);
      connecting = false;
      reconnecting = false;
      _retryCount = 0;
      if (createMode == null && isHost && !_snapshotReceived && !_migrating) {
        await connection.setPlaylist([snapshot!.encode()]);
        if (savedTimeline != null) {
          connection.setPosition(savedTimeline.target);
          connection.setPaused(savedTimeline.paused);
          await connection.sendSyncPlaySyncRequest(doSeek: true);
        }
      }
      await connection.requestList();
      final pending = _pendingFollow;
      _pendingFollow = null;
      if (pending != null) unawaited(_followContent(pending));
      final local = binding;
      if (createMode != null && local?.ready() == true) {
        await local!.prepare?.call();
        final content = identical(binding, local) ? local.content() : null;
        if (content != null && await select(content)) {
          await publish(
            position: local.position(),
            paused: !local.playing(),
            doSeek: true,
          );
        }
      }
      if (!_migrating) unawaited(playerReady());
      _changed();
    } catch (e) {
      if (!current()) return;
      connecting = false;
      error = e.toString();
      await _closeConnection();
      _changed();
      if (reconnecting) _scheduleRetry();
    }
  }

  void _roomMessage(Map<String, dynamic> message) {
    switch (message['type']) {
      case 'list':
        final rooms = message['rooms'] as Map;
        final users = rooms[client?.currentRoom] as Map? ?? {};
        members.clear();
        for (final entry in users.entries) {
          members['${entry.key}'] = (entry.value as Map)['controller'] == true;
        }
        hostOnline = snapshot == null || members.containsKey(snapshot!.host);
      case 'joined':
      case 'left':
      case 'auth':
      case 'userUpdated':
        final active = client;
        if (active != null) {
          unawaited(
            active.requestList().catchError((Object e) {
              reportError(e);
            }),
          );
        }
      case 'playlist':
        final files = message['files'];
        if (files is! List || files.length != 1 || files.first is! String) {
          break;
        }
        final incoming = RoomSnapshot.decode(files.first as String);
        if (incoming == null) break;
        final expectedMode = client?.currentRoom?.startsWith('+') == true
            ? WatchRoomMode.hostOnly
            : WatchRoomMode.everyone;
        if (incoming.mode != expectedMode && incoming.migrateTo == null) break;
        if (snapshot != null && incoming.host != snapshot!.host) break;
        if (incoming.migrateTo != null) {
          if (message['user'] == snapshot?.host) {
            if (_migrating) {
              _pendingMigration = incoming;
            } else {
              unawaited(_followMigration(incoming));
            }
          }
          break;
        }
        if (message['user'] == username && _pendingLocalContentId != null) {
          if (incoming.content?.id != _pendingLocalContentId) break;
          _pendingLocalContentId = null;
        }
        final previous = snapshot?.content;
        _snapshotReceived = true;
        snapshot = incoming;
        hostOnline = members.isEmpty || members.containsKey(incoming.host);
        final content = incoming.content;
        if (content != null && content.id != previous?.id) {
          final local = binding;
          if (local?.contentId != content.id) {
            timeline = RoomTimeline(
              position: 0,
              paused: true,
              contentId: content.id,
            );
            if (connecting) {
              _pendingFollow = content;
            } else {
              _waitingForReset = message['user'] as String?;
              unawaited(_followContent(content));
            }
          }
        }
    }
    _changed();
  }

  Future<void> _followContent(RoomContent content) async {
    final selection = ++_selection;
    _announcedBinding = null;
    _announcedContent = null;
    try {
      final local = binding;
      if (local != null && local.content()?.sameSource(content) == true) {
        local.following = true;
        local.contentId = content.id;
        await local.switchContent(content);
      } else {
        await openContent?.call(content);
      }
    } catch (e) {
      if (selection == _selection) reportError(e);
    }
  }

  Future<void> follow() async {
    final content = snapshot?.content;
    if (content != null) await _followContent(content);
  }

  void attach(RoomPlaybackBinding value, {String? contentId}) {
    binding = value;
    value.contentId = contentId;
    value.following = contentId != null || !hasSession;
  }

  void detach(RoomPlaybackBinding value) {
    if (!identical(binding, value)) return;
    binding = null;
    _readyPoll?.cancel();
    ++_applyVersion;
    ++_selection;
    final state = timeline;
    if (state != null) {
      client?.setPosition(state.target);
      client?.setPaused(state.paused);
    }
    scheduleMicrotask(_changed);
  }

  /// Called at selection commit, before stopping/resolving a media player.
  Future<bool> select(RoomContent content) async {
    if (!hasSession) return true;
    if (!canControl) {
      reportError('当前由房主控制，请使用「跟随播放」');
      return false;
    }
    final current = snapshot;
    if (current == null) return false;
    final active = client!;
    ++_selection;
    _announcedBinding = null;
    _announcedContent = null;
    _waitingForReset = null;
    error = null;
    binding?.contentId = content.id;
    _pendingLocalContentId = content.id;
    binding?.following = true;
    snapshot = RoomSnapshot(
      host: current.host,
      mode: current.mode,
      content: content,
    );
    timeline = RoomTimeline(position: 0, paused: true, contentId: content.id);
    client!.setPosition(0);
    client!.setPaused(true);
    try {
      await active.setPlaylist([snapshot!.encode()]);
      if (!identical(client, active) || snapshot?.content?.id != content.id) {
        return false;
      }
      await active.sendSyncPlaySyncRequest(doSeek: true);
      _changed();
      return snapshot?.content?.id == content.id;
    } catch (e) {
      if (_pendingLocalContentId == content.id) _pendingLocalContentId = null;
      reportError(e);
      return false;
    }
  }

  Future<void> playerReady() async {
    final local = binding;
    if (local == null || !local.following || snapshot?.content == null) return;
    if (local.contentId != snapshot?.content?.id || !connected) return;
    if (!local.ready()) {
      _readyPoll?.cancel();
      final id = local.contentId;
      _readyPoll = Timer(const Duration(milliseconds: 50), () {
        if (identical(binding, local) && local.contentId == id) {
          unawaited(playerReady());
        }
      });
      return;
    }
    if (identical(_announcedBinding, local) &&
        _announcedContent == local.contentId) {
      return;
    }
    _announcedBinding = local;
    _announcedContent = local.contentId;
    _readyPoll?.cancel();
    try {
      await client!.setSyncPlayPlaying(
        '${local.content()!.bangumiId}[${local.content()!.episode}]',
        0,
        0,
      );
      if (!identical(binding, local) ||
          local.contentId != snapshot?.content?.id) {
        return;
      }
      // The content initiator owns the initial play, followers restore native State.
      if (_initiatedContent == local.contentId && canControl) {
        _initiatedContent = null;
        await publish(
          position: local.position(),
          paused: !local.playing(),
          doSeek: true,
        );
      } else {
        _applyTimeline(true);
      }
    } catch (e) {
      reportError(e);
    }
  }

  String? _initiatedContent;
  void markInitiator(String id) => _initiatedContent = id;

  void sampleLocalPosition() {
    final local = binding;
    if (!connected ||
        local == null ||
        !local.following ||
        !local.ready() ||
        local.contentId != snapshot?.content?.id) {
      return;
    }
    // Followers report their compensated room clock; buffering must not drag others back.
    if (canControl && (_lastActor == username || timeline == null)) {
      client!.setPosition(local.position());
      client!.setPaused(!local.playing());
    }
  }

  String? _lastActor;
  Future<void> publish({
    required double position,
    required bool paused,
    bool doSeek = false,
  }) async {
    final local = binding;
    if (connected && canControl && local != null && snapshot?.content == null) {
      final chosen = local.content();
      if (chosen == null) return;
      await local.prepare?.call();
      if (!identical(binding, local) || !connected) return;
      final selection = RoomContent.fromJson({
        ...chosen.toJson(),
        'id': newContentId(),
      });
      if (!await select(selection)) return;
    }
    if (!connected ||
        !canControl ||
        !identical(binding, local) ||
        local?.following != true ||
        local?.contentId != snapshot?.content?.id) {
      return;
    }
    _lastActor = username;
    timeline = RoomTimeline(
      position: position,
      paused: paused,
      contentId: local!.contentId,
    );
    client!.setPosition(position);
    client!.setPaused(paused);
    try {
      await client!.sendSyncPlaySyncRequest(doSeek: doSeek);
    } catch (e) {
      reportError(e);
    }
  }

  void _applyTimeline(bool force) {
    if (_migrating) return;
    final local = binding;
    final state = timeline;
    if (local == null ||
        state == null ||
        !local.following ||
        !local.ready() ||
        local.contentId != state.contentId) {
      return;
    }
    final version = ++_applyVersion;
    _applyTail = _applyTail
        .then((_) async {
          if (version != _applyVersion ||
              !identical(binding, local) ||
              !local.ready()) {
            return;
          }
          await local.apply(state, force);
        })
        .catchError((Object e) {
          reportError(e);
        });
  }

  Future<void> sendChatMessage(String text) async {
    if (!connected) return;
    final limit = client!.serverFeatures['maxChatMessageLength'] as int? ?? 50;
    if (text.runes.length > limit) {
      reportError('聊天消息最多 $limit 个字符');
      return;
    }
    try {
      await client!.sendChatMessage(text);
    } catch (e) {
      reportError(e);
    }
  }

  Future<void> changeMode(WatchRoomMode mode) async {
    if (!connected || !isHost || snapshot!.mode == mode || _migrating) return;
    _migrating = true;
    try {
      final base = List.generate(8, (_) => _random.nextInt(10)).join();
      final target = mode == WatchRoomMode.hostOnly
          ? await client!.createControlledRoom(base, _ownerPassword!)
          : base;
      final next = RoomSnapshot(
        host: username,
        mode: mode,
        content: snapshot!.content,
        migrateTo: target,
      );
      await client!.setPlaylistAndWaitForEcho([next.encode()]);
      await _migrate(
        target,
        RoomSnapshot(host: username, mode: mode, content: next.content),
      );
    } catch (e) {
      reportError(e);
    } finally {
      _finishMigration();
    }
  }

  Future<void> _followMigration(RoomSnapshot next) async {
    _migrating = true;
    try {
      await _migrate(
        next.migrateTo!,
        RoomSnapshot(host: next.host, mode: next.mode, content: next.content),
      );
    } catch (e) {
      reportError(e);
    } finally {
      _finishMigration();
    }
  }

  void _finishMigration() {
    _migrating = false;
    final pending = _pendingMigration;
    _pendingMigration = null;
    // A newer mode change may arrive after joining the new room but before
    // this migration finishes. Follow it instead of dropping the notification.
    if (connected &&
        pending != null &&
        pending.host == snapshot?.host &&
        pending.migrateTo != room) {
      unawaited(_followMigration(pending));
      return;
    }
    _applyTimeline(true);
    unawaited(playerReady());
    _changed();
  }

  Future<void> _migrate(String target, RoomSnapshot next) async {
    final savedTimeline = timeline;
    final revision = _selection;
    reconnecting = true;
    await _closeConnection();
    if (revision != _selection || !reconnecting || _disposed) return;
    snapshot = next;
    await _connect(target);
    if (isHost && connected) {
      await client!.setPlaylist([next.encode()]);
      if (savedTimeline != null) {
        client!.setPosition(savedTimeline.target);
        client!.setPaused(savedTimeline.paused);
        await client!.sendSyncPlaySyncRequest(doSeek: true);
      }
    }
  }

  Future<void> _lostConnection() async {
    reconnecting = true;
    await _closeConnection();
    _scheduleRetry();
    _changed();
  }

  void _scheduleRetry() {
    _retry?.cancel();
    _retry = Timer(Duration(seconds: min(1 << min(_retryCount++, 4), 15)), () {
      if (!_disposed && reconnecting) unawaited(_connect(_lastRoom));
    });
  }

  Future<void> reconnect() async {
    _retry?.cancel();
    reconnecting = true;
    await _closeConnection();
    await _connect(_lastRoom);
  }

  Future<void> _closeConnection() async {
    _pendingLocalContentId = null;
    _readyPoll?.cancel();
    _announcedBinding = null;
    _announcedContent = null;
    ++_connection;
    ++_applyVersion;
    final previous = client;
    runInAction(() {
      _client.value = null;
      _room.value = '';
    });
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    await previous?.disconnect();
  }

  Future<void> leave() async {
    _retry?.cancel();
    _pendingMigration = null;
    reconnecting = false;
    connecting = false;
    ++_selection;
    await _closeConnection();
    snapshot = null;
    timeline = null;
    members.clear();
    _ownerPassword = null;
    _lastActor = null;
    _initiatedContent = null;
    _pendingFollow = null;
    _waitingForReset = null;
    error = null;
    runInAction(() => _rtt.value = 0);
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(leave());
    unawaited(_chat.close());
    super.dispose();
  }
}
