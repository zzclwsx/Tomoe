import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/search/search_history_module.dart';
import 'package:kazumi/pages/search/search_controller.dart';
import 'package:kazumi/pages/search/image_search_page.dart';
import 'package:kazumi/pages/search/search_module.dart';
import 'package:kazumi/pages/search/search_page.dart';
import 'package:kazumi/repositories/collect_repository.dart';
import 'package:kazumi/repositories/search_history_repository.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/services/player/watch_room_service.dart';
import 'package:kazumi/services/storage/storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory storage;
  final collect = _PrivateCollectRepository();
  final history = _EmptyHistoryRepository();

  setUpAll(() async {
    final root = Directory('.dart_tool').absolute;
    storage = await root.createTemp('search-page-test-');
    Hive.init(storage.path);
    await GStorage.init(hivePath: storage.path);
  });

  tearDownAll(() async {
    await Hive.close();
    expect(storage.parent.path, Directory('.dart_tool').absolute.path);
    expect(
      storage.uri.pathSegments.where((s) => s.isNotEmpty).last,
      startsWith('search-page-test-'),
    );
    await storage.delete(recursive: true);
  });

  Widget app({SearchPageController? controller}) => ModularApp(
    module: createModule(
      register: (c) {
        c
          ..addInstance<ICollectRepository>(collect)
          ..addInstance<ISearchHistoryRepository>(history)
          ..addSingleton<WatchRoomService>(WatchRoomService.new)
          ..route(
            '/',
            child: (context, _) => Scaffold(
              body: TextButton(
                onPressed: () => context.pushNamed('/search/'),
                child: const Text('打开搜索'),
              ),
            ),
          );
        if (controller == null) {
          c.module(searchModule);
        } else {
          c.route(
            '/search/',
            child: (_, _) => SearchPage(controller: controller),
          );
        }
      },
    ),
    child: Builder(
      builder: (context) => MaterialApp.router(
        routerConfig: ModularApp.routerConfigOf(context),
        theme: ThemeData(useMaterial3: true),
      ),
    ),
  );

  testWidgets('search entry resolves the production page controller', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开搜索'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(SearchBar), findsOneWidget);
    await tester.tap(find.byTooltip('以图搜番'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ImageSearchPage), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back).hitTestable());
    await tester.pumpAndSettle();
    expect(find.byType(SearchBar), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back).hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开搜索'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(SearchBar), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final size in [
    const Size(900, 680),
    const Size(390, 844),
    const Size(844, 390),
  ]) {
    testWidgets('submit and clear preserve a usable search field at $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final response = Completer<BangumiSearchPage?>();
      final controller = SearchPageController(
        collect,
        history,
        searchLoader: (_, _, _) => response.future,
      );
      await tester.pumpWidget(app(controller: controller));
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开搜索'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '芙莉莲');
      await tester.tap(find.byTooltip('搜索'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(SearchBar), findsOneWidget);
      response.complete(const BangumiSearchPage(items: [], rawCount: 0));
      await tester.pumpAndSettle();
      expect(find.text('没有找到番剧'), findsOneWidget);
      await tester.tap(find.byTooltip('清空搜索'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('按条件查找'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '新搜索');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('搜索结果'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

class _PrivateCollectRepository implements ICollectRepository {
  @override
  bool getPrivateMode() => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected collection access: ${invocation.memberName}',
  );
}

class _EmptyHistoryRepository implements ISearchHistoryRepository {
  @override
  List<SearchHistory> getAllHistories() => [];
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected history access: ${invocation.memberName}');
}
