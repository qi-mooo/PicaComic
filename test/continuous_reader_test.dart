import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/components/scrollable_list/src/item_positions_listener.dart';
import 'package:pica_comic/components/scrollable_list/src/item_positions_notifier.dart';
import 'package:pica_comic/components/scrollable_list/src/scrollable_positioned_list.dart';
import 'package:pica_comic/foundation/pair.dart';
import 'package:pica_comic/foundation/state_controller.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/pages/reader/comic_reading_page.dart';

class TestReadingData extends ReadingData {
  TestReadingData({int chapters = 3, this.hasEp = true})
      : eps = hasEp
            ? {for (var i = 1; i <= chapters; i++) '$i': 'Chapter $i'}
            : null;

  final calls = <int>[];
  final responses = <int, Future<Res<List<String>>> Function()>{};
  final imageRequests = <(int, int, String)>[];

  @override
  final bool hasEp;
  @override
  final Map<String, String>? eps;
  @override
  String get title => 'Test comic';
  @override
  String get id => 'test';
  @override
  ComicType get type => ComicType.other;

  @override
  Future<Res<List<String>>> loadEp(int ep) async {
    calls.add(ep);
    final response = responses[ep];
    if (response != null) return response();
    return Res(List.generate(3, (page) => '$ep/$page'));
  }

