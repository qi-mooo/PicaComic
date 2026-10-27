part of 'comic_reading_page.dart';

extension PageControllerExtension on PageController {
  void animatedJumpToPage(int page) {
    final current = this.page?.round() ?? 0;
    if ((current - page).abs() > 1) {
      jumpToPage(page > current ? page - 1 : page + 1);
    }
    animateToPage(page,
        duration: const Duration(milliseconds: 300), curve: Curves.ease);
  }

  void jumpByDeviceType(int page) {
    if (StateController.find<ComicReadingPageLogic>().mouseScroll) {
      jumpToPage(page);
    } else {
      animatedJumpToPage(page);
    }
  }
}

class ContinuousImageItem {
  final int chapter;
  final int page;
  final String url;

  const ContinuousImageItem(this.chapter, this.page, this.url);
}

class ComicReadingPageLogic extends StateController {
  ///控制页面, 用于非从上至下(连续)阅读方式
  late PageController pageController;

  ///用于从上至下(连续)阅读方式, 跳转至指定项目
  var itemScrollController = ItemScrollController();

  ///用于从上至下(连续)阅读方式, 获取当前滚动到的元素的序号
  var itemScrollListener = ItemPositionsListener.create();

  ///用于从上至下(连续)阅读方式, 控制滚动
  var scrollController = ScrollController(keepScrollOffset: true);

  ///用于从上至下(连续)阅读方式, 获取放缩大小
  PhotoViewController get photoViewController =>
      photoViewControllers[index] ?? photoViewControllers[0]!;

  var photoViewControllers = <int, PhotoViewController>{};

  /// Images loaded into the seamless continuous reader, in display order.
  final continuousItems = <ContinuousImageItem>[];
  final continuousChapterUrls = <int, List<String>>{};
  final _continuousLoads = <int, Future<bool>>{};
  final _continuousChapterErrors = <int, String>{};
  final _continuousImageKeys = <String>{};
  int _continuousGeneration = 0;
  bool continuousLoadingStarted = false;

  ListenVolumeController? listenVolume;

  ScrollManager? scrollManager;

  String? errorMessage;

  void clearPhotoViewControllers() {
    photoViewControllers.forEach((key, value) => value.dispose());
    photoViewControllers.clear();
  }

  bool noScroll = false;

  bool mouseScroll = false;

  double currentScale = 1.0;

  bool get isCtrlPressed => HardwareKeyboard.instance.isControlPressed;

  List<bool> requestedLoadingItems = [];

  bool isOnChapterCommentsPage = false;

  /// 当前是否为连续滚动阅读模式
  bool get isContinuousMode =>
      readingMethod == ReadingMethod.topToBottomContinuously;

  /// 是否已滚动到本章开头(带 2px 容差, 避免浮点严格相等判断失效)
  bool get isAtScrollStart =>
      scrollController.hasClients &&
      scrollController.position.pixels <=
          scrollController.position.minScrollExtent + 2;

  /// 是否已滚动到本章末尾(带 2px 容差)
  bool get isAtScrollEnd =>
      scrollController.hasClients &&
      scrollController.position.pixels >=
          scrollController.position.maxScrollExtent - 2;

  /// 已滚动到章末且存在下一章
  bool get isAtChapterEnd =>
      isContinuousMode &&
      data.hasEp &&
      order < (data.eps?.length ?? 1) &&
      isAtScrollEnd;

  /// 已滚动到章首且存在上一章
  bool get isAtChapterStart =>
      isContinuousMode && data.hasEp && order > 1 && isAtScrollStart;

  /// 双页模式下是否在第一页时显示单页
  bool get singlePageForFirstScreen => appdata.implicitData[1] == '1';

  var focusNode = FocusNode();

  static int _getIndex(int initPage) {
    if (appdata.settings[9] == "5" || appdata.settings[9] == "6") {
      return initPage % 2 == 1 ? initPage : initPage - 1;
    } else {
      return initPage;
    }
  }

