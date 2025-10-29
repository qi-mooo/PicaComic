part of pica_reader;

abstract class ReadingData {
  ReadingData();

  String get title;

  String get id;

  String get downloadId;

  ComicType get type;

  String get sourceKey;

  bool get hasEp;

  Map<String, String>? get eps;

  bool get downloaded => DownloadManager().isExists(downloadId);

  List<int> downloadedEps = [];

  String get favoriteId => id;

  FavoriteType get favoriteType;

  bool checkEpDownloaded(int ep) {
    return !hasEp || downloadedEps.contains(ep-1);
  }

  Future<Res<List<String>>> loadEp(int ep) async {
    if(downloaded && downloadedEps.isEmpty){
      downloadedEps = (await DownloadManager().getComicOrNull(downloadId))!.downloadedEps;
    }
    if (downloaded && checkEpDownloaded(ep)){
      int length;
      if(hasEp) {
        length = await DownloadManager().getEpLength(downloadId, ep);
      } else {
        length = await DownloadManager().getComicLength(downloadId);
      }
      return Res(List.filled(length, ""));
    } else {
      return await loadEpNetwork(ep);
    }
  }

  /// Load image from local or network
  ///
  /// [page] starts from 0, [ep] starts from 1
  Stream<DownloadProgress> loadImage(int ep, int page, String url) async* {
    if (downloaded && checkEpDownloaded(ep)) {
      yield DownloadProgress(
          1, 1, "", DownloadManager().getImage(downloadId, hasEp ? ep : 0, page).path);
    } else {
      yield* loadImageNetwork(ep, page, url);
    }
  }

  ImageProvider createImageProvider(int ep, int page, String url){
    if (downloaded && checkEpDownloaded(ep)){
      return FileImageProvider(downloadId, hasEp ? ep : 0, page);
    } else {
      return StreamImageProvider(() => loadImage(ep, page, url), buildImageKey(ep, page, url));
    }
  }

  String buildImageKey(int ep, int page, String url) => url;

  Future<Res<List<String>>> loadEpNetwork(int ep);

  Stream<DownloadProgress> loadImageNetwork(int ep, int page, String url);
}

class PicacgReadingData extends ReadingData {
  @override
  final String title;

  @override
  final String id;

  PicacgReadingData(this.title, this.id, List<String> epsList)
      : eps = {for (var e in epsList) e: e};

  @override
  final Map<String, String> eps;

  @override
  bool get hasEp => true;

  @override
  String get sourceKey => "picacg";

  @override
  ComicType get type => ComicType.picacg;

  @override
  String get downloadId => id;

  @override
  Future<Res<List<String>>> loadEpNetwork(int ep) {
    return PicacgNetwork().getComicContent(id, ep);
  }

  @override
  Stream<DownloadProgress> loadImageNetwork(int ep, int page, String url) {
    return ImageManager().getImage(url);
  }

  @override
  FavoriteType get favoriteType => FavoriteType.picacg;
}

class EhReadingData extends ReadingData {
  final Gallery gallery;

  EhReadingData(this.gallery);

  @override
  bool get hasEp => eps != null;

  @override
  String get sourceKey => "ehentai";

  @override
  ComicType get type => ComicType.ehentai;

  @override
  String get downloadId => getGalleryId(id);

  @override
  Future<Res<List<String>>> loadEpNetwork(int ep) {
    return Future.value(Res(List.filled(int.parse(gallery.maxPage), "")));
  }

  @override
  Stream<DownloadProgress> loadImageNetwork(int ep, int page, String url) {
    return ImageManager().getEhImageNew(gallery, page+1);
  }

  @override
  Map<String, String>? get eps => null;

  @override
  String get id => gallery.link;

  @override
  String get title => gallery.title;

  @override
  String buildImageKey(int ep, int page, String url) => "${gallery.link}$page";

  @override
  FavoriteType get favoriteType => FavoriteType.ehentai;
}

class JmReadingData extends ReadingData {
  @override
  final String title;

  @override
  final String id;

  int? commentsLength;
  
  static Map<String, String> generateMap(List<String> epIds, List<String> epNames){
    if(epIds.length == epNames.length){
      return Map.fromIterables(epIds, epNames);
    } else {
      return Map.fromIterables(epIds, List.generate(epIds.length, (index) => "第${index+1}章"));
    }
  }

