import 'dart:io';
import 'package:flutter/material.dart';
import 'package:kazumi/app_module.dart';
import 'package:kazumi/app_widget.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/settings/theme_provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:kazumi/services/network/metered_network_service.dart';
import 'package:kazumi/services/network/ech_http_licenses.dart';
import 'package:kazumi/services/network/proxy_manager.dart';
import 'package:kazumi/services/network/system_proxy_service.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'package:kazumi/pages/error/storage_error_page.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:kazumi/utils/device.dart';
import 'package:kazumi/services/platform/desktop_window_config.dart';
import 'package:kazumi/services/platform/webview_feature_service.dart';
import 'package:kazumi/services/platform/visual_asset_licenses.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/request/config/app_distribution.dart';

// Keep this ID in sync with windows/runner/main.cpp. The normal instance
// (unset environment variable) uses this application's default Hive directory.
String? getWindowsTestInstanceId() {
  if (!Platform.isWindows) return null;

  final id = Platform.environment['KAZUMI_TEST_INSTANCE'];
  if (id == null || id.isEmpty) return null;

  // Matches the ASCII identifiers accepted by the Windows runner's mutex.
  if (id.length > 63 || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id)) {
    throw StateError(
      'Invalid KAZUMI_TEST_INSTANCE. Use 1-63 ASCII letters, digits, _ or -.',
    );
  }
  return id;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerEchHttpLicenses();
  registerVisualAssetLicenses();
  MediaKit.ensureInitialized();
  if (Platform.isAndroid || Platform.isIOS) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        statusBarColor: Colors.transparent,
      ),
    );
  }

  if (Platform.isAndroid) {
    await WebViewFeatureService.initialize();
  }

  // Compute this once so Hive and GStorage recovery/backup use the same path.
  final testInstanceId = getWindowsTestInstanceId();
  try {
    final supportPath = (await getApplicationSupportDirectory()).path;
    final hivePath = testInstanceId == null
        ? '$supportPath/hive'
        : '$supportPath/hive_test_$testInstanceId';
    await Hive.initFlutter(hivePath);
    await GStorage.init(hivePath: hivePath);
  } catch (e) {
    debugPrint('Storage initialization failed: $e');

    if (isDesktop()) {
      await windowManager.ensureInitialized();
      windowManager.waitUntilReadyToShow(null, () async {
        // window_manager controls desktop visibility to avoid startup flicker.
        await windowManager.show();
        await windowManager.focus();
      });
    }
    runApp(
      MaterialApp(
        title: '初始化失败',
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [
          Locale.fromSubtags(
            languageCode: 'zh',
            scriptCode: 'Hans',
            countryCode: "CN",
          ),
        ],
        locale: const Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hans',
          countryCode: "CN",
        ),
        builder: (context, child) {
          return const StorageErrorPage();
        },
      ),
    );
    return;
  }
  final showWindowButton = DesktopWindowConfig.showWindowButton;
  if (isDesktop()) {
    await windowManager.ensureInitialized();
    final lowResolution = await isLowResolution();
    final windowOptions = WindowOptions(
      size: lowResolution ? const Size(840, 600) : const Size(1280, 860),
      center: true,
      skipTaskbar: false,
      // macOS embeds native buttons in the Flutter view.
      titleBarStyle: (Platform.isMacOS || !showWindowButton)
          ? TitleBarStyle.hidden
          : TitleBarStyle.normal,
      windowButtonVisibility: showWindowButton,
      // Match the title set by windows/runner/main.cpp, so a second launch
      // can find and activate the right instance.
      title: testInstanceId == null
          ? AppDistribution.productName
          : '${AppDistribution.productName} [test $testInstanceId]',
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      // window_manager controls desktop visibility to avoid startup flicker.
      await windowManager.show();
      await windowManager.focus();
    });
  }
  if (Platform.isWindows) {
    SystemProxyService.init();
  }
  await MeteredNetworkService.refresh();
  ProxyManager.applyProxy();
  runApp(
    ModularApp(
      module: appModule,
      navigatorKey: rootNavigatorKey,
      navigatorObservers: [KazumiDialog.observer, rootRouteObserver],
      defaultTransition: TransitionType.material,
      provide: (scoped) {
        scoped.addChangeNotifier<ThemeProvider>(ThemeProvider.new);
      },
      child: const AppWidget(),
    ),
  );
}
