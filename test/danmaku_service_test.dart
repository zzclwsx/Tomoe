import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/danmaku/danmaku_search_response.dart';
import 'package:kazumi/request/clients/danmaku_client.dart';
import 'package:kazumi/request/core/danmaku_service_exception.dart';

void main() {
  const url = 'https://api.dandanplay.net/api/v2/search/episodes';
  late _Adapter adapter;
  late Dio dio;
  late DanmakuClient client;
  setUp(() {
    adapter = _Adapter();
    dio = Dio()..httpClientAdapter = adapter;
    client = DanmakuClient.withCredentials({
      'id': 'test-app',
      'value': 'test-secret',
    }, dio);
  });
  tearDown(() => dio.close(force: true));
  Matcher failure(DanmakuServiceFailure value) =>
      isA<DanmakuServiceException>().having((e) => e.failure, 'failure', value);
  test(
    'missing either credential fails clearly before any HTTP request',
    () async {
      for (final values in [
        <String, String>{},
        {'id': 'test'},
        {'value': 'test'},
      ]) {
        await expectLater(
          DanmakuClient.withCredentials(values, dio).get(url),
          throwsA(failure(DanmakuServiceFailure.notConfigured)),
        );
      }
      expect(adapter.request, isNull);
      expect(
        danmakuFailureMessage(
          const DanmakuServiceException(DanmakuServiceFailure.notConfigured),
        ),
        contains('尚未配置'),
      );
    },
  );
  test(
    'credentials sign the path without query and preserve search parameters',
    () async {
      await client.get(url, queryParameters: {'anime': '星空', 'v2': 'true'});
      final request = adapter.request!;
      expect(request.uri.queryParameters['anime'], '星空');
      expect(request.headers['X-AppId'], 'test-app');
      final timestamp = request.headers['X-Timestamp'];
      final expected = base64Encode(
        sha256
            .convert(
              utf8.encode(
                'test-app$timestamp/api/v2/search/episodestest-secret',
              ),
            )
            .bytes,
      );
      expect(request.headers['X-Signature'], expected);
    },
  );
  test(
    '401 and 403 explain service authentication instead of empty results',
    () async {
      for (final status in [401, 403]) {
        adapter.status = status;
        await expectLater(
          client.get(url),
          throwsA(failure(DanmakuServiceFailure.authorization)),
        );
      }
    },
  );
  test(
    'service rejection and malformed responses are distinguishable',
    () async {
      adapter.body = '{"success":false,"errorCode":123}';
      await expectLater(
        client.get(url),
        throwsA(failure(DanmakuServiceFailure.rejected)),
      );
      adapter.body = '[]';
      await expectLater(
        client.get(url),
        throwsA(failure(DanmakuServiceFailure.invalidResponse)),
      );
      expect(() => DanmakuSearchResponse.fromJson({}), throwsFormatException);
      expect(DanmakuSearchResponse.fromJson({'animes': []}).animes, isEmpty);
    },
  );
}

class _Adapter implements HttpClientAdapter {
  int status = 200;
  String body = '{"success":true,"animes":[]}';
  RequestOptions? request;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
