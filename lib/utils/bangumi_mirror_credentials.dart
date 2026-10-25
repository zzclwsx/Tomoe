// Optional authorized mirror credentials, supplied with --dart-define.
// Builds without both values use the public Bangumi API instead.
const Map<String, String> bangumiMirrorCredentials = {
  'id': String.fromEnvironment('KAZUMI_APPID'),
  'value': String.fromEnvironment('KAZUMI_KEY'),
};

bool get hasBangumiMirrorCredentials =>
    bangumiMirrorCredentials['id']!.trim().isNotEmpty &&
    bangumiMirrorCredentials['value']!.trim().isNotEmpty;