  final image = MemoryImage(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII='));

  @override
  ImageProvider createImageProvider(int ep, int page, String url) {
    imageRequests.add((ep, page, url));
    return image;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void reportPositions(ComicReadingPageLogic logic, List<ItemPosition> items) {
  (logic.itemScrollListener as ItemPositionsNotifier).itemPositions.value =
      items;
}

ItemPosition position(int index, [double leading = 0]) => ItemPosition(
    index: index, itemLeadingEdge: leading, itemTrailingEdge: leading + 0.9);

Future<void> flushLoads() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TestReadingData data;
  late ComicReadingPageLogic logic;
  late List<(int, int, int)> history;

  setUp(() {
    appdata.settings[9] = '4';
    appdata.settings[28] = '2';
    data = TestReadingData();
    history = [];
    logic = ComicReadingPageLogic(1, data, 1, () {
      history.add((logic.order, logic.index, logic.length));
    });
  });

  tearDown(() {
    logic.resetContinuousState();
    logic.pageController.dispose();
    logic.scrollController.dispose();
    logic.focusNode.dispose();
    logic.clearPhotoViewControllers();
    StateController.remove<ComicReadingPageLogic>();
    ComicImage.clear();
  });

  test('preloads one chapter, deduplicates requests, and follows visible pages',
      () async {
    final pending = Completer<Res<List<String>>>();
    data.responses[2] = () => pending.future;
    await logic.startContinuousLoading();
    final sameLoad = logic.loadContinuousChapter(2);
    logic.prefetchNextContinuousChapter();
    expect(data.calls, [1, 2]);
    expect(logic.order, 1);
    expect(logic.urls, ['1/0', '1/1', '1/2']);
    pending.complete(const Res(['2/0', '2/1']));
    expect(await sameLoad, isTrue);
    expect(logic.continuousItems.map((item) => item.url),
        ['1/0', '1/1', '1/2', '2/0', '2/1']);
    // Positions need not arrive sorted, and cache-only items must be ignored.
    reportPositions(logic, [position(4, 0.8), position(0, -2), position(3)]);
    expect((logic.order, logic.index, logic.length), (2, 1, 2));
    expect(history.last, (2, 1, 2));
    await flushLoads();
    expect(data.calls, [1, 2, 3]);
    expect(logic.nextContinuousChapter, isNull);
    reportPositions(logic, [position(1)]);
    expect((logic.order, logic.index, logic.length), (1, 2, 3));
    await logic.loadContinuousChapter(2);
    expect(data.calls, [1, 2, 3]);
  });

  test('same page number in the next chapter updates history and continuation',
      () async {
    data.responses[1] = () async => const Res(['1/0']);
    data.responses[2] = () async => const Res(['2/0']);
    var continuationUpdates = 0;
    logic.addIndexChangeCallback((_) => continuationUpdates++);
    await logic.startContinuousLoading();
    await flushLoads();
    reportPositions(logic, [position(1)]);
    expect(history.last, (2, 1, 1));
    expect(continuationUpdates, 1);
    await flushLoads();
  });

  test('failed prefetch preserves current chapter and retries only on request',
      () async {
    data.responses[2] = () async => const Res.error('offline');
    await logic.startContinuousLoading();
    await flushLoads();
    expect(logic.isLoading, isFalse);
    expect(logic.urls, ['1/0', '1/1', '1/2']);
    expect(logic.nextContinuousChapterError, 'offline');
    reportPositions(logic, [position(2)]);
    logic.prefetchNextContinuousChapter();
    expect(data.calls, [1, 2]);
    data.responses[2] = () async => const Res(['2/0']);
    logic.prefetchNextContinuousChapter(retry: true);
    await flushLoads();
    expect(data.calls, [1, 2, 2]);
    expect(logic.continuousItems.last.url, '2/0');
    expect(logic.nextContinuousChapterError, isNull);
  });

  test('initial failures can retry and single-chapter comics never prefetch',
      () async {
    data = TestReadingData(hasEp: false);
    logic.data = data;
    data.responses[1] = () async => throw StateError('offline');
    await logic.startContinuousLoading();
    expect(logic.errorMessage, contains('offline'));
    expect(logic.isLoading, isFalse);
    data.responses[1] = () async => const Res(['one image']);
    logic.change();
    await logic.startContinuousLoading();
    expect(logic.urls, ['one image']);
    expect(logic.nextContinuousChapter, isNull);
    expect(logic.errorMessage, isNull);
    expect(data.calls, [1, 1]);
    expect(await logic.loadContinuousChapter(2), isFalse);
  });

  test('empty chapters show a retryable error', () async {
    data.responses[1] = () async => const Res([]);
    await logic.startContinuousLoading();
    expect(logic.errorMessage, isNotEmpty);
    expect(logic.isLoading, isFalse);
    data.responses[1] = () async => const Res(['1/0']);
    logic.change();
    await logic.startContinuousLoading();
    await flushLoads();
    expect(logic.urls, ['1/0']);
  });

  test('old prefetch cannot append after selecting a different chapter',
      () async {
    final pending = Completer<Res<List<String>>>();
    data.responses[2] = () => pending.future;
    await logic.startContinuousLoading();
    logic.jumpToChapter(3);
    await logic.startContinuousLoading();
    pending.complete(const Res(['obsolete']));
    await flushLoads();
    expect(logic.continuousItems.map((item) => item.chapter), [3, 3, 3]);
    expect(logic.urls, ['3/0', '3/1', '3/2']);
    expect(logic.order, 3);
  });

  test('old initial load cannot overwrite a new chapter or restart prefetch',
      () async {
    final pending = Completer<Res<List<String>>>();
    data.responses[1] = () => pending.future;
    final first = logic.startContinuousLoading();
    logic.jumpToChapter(3);
    await logic.startContinuousLoading();
    pending.complete(const Res(['obsolete']));
    await first;
    expect(logic.continuousItems.map((item) => item.chapter), [3, 3, 3]);
    expect(data.calls, [1, 3]);
  });

  test('jumping to an earlier unloaded chapter resets instead of appending it',
      () async {
    logic.order = 3;
    await logic.startContinuousLoading();
    logic.jumpToLastChapter();
    expect(logic.order, 2);
    expect(logic.isLoading, isTrue);
    await logic.startContinuousLoading();
    await flushLoads();
    expect(
        logic.continuousItems.map((item) => item.chapter), [2, 2, 2, 3, 3, 3]);
    expect(await logic.loadContinuousChapter(1), isFalse);
    expect(data.calls, [3, 2, 3]);
  });

  test('refresh retains the position listener and discards in-flight responses',
      () async {
    final pending = Completer<Res<List<String>>>();
    data.responses[2] = () => pending.future;
    await logic.startContinuousLoading();
    logic.refresh_();
    data.responses[2] = () async => const Res(['fresh']);
    await logic.startContinuousLoading();
    await flushLoads();
    pending.complete(const Res(['obsolete']));
    await flushLoads();
    reportPositions(logic, [position(3)]);
    expect(logic.order, 2);
    expect(logic.urls, ['fresh']);
    await flushLoads();
  });

  Future<ComicReadingPage> mountReader(WidgetTester tester) async {
    final page = ComicReadingPage(data, logic.index, logic.order);
    // Use the logic with the in-memory history callback to exercise the actual
    // image view without platform services or a persistent history database.
    StateController.remove<ComicReadingPageLogic>();
    StateController.put(logic);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
        logic.stateUpdaters = [Pair(null, () => setState(() {}))];
        return Stack(children: [page.buildComicView(logic, context, data.id)]);
      })),
    ));
    await tester.runAsync(() => precacheImage(
        data.image, tester.element(find.byType(ScrollablePositionedList))));
    await tester.pump();
    return page;
  }

  testWidgets(
      'appending keeps scroll position and crosses chapters in one list',
      (tester) async {
    final pending = Completer<Res<List<String>>>();
    data.responses[2] = () => pending.future;
    await logic.startContinuousLoading();
    await mountReader(tester);
    logic.jumpToPage(2);
    await tester.pump();
    await tester.pump();
    final beforeState = tester.state(find.byType(ScrollablePositionedList));
    final before = logic.visibleContinuousPositions.first;
    pending.complete(const Res(['2/0', '2/1']));
    await tester.pump();
    await tester.pump();
    expect(
        tester.state(find.byType(ScrollablePositionedList)), same(beforeState));
    final after = logic.visibleContinuousPositions.first;
    expect(after.index, before.index);
    expect(after.itemLeadingEdge, closeTo(before.itemLeadingEdge, 0.001));
    expect(find.textContaining('下一章:'), findsNothing);
    logic.itemScrollController.jumpTo(index: 3);
    await tester.pump();
    await tester.pump();
    expect((logic.order, logic.index), (2, 1));
    expect(data.imageRequests, contains((2, 0, '2/0')));
    // Appending chapter three while chapter two is current must not replace
    // the PhotoView/list state (which previously used the chapter as its key).
    expect(
        tester.state(find.byType(ScrollablePositionedList)), same(beforeState));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed next chapter can retry inline and keep the current image',
      (tester) async {
    data.responses[2] = () async => const Res.error('offline');
    await logic.startContinuousLoading();
    await tester.pump();
    await mountReader(tester);
    logic.jumpToPage(3);
    await tester.pump();
    await tester.pump();
    await tester.drag(
        find.byType(ScrollablePositionedList), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('offline'), findsOneWidget);
    final pending = Completer<Res<List<String>>>();
    data.responses[2] = () => pending.future;
    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(find.text('offline'), findsNothing);
    expect(logic.order, 1);
    pending.complete(const Res(['2/0', '2/1']));
    await tester.pump();
    await tester.pump();
    for (var attempt = 0; attempt < 3 && logic.order == 1; attempt++) {
      await tester.drag(
          find.byType(ScrollablePositionedList), const Offset(0, -400));
      await tester.pumpAndSettle();
    }
    expect(logic.order, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('explicit next-chapter jump waits for the appended list to build',
      (tester) async {
    final pending = Completer<Res<List<String>>>();
    data.responses[2] = () => pending.future;
    await logic.startContinuousLoading();
    await mountReader(tester);
    logic.jumpToNextChapter();
    pending.complete(const Res(['2/0', '2/1']));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect((logic.order, logic.index), (2, 1));
    expect(logic.visibleContinuousPositions.first.index, 3);
    expect(data.calls.where((chapter) => chapter == 2).length, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'initial page, loaded chapter jumps, and image selection use chapter-local pages',
      (tester) async {
    await logic.startContinuousLoading();
    await tester.pump();
    logic.index = 2;
    final page = await mountReader(tester);
    expect(logic.visibleContinuousPositions.first.index, 1);
    logic.jumpToNextChapter();
    await tester.pump();
    await tester.pump();
    expect((logic.order, logic.index), (2, 1));
    logic.jumpToPage(2);
    await tester.pump();
    await tester.pump();
    reportPositions(logic, [position(4)]);
    final selected = await page.selectImage();
    expect((selected!.chapter, selected.page, selected.url), (2, 1, '2/1'));
    logic.jumpToLastChapter();
    await tester.pump();
    await tester.pump();
    expect((logic.order, logic.index), (1, 1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
