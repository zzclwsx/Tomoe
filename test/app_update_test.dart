import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/request/config/app_distribution.dart';
import 'package:kazumi/request/core/network_exception.dart';
import 'package:kazumi/services/update/auto_updater.dart';
import 'package:kazumi/utils/version.dart';

void main() {
  testWidgets(
    'long release notes stay scrollable and keep update actions visible',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 680));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final notes = List.generate(100, (index) => '更新说明 $index').join('\n');
      final updater = AutoUpdater.withReleaseLoader(
        (_, _) async => jsonEncode({
          'tag_name': 'v999.0.0',
          'body': notes,
          'html_url': 'https://example.com/releases/v999.0.0',
          'assets': [
            {'name': 'Tomoe_windows_x64_v999.0.0.zip'},
          ],
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: rootNavigatorKey,
          home: const Scaffold(body: Text('首页')),
        ),
      );
      await updater.manualCheckForUpdates();
      await tester.pumpAndSettle();
      expect(find.text('立即更新').hitTestable(), findsOneWidget);
      expect(find.text('稍后提醒').hitTestable(), findsOneWidget);
      final dialogSize = tester.getSize(
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(dialogSize.height, lessThan(680 * 0.8));
      final scrollable = find
          .ancestor(of: find.text(notes), matching: find.byType(Scrollable))
          .first;
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(position.maxScrollExtent, greaterThan(0));
      await tester.drag(scrollable, const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(0));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'update checks use only this derivative and offer available packages',
    () async {
      final urls = <String>[];
      final updater = AutoUpdater.withReleaseLoader((url, headers) async {
        urls.add(url);
        expect(headers['Accept'], 'application/vnd.github+json');
        return jsonEncode({
          'tag_name': 'v999.0.0',
          'assets': [
            {'name': 'Tomoe_windows_x64_v999.0.0.zip'},
            {'name': 'Tomoe_android_v999.0.0.apk'},
            {'name': 'Tomoe_macos_v999.0.0.dmg'},
          ],
        });
      });
      final update = await updater.checkForUpdates();
      expect(urls, [AppDistribution.latestReleaseApi]);
      expect(update!.version, 'v999.0.0');
      if (Platform.isWindows) {
        expect(update.availableInstallationTypes, [
          InstallationType.windowsPortable,
        ]);
      }
    },
  );

  test(
    'a repository without a release does not fall back to upstream',
    () async {
      var requests = 0;
      final updater = AutoUpdater.withReleaseLoader((url, headers) async {
        requests++;
        throw const NetworkException(
          type: NetworkExceptionType.badResponse,
          message: 'Not Found',
          statusCode: 404,
        );
      });
      expect(await updater.checkForUpdates(), isNull);
      expect(requests, 1);
    },
  );

  test('app releases compare SemVer tags independently of rule versions', () {
    expect(isNewerAppVersion('1.0.0', 'v1.0.1'), isTrue);
    expect(isNewerAppVersion('1.0.0', 'v1.0.0'), isFalse);
    expect(isNewerAppVersion('1.0.0+10000', '1.0.0+10001'), isFalse);
    expect(isNewerAppVersion('1.0.0-beta.2', 'v1.0.0-beta.10'), isTrue);
    expect(isNewerAppVersion('1.0.0-beta.10', '1.0.0'), isTrue);
    expect(isNewerAppVersion('1.0.0', '1.0.0-beta.10'), isFalse);
    expect(
      () => isNewerAppVersion('1.0.0', 'not-a-version'),
      throwsFormatException,
    );
    expect(needUpdate('2.6', '2.7'), isTrue);
  });

  test('Tomoe release assets preserve platform selection and SHA-256 checks', () {
    final assets = [
      {'name': 'Tomoe_source_v1.0.1.zip'},
      {
        'name': 'Tomoe_windows_x64_v1.0.1.zip',
        'browser_download_url':
            'https://github.com/zzclwsx/Tomoe/releases/download/v1.0.1/Tomoe_windows_x64_v1.0.1.zip',
        'digest': 'sha256:${'a' * 64}',
      },
      {'name': 'Tomoe_android_v1.0.1.apk'},
    ];
    final windows = getUpdateAssetForType(
      assets,
      InstallationType.windowsPortable,
    )!;
    expect(windows['name'], contains('windows_x64'));
    expect(getUpdateDownloadUrlFromAsset(windows), contains('/zzclwsx/Tomoe/'));
    expect(getUpdateFileHashFromAsset(windows), 'a' * 64);
    expect(getUpdateFileHashFromAsset({'digest': ''}), isEmpty);
    expect(
      getUpdateAssetForType(assets, InstallationType.androidApk)!['name'],
      endsWith('.apk'),
    );
    expect(getUpdateAssetForType(assets, InstallationType.windowsMsix), isNull);
  });
}
