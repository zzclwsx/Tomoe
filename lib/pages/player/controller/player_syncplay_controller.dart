import 'package:kazumi/pages/player/controller/player_models.dart';
import 'package:kazumi/services/player/syncplay_client.dart';
import 'package:kazumi/services/player/watch_room_service.dart';

/// The player borrows the application room; disposing it never disconnects.
class PlayerSyncPlayController {
  PlayerSyncPlayController(this.room);
  final WatchRoomService room;
  SyncplayClient? get syncplayController => room.client;
  String get syncplayRoom => room.room;
  int get syncplayClientRtt => room.rtt;
  bool get hasSession => room.hasSession;
  Stream<SyncPlayChatMessage> get chatStream => room.chatStream;
  void setCurrentPosition({
    bool? forceSyncPlaying,
    double? forceSyncPosition,
  }) => room.sampleLocalPosition();
  Future<void> setPlayingBangumi({
    bool? forceSyncPlaying,
    double? forceSyncPosition,
  }) => room.playerReady();
  Future<void> requestSync({bool? doSeek}) async {
    final local = room.binding;
    if (local != null) {
      await room.publish(
        position: local.position(),
        paused: !local.playing(),
        doSeek: doSeek ?? false,
      );
    }
  }

  Future<void> sendChatMessage(String message) => room.sendChatMessage(message);
  Future<void> exitRoom() => room.leave();
}
