import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/search/search_controller.dart';
import 'package:kazumi/repositories/collect_repository.dart';
import 'package:kazumi/repositories/search_history_repository.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';

void main() {
  SearchPageController controller(BangumiSearchLoader loader) =>
      SearchPageController(
        _PrivateCollectRepository(),
        _UnusedHistoryRepository(),
        searchLoader: loader,
      );

  test(
    'failed search is marked as a request error instead of no matches',
    () async {
      final search = controller((_, _, _) async => null);
      await search.searchBangumi('芙莉莲', type: 'init');
      expect(search.bangumiList, isEmpty);
      expect(search.isTimeOut, isTrue);
      expect(search.isLoading, isFalse);
    },
  );

  test(
    'successful empty response remains a genuine no-matches state',
    () async {
      final search = controller(
        (_, _, _) async => const BangumiSearchPage(items: [], rawCount: 0),
      );
      await search.searchBangumi('没有匹配的名字', type: 'init');
      expect(search.bangumiList, isEmpty);
      expect(search.isTimeOut, isFalse);
      expect(search.hasMoreSearchResults, isFalse);
    },
  );

  test(
    'a stale request failure cannot overwrite a newer successful query',
    () async {
      final first = Completer<BangumiSearchPage?>();
      final search = controller(
        (filters, _, _) async => filters.keyword == '旧搜索'
            ? first.future
            : const BangumiSearchPage(items: [], rawCount: 0),
      );
      final pending = search.searchBangumi('旧搜索', type: 'init');
      await search.searchBangumi('新搜索', type: 'init');
      first.complete(null);
      await pending;
      expect(search.isTimeOut, isFalse);
      expect(search.isLoading, isFalse);
    },
  );
}

class _PrivateCollectRepository implements ICollectRepository {
  @override
  bool getPrivateMode() => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected collection access: ${invocation.memberName}',
  );
}

class _UnusedHistoryRepository implements ISearchHistoryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected search history access: ${invocation.memberName}',
  );
}
