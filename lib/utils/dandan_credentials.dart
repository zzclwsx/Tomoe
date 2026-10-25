// DanDanPlay API credentials for the client signature flow.
// Supply our own authorized values with --dart-define. An empty build must
// report that online danmaku is unconfigured instead of sending blank headers.
const Map<String, String> dandanCredentials = {
  'id': String.fromEnvironment('DANDANAPI_APPID'),
  'value': String.fromEnvironment('DANDANAPI_KEY'),
};
