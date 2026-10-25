import 'package:dio/dio.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/request/core/network_error_mapper.dart';
import 'package:kazumi/request/core/danmaku_service_exception.dart';
import 'package:kazumi/utils/dandan_credentials.dart';
import 'package:kazumi/utils/http_headers.dart';
import 'package:kazumi/utils/crypto.dart';

class DanmakuClient {
  DanmakuClient._() : _credentials = dandanCredentials, _overrideDio = null;
  DanmakuClient.withCredentials(this._credentials, this._overrideDio);

  final Map<String, String> _credentials;
  final Dio? _overrideDio;

  static final DanmakuClient instance = DanmakuClient._();

  Future<dynamic> get(
    String url, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic> headers = const {},
    CancelToken? cancelToken,
  }) async {
    final appId = _credentials['id'] ?? '';
    final appSecret = _credentials['value'] ?? '';
    if (appId.trim().isEmpty || appSecret.trim().isEmpty) {
      throw const DanmakuServiceException(DanmakuServiceFailure.notConfigured);
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final uri = Uri.parse(url);
    final requestHeaders = <String, dynamic>{
      'user-agent': getRandomUA(),
      'referer': '',
      'X-Auth': 1,
      'X-AppId': appId,
      'X-Timestamp': timestamp,
      'X-Signature': generateDandanSignature(
        uri.path,
        timestamp,
        appId: appId,
        appSecret: appSecret,
      ),
      ...headers,
    };

    try {
      final response = await (_overrideDio ?? DioFactory.apiDio).get(
        url,
        queryParameters: queryParameters,
        options: Options(headers: requestHeaders),
        cancelToken: cancelToken,
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const DanmakuServiceException(
          DanmakuServiceFailure.invalidResponse,
        );
      }
      if (data['success'] == false) {
        throw const DanmakuServiceException(DanmakuServiceFailure.rejected);
      }
      return data;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        throw const DanmakuServiceException(
          DanmakuServiceFailure.authorization,
        );
      }
      throw await NetworkErrorMapper.mapException(e);
    }
  }
}
