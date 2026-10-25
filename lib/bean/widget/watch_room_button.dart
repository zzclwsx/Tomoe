import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/player/syncplay_sheet.dart';
import 'package:kazumi/services/player/watch_room_service.dart';

/// Shared app-bar entrance, available before a player is opened.
class WatchRoomButton extends StatelessWidget {
  const WatchRoomButton({super.key});
  @override
  Widget build(BuildContext context) {
    final room = inject<WatchRoomService>();
    return ListenableBuilder(
      listenable: room,
      builder: (context, _) => IconButton(
        tooltip: room.error != null
            ? '一起看 · ${room.error}'
            : room.hasSession
            ? '一起看 · ${room.members.length} 人'
            : '一起看',
        onPressed: () => showSyncPlaySheet(context, room: room),
        icon: Badge(
          isLabelVisible: room.hasSession,
          backgroundColor: room.error != null
              ? Theme.of(context).colorScheme.error
              : room.connected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.tertiary,
          child: const Icon(Icons.groups_outlined),
        ),
      ),
    );
  }
}
