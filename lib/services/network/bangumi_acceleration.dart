import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/bangumi_mirror_credentials.dart';

enum BangumiAcceleration {
  direct,
  ech,
  mirror;

  static BangumiAcceleration get current => resolve(
    storedMode: GStorage.getSetting(SettingsKeys.bangumiAcceleration),
    legacyMirrorEnabled: GStorage.getSetting(SettingsKeys.enableBangumiProxy),
    mirrorCredentialsAvailable: hasBangumiMirrorCredentials,
  );

  /// Older installations inherit the mirror switch. A derivative without
  /// mirror credentials must use the public API instead of sending empty MACs.
  static BangumiAcceleration resolve({
    required String storedMode,
    required bool legacyMirrorEnabled,
    required bool mirrorCredentialsAvailable,
  }) => switch (storedMode) {
    'direct' => direct,
    'ech' => ech,
    'mirror' => mirrorCredentialsAvailable ? mirror : ech,
    _ =>
      legacyMirrorEnabled
          ? (mirrorCredentialsAvailable ? mirror : ech)
          : direct,
  };

  static List<BangumiAcceleration> get availableModes =>
      hasBangumiMirrorCredentials ? values : const [direct, ech];

  String get label => switch (this) {
    direct => '直连',
    ech => 'ECH',
    mirror => '镜像',
  };
}