  static int _getPage(int initPage) {
    if (appdata.settings[9] == "5" || appdata.settings[9] == "6") {
      return (initPage + 2) ~/ 2;
    } else {
      return initPage;
    }
  }

  ComicReadingPageLogic(
      this.order, this.data, int initialPage, this.updateHistory) {
    if (initialPage <= 0) {
      initialPage = 1;
    }
    pageController = _createPageController(_getPage(initialPage));
    _index = _getIndex(initialPage);
    order <= 0 ? order = 1 : order;
    itemScrollListener.itemPositions.addListener(_onContinuousPositionsChanged);
  }

  List<ItemPosition> get visibleContinuousPositions =>
      itemScrollListener.itemPositions.value
          .where((item) =>
              item.itemLeadingEdge < 1 &&
              item.itemTrailingEdge > 0 &&
              item.index >= 0 &&
              item.index < continuousItems.length)
          .toList()
        ..sort((a, b) => a.itemLeadingEdge.compareTo(b.itemLeadingEdge));

  void _onContinuousPositionsChanged() {
    if (!isContinuousMode || isLoading) return;
    final positions = visibleContinuousPositions;
    if (positions.isEmpty) return;
    _setContinuousPosition(continuousItems[positions.first.index]);
    // Keep one chapter ahead, even when two short chapters share the viewport.
    if (continuousItems[positions.last.index].chapter ==
        continuousItems.last.chapter) {
      prefetchNextContinuousChapter();
    }
  }

  void _setContinuousPosition(ContinuousImageItem item) {
    final chapterChanged = order != item.chapter;
    order = item.chapter;
    urls = continuousChapterUrls[item.chapter]!;
    if (index != item.page + 1) {
      index = item.page + 1;
    } else if (chapterChanged) {
      // One-page chapters still need a history/continuation update.
      for (final callback in _indexChangeCallbacks) {
        callback(index);
      }
      updateHistory();
      update(["ToolBar"]);
    }
  }

  PageController _createPageController(int initialPage) {
    final controller = PageController(initialPage: initialPage);
    controller.addListener(() {
      _syncIndexFromPageController();
    });
    return controller;
  }

  void _syncIndexFromPageController() {
    if (urls.isEmpty ||
        readingMethod == ReadingMethod.topToBottomContinuously ||
        !pageController.hasClients) {
      return;
    }
    final page = pageController.page?.round();
    if (page == null) {
      return;
    }
    int? newIndex;
    if (readingMethod.isTwoPage) {
      if (page <= 0) {
        return;
      }
      newIndex = singlePageForFirstScreen
          ? (page * 2 - 2).clamp(1, urls.length)
          : page * 2 - 1;
    } else {
      if (page <= 0 || page > urls.length) {
        return;
      }
      newIndex = page;
    }
    if (newIndex >= 1 && newIndex <= urls.length && newIndex != index) {
      index = newIndex;
    }
  }

  final void Function() updateHistory;

  ReadingData data;

  bool isLoading = true;

  ///旋转方向: null-跟随系统, false-竖向, true-横向
  bool? rotation;

  ///当前的页面, 0和最后一个为空白页, 用于进行章节跳转
  late int _index;

  ///当前的页面, 0和最后一个为空白页, 用于进行章节跳转
  int get index => _index;

  ///当前的页面, 0和最后一个为空白页, 用于进行章节跳转
  set index(int value) {
    if (_index == value) {
      return;
    }
    _index = value;
    for (var element in _indexChangeCallbacks) {
      element(value);
    }
    updateHistory();
    update(["ToolBar"]);
  }

  final _indexChangeCallbacks = <void Function(int)>[];

  void Function(int)? continuationIndexCallback;

  void addIndexChangeCallback(void Function(int) callback) {
    _indexChangeCallbacks.add(callback);
  }

  void removeIndexChangeCallback(void Function(int) callback) {
    _indexChangeCallbacks.remove(callback);
  }

  ///当前的章节位置, 从1开始
  int order;

  ///工具栏是否打开
  bool tools = false;

  ///是否显示设置窗口
  bool showSettings = false;

  ///所有的图片链接
  var urls = <String>[];