  JmReadingData(this.title, this.id, List<String> epIds, List<String> epNames)
      : eps = generateMap(epIds, epNames);

  @override
  bool get hasEp => true;

  @override
  String get sourceKey => "jm";

  @override
  ComicType get type => ComicType.jm;

  @override
  String get downloadId => "jm$id";

  @override
  Future<Res<List<String>>> loadEpNetwork(int ep) async{
    var res = await JmNetwork().getChapter(eps.keys.elementAtOrNull(ep-1) ?? id);
    commentsLength = res.subData;
    return res;
  }

  @override
  Stream<DownloadProgress> loadImageNetwork(int ep, int page, String url) {
    var bookId = "";
    for (int i = url.length - 1; i >= 0; i--) {
      if (url[i] == '/') {
        bookId = url.substring(i + 1, url.length - 5);
        break;
      }
    }
    return ImageManager().getJmImage(url, null,
        epsId: eps.keys.elementAtOrNull(ep-1) ?? id,
        scrambleId: "220980",
        bookId: bookId);
  }

  @override
  final Map<String, String> eps;

  @override
  String buildImageKey(int ep, int page, String url) => url.replaceAll(RegExp(r"\?.+"), "");

  @override
  FavoriteType get favoriteType => FavoriteType.jm;
}

class HitomiReadingData extends ReadingData {
  @override
  final String title;

  @override
  final String id;

  final List<HitomiFile> images;

  final String link;

  HitomiReadingData(this.title, this.id, this.images, this.link);

  @override
  Map<String, String>? get eps => null;

  @override
  bool get hasEp => false;

  @override
  String get sourceKey => "hitomi";

  @override
  ComicType get type => ComicType.hitomi;

  @override
  String get downloadId => "hitomi$id";

  @override
  String get favoriteId => link;

  @override
  Future<Res<List<String>>> loadEpNetwork(int ep) {
    return Future.value(Res(List.filled(images.length, "")));
  }

  @override
  Stream<DownloadProgress> loadImageNetwork(int ep, int page, String url) {
    return ImageManager().getHitomiImage(images[page], id);
  }

  @override
  String buildImageKey(int ep, int page, String url) => images[page].hash;

  @override
  FavoriteType get favoriteType => FavoriteType.hitomi;
}

class HtReadingData extends ReadingData {
  @override
  final String title;

  @override
  final String id;

  HtReadingData(this.title, this.id,);

  @override
  Map<String, String>? get eps => null;

  @override
  bool get hasEp => false;

  @override
  String get sourceKey => "htManga";

  @override
  ComicType get type => ComicType.htManga;

  @override
  String get downloadId => "Ht$id";

  @override
  Future<Res<List<String>>> loadEpNetwork(int ep) {
    return HtmangaNetwork().getImages(id);
  }

  @override
  Stream<DownloadProgress> loadImageNetwork(int ep, int page, String url) {
    return ImageManager().getImage(url);
  }

  @override
  FavoriteType get favoriteType => FavoriteType.htManga;
}

class NhentaiReadingData extends ReadingData {
  @override
  final String title;

  @override
  final String id;

  NhentaiReadingData(this.title, this.id);

  @override
  Map<String, String>? get eps => null;

  @override
  bool get hasEp => false;

  @override
  String get sourceKey => "nhentai";

  @override
  ComicType get type => ComicType.nhentai;

  @override
  String get downloadId => "nhentai$id";

  @override
  Future<Res<List<String>>> loadEpNetwork(int ep) {
    return NhentaiNetwork().getImages(id);
  }

  @override
  Stream<DownloadProgress> loadImageNetwork(int ep, int page, String url) {
    return ImageManager().getImage(url);
  }

  @override
  FavoriteType get favoriteType => FavoriteType.nhentai;
}

class CustomReadingData extends ReadingData{
  CustomReadingData(this.id, this.title, this.source, this.eps);

  final ComicSource? source;

  @override
  String get downloadId => DownloadManager().generateId(sourceKey, id);

  @override
  final Map<String, String>? eps;

  @override
  bool get hasEp => eps != null;

