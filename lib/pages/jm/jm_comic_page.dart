import 'package:flutter/material.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/comic_source/built_in/jm.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/components/select_download_eps.dart';
import 'package:pica_comic/network/jm_network/jm_download.dart';
import 'package:pica_comic/network/jm_network/jm_image.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/pages/comic_page.dart';
import 'package:pica_comic/pages/reader/comic_reading_page.dart';
import 'package:pica_comic/pages/search_result_page.dart';
import 'package:pica_comic/tools/extensions.dart';
import 'package:pica_comic/tools/translations.dart';

import '../../foundation/app.dart';
import '../../foundation/history.dart';
import '../../foundation/local_favorites.dart';
import '../../foundation/ui_mode.dart';
import '../../network/download.dart';
import '../../network/jm_network/jm_models.dart';
import '../../network/jm_network/jm_network.dart';
import '../../network/server_client.dart';
import 'jm_comments_page.dart';

class JmComicPage extends BaseComicPage<JmComicInfo> {
  const JmComicPage(this.id, {super.key});

  @override
  final String id;

  @override
  ActionFunc? get onLike => () {
        if (!data!.liked) {
          jmNetwork.likeComic(data!.id);
        }
        data!.liked = true;
        update();
      };

  @override
  bool get isLiked => data!.liked;

  @override
  String? get likeCount => data!.likes.toString().replaceLast("000", "K");

  @override
  void openFavoritePanel() {
    favoriteComic(FavoriteComicWidget(
      havePlatformFavorite: jm.isLogin,
      needLoadFolderData: true,
      setFavorite: (b) {
        if (favorite != b) {
          favorite = b;
          update();
        }
      },
      foldersLoader: () async {
        var res = await jmNetwork.getFolders();
        if (res.error) {
          return res;
        } else {
          var resData = <String, String>{"0": "全部收藏".tl};
          resData.addAll(res.data);
          return Res(resData);
        }
      },
      localFavoriteItem: toLocalFavoriteItem(),
      favoriteOnPlatform: data!.favorite,
      selectFolderCallback: (folder, page) async {
        if (page == 0) {
          var res = await jmNetwork.favorite(id, folder);
          if (res.success) {
            data!.favorite = true;
          }
          return res;
        } else {
          LocalFavoritesManager().addComic(
            folder,
            toLocalFavoriteItem(),
          );
          return const Res(true);
        }
      },
      cancelPlatformFavorite: () async {
        var res = await jmNetwork.favorite(id, null);
        if (res.success) {
          data!.favorite = false;
        }
        return res;
      },
    ));
  }

  @override
  ActionFunc? get openComments => () {
        showComments(App.globalContext!, id, data!.comments);
      };

  @override
  String get cover => getJmCoverUrl(id);

  @override
  void download() => downloadComic(data!, App.globalContext!);

  String _getEpName(int index) {
    final epName = data!.epNames.elementAtOrNull(index);
    if (epName != null) {
      return epName;
    }
    var name = "第 @c 章".tlParams({"c": (index + 1).toString()});
    return name;
  }

  @override
  EpsData? get eps {
    return EpsData(
      List<String>.generate(
          data!.series.values.length, (index) => _getEpName(index)),
      (i) async {
        await History.findOrCreate(data!);
        App.globalTo(() => ComicReadingPage.jmComic(data!, i + 1));
      },
    );
  }

  @override
  String? get introduction => data!.description;

  @override
  Future<Res<JmComicInfo>> loadData() => JmNetwork().getComicInfo(id);

  @override
  int? get pages => null;

  @override
  Future<bool> loadFavorite(JmComicInfo data) async {
    return data.favorite ||
        (await LocalFavoritesManager().findWithModel(toLocalFavoriteItem()))
            .isNotEmpty;
  }

  @override
  void read(History? history) async {
    history = await History.createIfNull(history, data!);
    App.globalTo(
      () => ComicReadingPage.jmComic(
        data!,
        history!.ep,
        initialPage: history.page,
      ),
    );
  }

  @override
  Widget recommendationBuilder(JmComicInfo data) =>
      SliverGridComics(comics: data.relatedComics, sourceKey: 'jm');

  @override
  String get tag => "Jm ComicPage $id";

  @override
  Map<String, List<String>>? get tags => {
        "ID": "JM${data!.id}".toList(),
        "作者".tl: (data!.author.isEmpty) ? "未知".tl.toList() : data!.author,
        if (data!.works.isNotEmpty) "作品".tl: data!.works,
        if (data!.actors.isNotEmpty) "登场人物".tl: data!.actors,
        if (data!.tags.isNotEmpty) "标签".tl: data!.tags
      };

  @override
  void tapOnTag(String tag, String key) => context.to(() => SearchResultPage(
        keyword: tag,
        sourceKey: "jm",
      ));

  @override
  ThumbnailsData? get thumbnailsCreator => null;