  void reload() {
    index = 1;
    isOnChapterCommentsPage = false;
    pageController = _createPageController(1);
    isLoading = true;
    if (isContinuousMode) {
      urls = [];
      errorMessage = null;
      resetContinuousState();
    }
    requestedLoadingItems = [];
    update();
  }

  void change() {
    if (isContinuousMode) {
      urls = [];
      errorMessage = null;
      isLoading = true;
      resetContinuousState();
      update();
      return;
    }
    isLoading = !isLoading;
    update();
  }

  ReadingMethod get readingMethod =>
      ReadingMethod.values[int.parse(appdata.settings[9]) - 1];

  void jumpToNextPage() {
    if (isContinuousMode) {
      if (!scrollController.hasClients) return;
      if (isAtChapterEnd) {
        prefetchNextContinuousChapter();
      }
      scrollController.jumpTo((scrollController.position.pixels + 600).clamp(
          scrollController.position.minScrollExtent,
          scrollController.position.maxScrollExtent));
      return;
    }
    if (readingMethod.index < 3) {
      pageController.jumpToPage(index + 1);
    } else {
      pageController.jumpToPage(pageController.page!.round() + 1);
    }
  }

  void jumpToLastPage() {
    if (isContinuousMode) {
      if (!scrollController.hasClients) return;
      if (isAtChapterStart) {
        jumpToLastChapter();
        return;
      }
      scrollController.jumpTo((scrollController.position.pixels - 600).clamp(
          scrollController.position.minScrollExtent,
          scrollController.position.maxScrollExtent));
      return;
    }
    if (readingMethod.index < 3) {
      pageController.jumpToPage(index - 1);
    } else {
      pageController.jumpToPage(pageController.page!.round() - 1);
    }
  }

  void jumpToPage(int i, [bool updateWidget = false]) {
    if (length == 0) return;
    i = i.clamp(1, length);
    if (readingMethod == ReadingMethod.topToBottomContinuously) {
      final target = continuousItems
          .indexWhere((item) => item.chapter == order && item.page == i - 1);
      if (target >= 0 && itemScrollController.isAttached) {
        itemScrollController.jumpTo(index: target);
      }
    } else if (!readingMethod.isTwoPage) {
      pageController.jumpToPage(i);
    } else {
      var page = singlePageForFirstScreen ? i ~/ 2 + 1 : (i + 1) ~/ 2;
      pageController.jumpToPage(page);
    }
    if (index != i) {
      index = i;
    }
    if (updateWidget) {
      update(["ToolBar"]);
    }
  }

  void jumpByDeviceType(int page) {
    Future.microtask(() {
      if (mouseScroll) {
        pageController.jumpToPage(page);
      } else {
        pageController.animatedJumpToPage(page);
      }
    });
  }

  void jumpToNextChapter() {
    var eps = data.eps;
    if (!data.hasEp || order == eps?.length) {
      if (readingMethod != ReadingMethod.topToBottomContinuously) {
        if (readingMethod.index < 3) {
          jumpByDeviceType(urls.length);
        } else if (readingMethod == ReadingMethod.twoPage) {
          jumpByDeviceType((urls.length % 2 + urls.length) ~/ 2);
        }
      } else {
        jumpToPage(urls.length);
        index = urls.length;
        update(["ToolBar"]);
      }
      return;
    }
    if (isContinuousMode) {
      unawaited(_jumpToContinuousChapter(order + 1));
      return;
    }
    order += 1;
    urls = [];
    isLoading = true;
    tools = false;
    index = 1;
    isOnChapterCommentsPage = false;
    pageController = _createPageController(1);
    requestedLoadingItems = [];
    resetContinuousState();
    clearPhotoViewControllers();
    update();
  }

  void jumpToChapter(int index) {
    order = index;
    errorMessage = null;
    urls = [];
    isLoading = true;
    tools = false;
    this.index = 1;
    isOnChapterCommentsPage = false;
    pageController = _createPageController(1);
    requestedLoadingItems = [];
    resetContinuousState();
    clearPhotoViewControllers();
    update();
  }

