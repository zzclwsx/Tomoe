import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/search/image_search_page.dart';
import 'package:kazumi/pages/search/search_controller.dart';
import 'package:kazumi/pages/search/search_page.dart';
import 'package:kazumi/repositories/collect_repository.dart';
import 'package:kazumi/repositories/search_history_repository.dart';

void _provideSearchController(Scoped scoped) {
  // Keep the optional function-valued test seam out of AutoInjector's
  // constructor signature parser. Production uses the default API loader.
  scoped.add<SearchPageController>(
    (
      ICollectRepository collectRepository,
      ISearchHistoryRepository searchHistoryRepository,
    ) => SearchPageController(collectRepository, searchHistoryRepository),
  );
}

final searchModule = createModule(
  path: '/search',
  register: (c) {
    c
      ..route(
        '/',
        provide: _provideSearchController,
        child: (context, state) =>
            SearchPage(controller: context.read<SearchPageController>()),
      )
      ..route(
        '/image',
        provide: _provideSearchController,
        child: (context, state) =>
            ImageSearchPage(controller: context.read<SearchPageController>()),
      )
      ..route(
        '/:tag',
        provide: _provideSearchController,
        child: (context, state) => SearchPage(
          controller: context.read<SearchPageController>(),
          inputTag: state['tag'] ?? '',
        ),
      );
  },
);