  @override
  String? get title => data?.name;

  @override
  Card? get uploaderInfo => null;

  @override
  String get source => "禁漫天堂".tl;

  @override
  FavoriteItem toLocalFavoriteItem() => FavoriteItem.fromJmComic(JmComicBrief(
      id,
      data!.author.elementAtOrNull(0) ?? "",
      data!.name,
      data!.description, []));

  @override
  String get downloadedId => "jm${data!.id}";

  @override
  String get sourceKey => "jm";
}

void downloadComic(JmComicInfo comic, BuildContext context) async {
  for (var i in downloadManager.downloading) {
    if (i.id == comic.id) {
      showToast(message: "下载中".tl);
      return;
    }
  }

  List<String> eps = [];
  if (comic.series.isEmpty) {
    eps.add("第1章".tl);
  } else {
    eps = List<String>.generate(comic.series.length,
        (index) => "第 @c 章".tlParams({"c": (index + 1).toString()}));
  }

  var downloaded = <int>[];
  if (DownloadManager().isExists("jm${comic.id}")) {
    var downloadedComic = (await DownloadManager()
        .getComicOrNull("jm${comic.id}"))! as DownloadedJmComic;
    downloaded.addAll(downloadedComic.downloadedEps);
  }

  Future<void> downloadToServer(List<int> selectedEps) async {
    final serverUrl = appdata.settings[90];
    if (serverUrl.isEmpty) {
      showToast(message: "请先在设置中配置服务器地址".tl);
      return;
    }

    final sanitized =
        selectedEps.where((idx) => idx >= 0 && idx < eps.length).toList();

    if (sanitized.isEmpty) {
      showToast(message: "请选择章节".tl);
      return;
    }

    showLoadingDialog(App.globalContext!, allowCancel: false);
    try {
      // 处理单章漫画（series 为空的情况）
      if (comic.series.isEmpty) {
        comic.series[1] = comic.id;
      }
      
      // 🆕 使用直接下载模式：拦截客户端获取的URL并发送到服务器
      final network = JmNetwork();
      final episodes = <DirectEpisode>[];
      
      for (var idx in sanitized) {
        // JM 的章节索引从 1 开始
        final chapterKey = idx + 1;
        final epName = eps[idx];
        final chapterId = comic.series[chapterKey];
        
        if (chapterId == null) {
          print('[JM下载] 警告: 章节 $chapterKey 没有对应的 chapterId');
          continue;
        }
        
        // 获取这个章节的图片URL
        final pagesRes = await network.getChapter(chapterId);
        if (pagesRes.error) {
          throw Exception("获取章节 $epName 失败: ${pagesRes.errorMessage}");
        }
        
        // JM 图片下载需要的 headers
        final imageHeaders = {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Referer': 'https://18comic.vip/',
          'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        };
        
        episodes.add(DirectEpisode(
          order: chapterKey,
          name: epName,
          pageUrls: pagesRes.data,
          headers: imageHeaders,
        ));
      }
      
      // 发送到服务器
      final client = ServerClient(serverUrl);
      final jmNetwork = JmNetwork();
      await client.submitDirectDownload(
        comicId: "jm${comic.id}",
        source: "jm",
        title: comic.name,
        author: (comic.author.isNotEmpty ? comic.author.join(', ') : ''),
        cover: comic.cover,
        tags: {"tags": comic.tags},
        description: comic.description ?? "",
        detailUrl: "${jmNetwork.baseUrl}/album?id=${comic.id}",
        episodes: episodes,
      );
      
      Navigator.pop(App.globalContext!);
      App.globalBack();
      showToast(message: "已提交到服务器下载 (共 ${episodes.length} 个章节)".tl);
    } on ServerException catch (e) {
      Navigator.pop(App.globalContext!);
      showToast(message: e.message);
    } catch (e) {
      Navigator.pop(App.globalContext!);
      showToast(message: "添加失败: $e");
    }
  }

  final target = SelectDownloadChapter(
    eps: eps,
    downloadedEps: downloaded,
    onLocalDownload: (selectedEps) {
      downloadManager.addJmDownload(comic, selectedEps);
      App.globalBack();
      showToast(message: "已加入下载队列".tl);
    },
    onServerDownload: appdata.settings[90].isNotEmpty ? downloadToServer : null,
    serverAvailable: appdata.settings[90].isNotEmpty,
    serverStatus: appdata.settings[90].isEmpty ? "未配置服务器".tl : null,
    initialTarget: appdata.settings[90].isNotEmpty
        ? DownloadTarget.server
        : DownloadTarget.local,
  );

  if (UiMode.m1(App.globalContext!)) {
    showModalBottomSheet(
      context: App.globalContext!,
      builder: (context) => target,
    );
  } else {
    showSideBar(
      App.globalContext!,
      target,
      useSurfaceTintColor: true,
    );
  }
}