  void jumpToLastChapter() {
    if (order == 1 || !data.hasEp) {
      if (readingMethod != ReadingMethod.topToBottomContinuously) {
        jumpByDeviceType(1);
      } else {
        jumpToPage(1);
        index = 1;
        update(["ToolBar"]);
      }
      return;
    }

    if (isContinuousMode) {
      unawaited(_jumpToContinuousChapter(order - 1));
      return;
    }
    order -= 1;
    urls = [];
    isLoading = true;
    tools = false;
    isOnChapterCommentsPage = false;
    pageController = _createPageController(1);
    index = 1;
    requestedLoadingItems = [];
    clearPhotoViewControllers();
    update();
  }

  ///当前章节的长度
  int get length => urls.length;

  /// 是否处于自动翻页状态
  bool runningAutoPageTurning = false;

  /// 自动翻页
  void autoPageTurning() async {
    if (isContinuousMode
        ? nextContinuousChapter == null && isAtScrollEnd
        : index == urls.length - 1) {
      runningAutoPageTurning = false;
      update();
      return;
    }
    int sec = int.parse(appdata.settings[33]);
    for (int i = 0; i < sec * 10; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (!runningAutoPageTurning) {
        return;
      }
    }
    jumpToNextPage();
    autoPageTurning();
  }

  void refresh_() {
    pageController = _createPageController(1);
    scrollController = ScrollController(keepScrollOffset: true);
    clearPhotoViewControllers();
    noScroll = false;
    currentScale = 1.0;
    index = 1;
    urls = [];
    errorMessage = null;
    isLoading = true;
    tools = false;
    showSettings = false;
    requestedLoadingItems = [];
    resetContinuousState();
    update();
  }

  int get continuousItemIndex => continuousItems
      .indexWhere((item) => item.chapter == order && item.page == index - 1);

  int? get nextContinuousChapter {
    if (!data.hasEp || continuousItems.isEmpty) return null;
    final next = continuousItems.last.chapter + 1;
    return next <= (data.eps?.length ?? 0) ? next : null;
  }

  String? get nextContinuousChapterError =>
      _continuousChapterErrors[nextContinuousChapter];

  void resetContinuousState() {
    _continuousGeneration++;
    continuousItems.clear();
    continuousChapterUrls.clear();
    _continuousLoads.clear();
    _continuousChapterErrors.clear();
    _continuousImageKeys.clear();
    continuousLoadingStarted = false;
  }

  /// Marks an image as requested by the continuous-reader preloader.
  bool markContinuousImagePrecached(String key) =>
      _continuousImageKeys.add(key);

  void prefetchNextContinuousChapter({bool retry = false}) {
    final chapter = nextContinuousChapter;
    if (chapter == null ||
        (!retry && _continuousChapterErrors.containsKey(chapter))) {
      return;
    }
    unawaited(loadContinuousChapter(chapter));
  }

  Future<bool> loadContinuousChapter(int chapter) {
    if (chapter <= 0 ||
        (data.hasEp && chapter > (data.eps?.length ?? 0)) ||
        (!data.hasEp && chapter != 1)) {
      return Future.value(false);
    }
    if (continuousChapterUrls.containsKey(chapter)) return Future.value(true);
    // Append only adjacent chapters; earlier/unrelated chapter jumps reset the
    // list instead of inserting images above the reader's scroll position.
    if (continuousItems.isNotEmpty &&
        chapter != continuousItems.last.chapter + 1) {
      return Future.value(false);
    }
    final existing = _continuousLoads[chapter];
    if (existing != null) return existing;
    final generation = _continuousGeneration;
    final hadError = _continuousChapterErrors.remove(chapter) != null;
    final future = () async {
      try {
        final res = await Future.sync(() => data.loadEp(chapter));
        if (generation != _continuousGeneration) return false;
        if (res.error || res.data.isEmpty) {
          _continuousChapterErrors[chapter] =
              res.error ? res.errorMessageWithoutNull : "章节没有图片".tl;
          return false;
        }
        final chapterUrls = List<String>.unmodifiable(res.data);
        continuousChapterUrls[chapter] = chapterUrls;
        continuousItems.addAll(chapterUrls.indexed
            .map((entry) => ContinuousImageItem(chapter, entry.$1, entry.$2)));
        return true;
      } catch (error) {
        if (generation == _continuousGeneration) {
          _continuousChapterErrors[chapter] = error.toString();
        }
        return false;
      } finally {
        if (generation == _continuousGeneration) {
          _continuousLoads.remove(chapter);
          if (!isLoading) update();
        }
      }
    }();
    _continuousLoads[chapter] = future;
    if (hadError && !isLoading) update();
    return future;
  }

