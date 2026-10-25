import 'package:kazumi/request/core/network_exception.dart';

enum DanmakuServiceFailure {
  notConfigured,
  authorization,
  rejected,
  invalidResponse,
}

class DanmakuServiceException implements Exception {
  const DanmakuServiceException(this.failure);
  final DanmakuServiceFailure failure;

  String get message => switch (failure) {
    DanmakuServiceFailure.notConfigured => '当前版本尚未配置在线弹幕服务，暂时无法搜索或加载在线弹幕',
    DanmakuServiceFailure.authorization => '弹幕服务认证失败，请联系本应用维护者检查服务配置',
    DanmakuServiceFailure.rejected => '弹幕服务暂时拒绝了请求，请稍后重试',
    DanmakuServiceFailure.invalidResponse => '弹幕服务返回的数据不完整，请稍后重试',
  };
  @override
  String toString() => message;
}

String danmakuFailureMessage(Object error) {
  if (error is DanmakuServiceException) return error.message;
  if (error is FormatException) {
    return const DanmakuServiceException(
      DanmakuServiceFailure.invalidResponse,
    ).message;
  }
  if (error is NetworkException && error.statusCode == 429) {
    return '弹幕服务请求过于频繁，请稍后重试';
  }
  return '弹幕请求失败，请检查网络或稍后重试';
}
