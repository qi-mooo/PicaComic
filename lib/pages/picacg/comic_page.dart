import 'package:flutter/material.dart';
import 'package:pica_comic/comic_source/built_in/picacg.dart';
import 'package:pica_comic/components/select_download_eps.dart';
import 'package:pica_comic/network/download.dart';
import 'package:pica_comic/network/picacg_network/methods.dart';
import 'package:pica_comic/network/server_client.dart';
import 'package:pica_comic/foundation/ui_mode.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/pages/category_comics_page.dart';
import 'package:pica_comic/pages/picacg/comments_page.dart';
import 'package:pica_comic/pages/reader/comic_reading_page.dart';
import 'package:pica_comic/pages/search_result_page.dart';
import 'package:pica_comic/tools/extensions.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:pica_comic/components/components.dart';
import '../../network/picacg_network/picacg_download_model.dart';
import '../comic_page.dart';

class PicacgComicPage extends BaseComicPage<ComicItem> {
  @override
  final String id;

  @override
  final String? cover;

  const PicacgComicPage(this.id, this.cover, {super.key});

  @override
  ActionFunc? get onLike => () {
        network.likeOrUnlikeComic(id);
        data!.isLiked = !data!.isLiked;
        update();
      };

  @override
  String? get likeCount => data?.likes.toString();

  @override
  bool get isLiked => data!.isLiked;

  @override
  void openFavoritePanel() {
    favoriteComic(FavoriteComicWidget(
      havePlatformFavorite: picacg.isLogin,
      needLoadFolderData: false,
      folders: const {"Picacg": "Picacg"},
      initialFolder: data!.isFavourite ? null : "Picacg",
      favoriteOnPlatform: data!.isFavourite,
      localFavoriteItem: toLocalFavoriteItem(),
      setFavorite: (b) {
        if (favorite != b) {
          favorite = b;
          update();
        }
      },
      cancelPlatformFavorite: () async {
        var res = await network.favouriteOrUnfavouriteComic(id);
        if (res) {
          data!.isFavourite = false;
          return const Res(true);
        }
        return Res.error("网络错误".tl);
      },
      selectFolderCallback: (name, p) async {
        if (p == 0) {
          var res = await network.favouriteOrUnfavouriteComic(id);
          if (res) {
            data!.isFavourite = true;
            update();
            return const Res(true);
          } else {
            return Res.error("网络错误".tl);
          }
        } else {
          LocalFavoritesManager().addComic(name, toLocalFavoriteItem());
          return const Res(true);
        }
      },
    ));
  }

  @override
  ActionFunc? get openComments => () => showComments(App.globalContext!, id);

  @override
  String? get commentsCount => data!.comments.toString();

  @override
  void download() {
    _downloadComic(data!, App.globalContext!, data!.eps);
  }

  @override
  EpsData? get eps {
    return EpsData(
      data!.eps,
      (i) async {
        await History.findOrCreate(data!);
        App.globalTo(
            () => ComicReadingPage.picacg(id, i + 1, data!.eps, data!.title));
      },
    );
  }

  @override
  String? get introduction => data?.description;

  @override
  Future<Res<ComicItem>> loadData() => network.getComicInfo(id);

  @override
  int? get pages => data?.pagesCount;

  @override
  void read(History? history) async {
    history = await History.createIfNull(history, data!);
    App.globalTo(
      () => ComicReadingPage.picacg(
        id,
        history!.ep,
        data!.eps,
        data!.title,
        initialPage: history.page,
      ),
    );
  }

  @override
  Widget recommendationBuilder(data) =>
      SliverGridComics(comics: data.recommendation, sourceKey: sourceKey);

  @override
  String get tag => "Picacg Comic Page $id";

  @override
  Map<String, List<String>>? get tags => {
        "作者".tl: data!.author.toList(),
        "汉化".tl: data!.chineseTeam.toList(),
        "分类".tl: data!.categories,
        "标签".tl: data!.tags
      };

  @override
  void tapOnTag(String tag, String key) {
    if (data!.categories.contains(tag)) {
      context.to(
        () => CategoryComicsPage(
          category: tag,
          categoryKey: "picacg",
        ),
      );
    } else if (data!.author == tag) {
      context.to(
        () => CategoryComicsPage(
          category: tag,
          param: "a",
          categoryKey: "picacg",
        ),
      );
    } else {
      context.to(
        () => SearchResultPage(
          keyword: tag,
          sourceKey: sourceKey,
        ),
      );
    }
  }