  Future<void> startContinuousLoading() async {
    if (continuousLoadingStarted) return;
    final generation = _continuousGeneration;
    final chapter = order;
    continuousLoadingStarted = true;
    final loaded = await loadContinuousChapter(chapter);
    if (generation != _continuousGeneration) return;
    if (!loaded) {
      errorMessage = _continuousChapterErrors[chapter] ?? '章节加载失败'.tl;
      urls = [];
      isLoading = false;
      continuousLoadingStarted = false;
      update();
      return;
    }
    urls = continuousChapterUrls[chapter]!;
    _index = index.clamp(1, urls.length);
    errorMessage = null;
    isLoading = false;
    update();
    prefetchNextContinuousChapter();
  }

  Future<void> _jumpToContinuousChapter(int chapter) async {
    if (chapter < 1 || chapter > (data.eps?.length ?? 1)) return;
    if (!continuousChapterUrls.containsKey(chapter) &&
        chapter != nextContinuousChapter) {
      jumpToChapter(chapter);
      return;
    }
    final generation = _continuousGeneration;
    final loaded = await loadContinuousChapter(chapter);
    if (!loaded || generation != _continuousGeneration) return;
    // The list must rebuild with the appended items before jumpTo, otherwise
    // ScrollablePositionedList clamps the target to the previous item count.
    await WidgetsBinding.instance.endOfFrame;
    if (generation != _continuousGeneration ||
        !itemScrollController.isAttached) {
      return;
    }
    final target =
        continuousItems.indexWhere((item) => item.chapter == chapter);
    if (target < 0) return;
    tools = false;
    _setContinuousPosition(continuousItems[target]);
    itemScrollController.jumpTo(index: target);
    update();
  }

  bool isFullScreen = false;
  Rect? _preFullscreenRect;
  bool _wasMaximized = false;

  void fullscreen() async {
    if (App.isDesktop) {
      if (isFullScreen) {
        isFullScreen = false;
        await windowManager.setFullScreen(false);
        if (_wasMaximized) {
          await windowManager.maximize();
        } else if (_preFullscreenRect != null) {
          await windowManager.setBounds(_preFullscreenRect!);
        }
      } else {
        isFullScreen = true;
        _wasMaximized = await windowManager.isMaximized();
        if (!_wasMaximized) {
          _preFullscreenRect = await windowManager.getBounds();
        }
        await windowManager.setFullScreen(true);
      }
    } else {
      const channel = MethodChannel("pica_comic/full_screen");
      channel.invokeMethod("set", !isFullScreen);
      isFullScreen = !isFullScreen;
    }
    WindowFrame.of(App.globalContext!).setWindowFrame(!isFullScreen);
    focusNode.requestFocus();
  }

  void handleKeyboard(KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      bool reverse = appdata.settings[9] == "2" || appdata.settings[9] == "6";
      switch (event.logicalKey) {
        case LogicalKeyboardKey.arrowDown:
        case LogicalKeyboardKey.arrowRight:
          reverse ? jumpToLastPage() : jumpToNextPage();
        case LogicalKeyboardKey.arrowUp:
        case LogicalKeyboardKey.arrowLeft:
          reverse ? jumpToNextPage() : jumpToLastPage();
        case LogicalKeyboardKey.f12:
          fullscreen();
      }
    }
  }

  late final void Function() openEpsView;
}
