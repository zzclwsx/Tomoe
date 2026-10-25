import 'dart:convert';

enum WatchRoomMode { hostOnly, everyone }

/// Source-page identity, never a resolved/expiring media URL or a plugin rule.
class RoomContent {
  const RoomContent({
    required this.id,
    required this.bangumiId,
    required this.name,
    required this.pluginName,
    required this.pluginVersion,
    required this.source,
    required this.roadName,
    required this.road,
    required this.episode,
    required this.episodeName,
    required this.pageUrl,
  });
  final String id;
  final int bangumiId;
  final String name;
  final String pluginName;
  final String pluginVersion;
  final String source;
  final String roadName;
  final int road;
  final int episode;
  final String episodeName;
  final String pageUrl;

  bool sameSource(RoomContent other) =>
      bangumiId == other.bangumiId &&
      pluginName == other.pluginName &&
      source == other.source;
  bool sameEpisode(RoomContent other) =>
      sameSource(other) && pageUrl == other.pageUrl;

  Map<String, dynamic> toJson() => {
    'id': id,
    'bangumi': bangumiId,
    'name': name,
    'plugin': pluginName,
    'version': pluginVersion,
    'source': source,
    'roadName': roadName,
    'road': road,
    'episode': episode,
    'episodeName': episodeName,
    'page': pageUrl,
  };

  factory RoomContent.fromJson(Map<String, dynamic> json) {
    final content = RoomContent(
      id: json['id'] as String,
      bangumiId: json['bangumi'] as int,
      name: json['name'] as String,
      pluginName: json['plugin'] as String,
      pluginVersion: json['version'] as String,
      source: json['source'] as String,
      roadName: json['roadName'] as String,
      road: json['road'] as int,
      episode: json['episode'] as int,
      episodeName: json['episodeName'] as String,
      pageUrl: json['page'] as String,
    );
    if (content.id.isEmpty ||
        content.bangumiId <= 0 ||
        content.episode < 1 ||
        content.road < 0 ||
        content.pluginName.isEmpty ||
        content.source.isEmpty ||
        content.pageUrl.isEmpty) {
      throw const FormatException('无效的房间选片信息');
    }
    return content;
  }
}

class RoomSnapshot {
  const RoomSnapshot({
    required this.host,
    required this.mode,
    this.content,
    this.migrateTo,
  });
  static const prefix = 'kazumi-room-v1:';
  final String host;
  final WatchRoomMode mode;
  final RoomContent? content;
  final String? migrateTo;

  String encode() {
    final encoded =
        '$prefix${jsonEncode({'host': host, 'mode': mode.name, 'content': content?.toJson(), if (migrateTo != null) 'migrate': migrateTo})}';
    // Upstream's shared playlist budget is 10,000 characters in total.
    if (encoded.length > 9500) throw const FormatException('选片信息过长，无法同步');
    return encoded;
  }

  static RoomSnapshot? decode(String value) {
    if (!value.startsWith(prefix) || value.length > 10000) return null;
    try {
      final json =
          jsonDecode(value.substring(prefix.length)) as Map<String, dynamic>;
      final host = json['host'] as String;
      if (host.isEmpty) return null;
      return RoomSnapshot(
        host: host,
        mode: WatchRoomMode.values.byName(json['mode'] as String),
        content: json['content'] == null
            ? null
            : RoomContent.fromJson(Map<String, dynamic>.from(json['content'])),
        migrateTo: json['migrate'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

/// A received native State is already compensated for transport delay.
/// Only local elapsed time is added while a player/source is loading.
class RoomTimeline {
  RoomTimeline({
    required this.position,
    required this.paused,
    this.contentId,
    Duration Function()? elapsed,
  }) : _elapsed = elapsed ?? (Stopwatch()..start()).elapsedGetter;
  final double position;
  final bool paused;
  final String? contentId;
  final Duration Function() _elapsed;
  double get target =>
      (position + (paused ? 0 : _elapsed().inMicroseconds / 1e6))
          .clamp(0, double.infinity)
          .toDouble();
}

extension on Stopwatch {
  Duration elapsedGetter() => elapsed;
}