  @override
  ThumbnailsData? get thumbnailsCreator => null;

  @override
  String? get title => data?.title;

  @override
  Future<bool> loadFavorite(ComicItem data) async {
    return data.isFavourite ||
        (await LocalFavoritesManager().findWithModel(toLocalFavoriteItem()))
            .isNotEmpty;
  }

  @override
  Card? get uploaderInfo => Card(
        elevation: 0,
        color: context.colorScheme.inversePrimary,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              Expanded(
                flex: 0,
                child: Avatar(
                  size: 50,
                  avatarUrl: data!.creator.avatarUrl,
                  frame: data!.creator.frameUrl,
                  couldBeShown: true,
                  name: data!.creator.name,
                  slogan: data!.creator.slogan,
                  level: data!.creator.level,
                ),
              ),
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(15, 10, 0, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data!.creator.name,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      Text(
                          "${data!.time.substring(0, 10)} ${data!.time.substring(11, 19)}更新")
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  @override
  String get source => "Picacg";

  @override
  FavoriteItem toLocalFavoriteItem() => FavoriteItem(
        target: id,
        name: data!.title,
        coverPath: data!.thumbUrl,
        author: data!.author,
        type: FavoriteType.picacg,
        tags: data!.tags,
      );

  @override
  String get downloadedId => id;

  @override
  String get sourceKey => "picacg";
}

void _downloadComic(
    ComicItem comic, BuildContext context, List<String> eps) async {
  for (var i in downloadManager.downloading) {
    if (i.id == comic.id) {
      showToast(message: "下载中".tl);
      return;
    }
  }
  var downloaded = <int>[];
  if (DownloadManager().isExists(comic.id)) {
    var downloadedComic =
        (await DownloadManager().getComicOrNull(comic.id))! as DownloadedComic;
    downloaded.addAll(downloadedComic.downloadedEps);
  }
  var serverUrl = appdata.settings[90];
  var content = SelectDownloadChapter(
    eps: eps,
    downloadedEps: downloaded,
    onLocalDownload: (selectedEps) {
      downloadManager.addPicDownload(comic, selectedEps);
      App.globalBack();
      showToast(message: "已加入下载队列".tl);
    },
    onServerDownload: serverUrl.isEmpty
        ? null
        : (selectedEps) async {
            final sanitized = selectedEps
                .where((idx) => idx >= 0 && idx < eps.length)
                .toList();
            if (sanitized.isEmpty) {
              showToast(message: "请选择章节".tl);
              return;
            }
            showLoadingDialog(App.globalContext!, allowCancel: false);
            try {
              // 🆕 使用直接下载模式：拦截客户端获取的URL并发送到服务器
              final network = PicacgNetwork();
              final allEps = (await network.getEps(comic.id)).data;
              
              final episodes = <DirectEpisode>[];
              for (var idx in sanitized) {
                final epOrder = idx + 1;
                final epName = idx < allEps.length ? allEps[idx] : '第 $epOrder 话';
                
                // 获取这个章节的图片URL
                final pagesRes = await network.getComicContent(comic.id, epOrder);
                if (pagesRes.error) {
                  throw Exception("获取章节 $epName 失败: ${pagesRes.errorMessage}");
                }
                
                episodes.add(DirectEpisode(
                  order: epOrder,
                  name: epName,
                  pageUrls: pagesRes.data,
                ));
              }
              
              // 发送到服务器
              final client = ServerClient(serverUrl);
              await client.submitDirectDownload(
                comicId: comic.id,
                source: "picacg",
                title: comic.title,
                author: comic.author,
                cover: getImageUrl(comic.thumbUrl),  // 使用 getImageUrl 处理封面URL
                tags: {
                  "category": comic.categories,  // 分类
                  "tags": comic.tags,           // 标签
                },
                description: comic.description,
                detailUrl: "https://www.picacomic.com/comic/${comic.id}",
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
          },
    serverAvailable: serverUrl.isNotEmpty,
    serverStatus: serverUrl.isEmpty ? "未配置服务器".tl : null,
    initialTarget:
        serverUrl.isNotEmpty ? DownloadTarget.server : DownloadTarget.local,
  );
  if (UiMode.m1(App.globalContext!)) {
    showModalBottomSheet(
      context: App.globalContext!,
      builder: (context) => content,
    );
  } else {
    showSideBar(
      App.globalContext!,
      content,
      useSurfaceTintColor: true,
    );
  }
}
