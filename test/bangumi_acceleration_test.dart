import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/request/core/bangumi_transport.dart';
import 'package:kazumi/services/network/bangumi_acceleration.dart';

void main() {
  test(
    'fresh and legacy mirror settings use official ECH without credentials',
    () {
      for (final storedMode in ['', 'mirror', 'unknown']) {
        expect(
          BangumiAcceleration.resolve(
            storedMode: storedMode,
            legacyMirrorEnabled: true,
            mirrorCredentialsAvailable: false,
          ),
          BangumiAcceleration.ech,
        );
      }
    },
  );

  test(
    'explicit direct/ECH choices and old direct preference are preserved',
    () {
      for (final mode in [
        BangumiAcceleration.direct,
        BangumiAcceleration.ech,
      ]) {
        expect(
          BangumiAcceleration.resolve(
            storedMode: mode.name,
            legacyMirrorEnabled: true,
            mirrorCredentialsAvailable: false,
          ),
          mode,
        );
      }
      expect(
        BangumiAcceleration.resolve(
          storedMode: '',
          legacyMirrorEnabled: false,
          mirrorCredentialsAvailable: false,
        ),
        BangumiAcceleration.direct,
      );
    },
  );

  test('configured mirror builds retain their authenticated mirror choice', () {
    for (final storedMode in ['', 'mirror']) {
      expect(
        BangumiAcceleration.resolve(
          storedMode: storedMode,
          legacyMirrorEnabled: true,
          mirrorCredentialsAvailable: true,
        ),
        BangumiAcceleration.mirror,
      );
    }
  });

  test(
    'credential-free search keeps the official host, query and POST body',
    () async {
      final adapter = _RecordingAdapter();
      final mode = BangumiAcceleration.resolve(
        storedMode: 'mirror',
        legacyMirrorEnabled: true,
        mirrorCredentialsAvailable: false,
      );
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(() => dio.close(force: true));
      dio.interceptors.add(BangumiAccelerationInterceptor(mode: () => mode));
      await dio.post(
        'https://api.bgm.tv/v0/search/subjects',
        queryParameters: {'limit': 20, 'offset': 0},
        data: {'keyword': '葬送的芙莉莲'},
      );
      final request = adapter.last!;
      expect(request.uri.host, 'api.bgm.tv');
      expect(request.uri.path, '/v0/search/subjects');
      expect(request.uri.queryParameters, {'limit': '20', 'offset': '0'});
      expect(request.method, 'POST');
      expect(request.extra['bangumiEch'], isTrue);
      expect(request.headers.containsKey('X-AppId'), isFalse);
    },
  );
}

class _RecordingAdapter implements HttpClientAdapter {
  RequestOptions? last;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    last = options;
    return ResponseBody.fromString(
      '{"data":[]}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
