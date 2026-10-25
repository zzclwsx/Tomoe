import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/player/watch_room_service.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'package:kazumi/utils/episode_url.dart';

/// Resolves locally installed rules and opens a normal route. Stale remote
/// selections cannot install a route after a newer selection or room exit.
class WatchRoomPlaybackCoordinator implements Disposable {
  WatchRoomPlaybackCoordinator(this.room, this.plugins) {
    room.openContent = open;
  }
  final WatchRoomService room;
  final PluginsController plugins;
  RuleCancelToken? _cancel;
  int _generation = 0;

  Future<void> open(RoomContent content) async {
    final generation = ++_generation;
    final revision = room.playbackRevision;
    _cancel?.cancel();
    final cancel = RuleCancelToken();
    _cancel = cancel;
    final matches = plugins.pluginList.where(
      (p) => p.name == content.pluginName,
    );
    if (matches.isEmpty) {
      throw StateError('未安装「${content.pluginName}」规则，请安装后点跟随播放');
    }
    final plugin = matches.first;
    if (plugin.version != content.pluginVersion) {
      throw StateError(
        '「${content.pluginName}」规则版本不同，请更新到 ${content.pluginVersion} 后跟随播放',
      );
    }
    final source = Uri.tryParse(
      normalizeEpisodeUrl(plugin.baseUrl, content.source),
    );
    final base = Uri.tryParse(plugin.baseUrl);
    if (source == null ||
        base == null ||
        source.host != base.host ||
        !['http', 'https'].contains(source.scheme)) {
      throw StateError('房间选片与本地规则站点不匹配');
    }
    final roads = await plugin.queryChapterRoads(
      content.source,
      cancelToken: cancel,
    );
    if (generation != _generation ||
        revision != room.playbackRevision ||
        !room.connected ||
        room.snapshot?.content?.id != content.id) {
      return;
    }
    final selection = resolveRoomEpisode(roads, content, plugin.baseUrl);
    final context = rootNavigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    final oldRoute = room.binding?.route;
    final navigator = rootNavigatorKey.currentState!;
    // Close transient sheets and replace the old player, preserving the shell
    // and the existing detail/search stack beneath it.
    if (oldRoute != null) {
      navigator.popUntil(
        (route) => identical(route, oldRoute) || route.isFirst,
      );
    } else {
      navigator.popUntil((route) => route is PageRoute || route.isFirst);
    }
    // Replacing also removes a player with local PiP history; a plain pop can
    // consume only that history entry and leave a second player underneath.
    final navigate = oldRoute != null
        ? context.replace<Object?>
        : context.pushNamed<Object?>;
    unawaited(
      navigate(
        '/video/',
        arguments: OnlineVideoPlaybackArgs(
          bangumiItem: BangumiItem(
            id: content.bangumiId,
            type: 2,
            name: content.name,
            nameCn: content.name,
            summary: '',
            airDate: '',
            airWeekday: 0,
            rank: 0,
            images: {},
            tags: [],
            alias: [],
            ratingScore: 0,
            votes: 0,
            votesCount: [],
            info: '',
          ),
          plugin: plugin,
          title: content.name,
          src: content.source,
          roads: roads,
          roomContentId: content.id,
          initialEpisode: selection.episode,
          initialRoad: selection.road,
        ),
      ),
    );
  }

  @override
  void dispose() {
    ++_generation;
    _cancel?.cancel();
    room.openContent = null;
  }
}

({int episode, int road}) resolveRoomEpisode(
  List<Road> roads,
  RoomContent content,
  String baseUrl,
) {
  final order = List.generate(roads.length, (i) => i);
  order.sort((a, b) {
    int rank(int index) => roads[index].name == content.roadName
        ? 0
        : index == content.road
        ? 1
        : 2;
    return rank(a).compareTo(rank(b));
  });
  final target = normalizeEpisodeUrl(baseUrl, content.pageUrl);
  for (final road in order) {
    final episodes = roads[road].data;
    for (var index = 0; index < episodes.length; index++) {
      if (normalizeEpisodeUrl(baseUrl, episodes[index]) == target) {
        return (episode: index + 1, road: road);
      }
    }
  }
  throw StateError('源站未找到房间选择的剧集，请刷新规则后重试');
}