  @override
  String id;

  @override
  final String title;

  @override
  Future<Res<List<String>>> loadEpNetwork(int ep) {
    if(source == null) {
      return Future.value(const Res.error("Unknown Comic Source"));
    }
    if(hasEp){
      return source!.loadComicPages!(id, eps!.keys.elementAtOrNull(ep-1) ?? id);
    } else {
      return source!.loadComicPages!(id, null);
    }
  }

  @override
  Stream<DownloadProgress> loadImageNetwork(int ep, int page, String url) {
    return ImageManager().getCustomImage(
        url,
        id,
        eps?.keys.elementAtOrNull(ep-1) ?? id,
        sourceKey
    );
  }

  @override
  String get sourceKey => source?.key ?? "";

  @override
  ComicType get type => ComicType.other;

  @override
  String buildImageKey(int ep, int page, String url) =>
      "$sourceKey$id${eps!.keys.elementAtOrNull(ep-1) ?? id}$url";

  @override
  FavoriteType get favoriteType => FavoriteType(source!.intKey);
}

class ServerReadingData extends ReadingData {
  final String serverUrl;
  final ServerComicDetail comic;

  ServerReadingData({
    required this.serverUrl,
    required this.comic,
  }) {
    downloadedEps = comic.downloadedEps ?? [];
  }

  @override
  String get title => comic.title;

  @override
  String get id => comic.id;

  @override
  String get downloadId => 'server_${comic.id}';

  @override
  String get sourceKey => comic.type;

  @override
  ComicType get type {
    switch (comic.type) {
      case 'picacg':
        return ComicType.picacg;
      case 'jm':
        return ComicType.jm;
      case 'ehentai':
        return ComicType.ehentai;
      case 'nhentai':
        return ComicType.nhentai;
      case 'htManga':
        return ComicType.htManga;
      case 'hitomi':
        return ComicType.hitomi;
      default:
        return ComicType.other;
    }
  }

  @override
  bool get hasEp => (comic.eps?.isNotEmpty ?? false);

  @override
  Map<String, String>? get eps {
    if (comic.eps == null) return null;
    return Map.fromIterables(
      List.generate(comic.eps!.length, (i) => i.toString()),
      comic.eps!,
    );
  }

  @override
  bool get downloaded => true; // 服务器漫画已下载

  @override
  FavoriteType get favoriteType {
    switch (comic.type) {
      case 'picacg':
        return FavoriteType.picacg;
      case 'jm':
        return FavoriteType.jm;
      case 'ehentai':
        return FavoriteType.ehentai;
      case 'nhentai':
        return FavoriteType.nhentai;
      case 'htManga':
        return FavoriteType.htManga;
      case 'hitomi':
        return FavoriteType.hitomi;
      default:
        return FavoriteType(99); // 服务器漫画
    }
  }

  @override
  Future<Res<List<String>>> loadEpNetwork(int ep) async {
    // 服务器漫画从服务器获取准确的页面数量
    try {
      final client = ServerClient(serverUrl);
      final pageCount = await client.getEpisodePageCount(comic.id, ep);
      
      // 返回空URL列表，实际图片从服务器获取
      return Res(List.filled(pageCount, ""));
    } catch (e) {
      // 如果获取失败，使用估算值
      int pageCount = 200; // 默认最大页数
      
      if (comic.epsCount > 0 && comic.pagesCount > 0) {
        // 使用平均页数作为估算
        pageCount = (comic.pagesCount / comic.epsCount).ceil() + 10; // 添加缓冲
      }
      
      return Res(List.filled(pageCount, ""));
    }
  }

  @override
  Stream<DownloadProgress> loadImageNetwork(int ep, int page, String url) async* {
    // 服务器漫画从服务器API获取图片
    // 注意：page参数从0开始，但服务器图片ID从1开始
    // JM 漫画的图片已在服务器端进行了反混淆处理
    final client = ServerClient(serverUrl);
    final imageUrl = client.getComicPageUrl(comic.id, ep, page + 1);
    
    yield* ImageManager().getImage(imageUrl);
  }

  @override
  String buildImageKey(int ep, int page, String url) {
    return '${comic.id}_${ep}_$page';
  }
}
