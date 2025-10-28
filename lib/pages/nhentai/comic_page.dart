import 'package:flutter/material.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/network/nhentai_network/nhentai_main_network.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/network/server_client.dart';
import 'package:pica_comic/pages/category_comics_page.dart';
import 'package:pica_comic/pages/comic_page.dart';
import 'package:pica_comic/pages/reader/comic_reading_page.dart';
import 'package:pica_comic/pages/search_result_page.dart';
import 'package:pica_comic/tools/translations.dart';

import '../../base.dart';
import '../../foundation/app.dart';
import '../../foundation/history.dart';
import '../../foundation/local_favorites.dart';
import '../../network/download.dart';
import 'comments.dart';

class NhentaiComicPage extends BaseComicPage<NhentaiComic> {
  const NhentaiComicPage(String id, {super.key, this.comicCover}) : _id = id;

  final String _id;

  final String? comicCover;

  @override
  String get url => "https://nhentai.net/g/$_id/";

  @override
  String get id => (data?.id) ?? _id;

  @override
  ActionFunc? get searchSimilar => () {
        String? subTitle = data!.subTitle;
        if (subTitle == "") {
          subTitle = null;
        }
        var title = subTitle ?? data!.title;
        title = title
            .replaceAll(RegExp(r"\[.*?\]"), "")
            .replaceAll(RegExp(r"\(.*?\)"), "");
        context.to(
          () => SearchResultPage(
            keyword: "\"$title\"".trim(),
            sourceKey: sourceKey,
          ),
        );
      };

  @override
  void openFavoritePanel() {
    favoriteComic(FavoriteComicWidget(
      havePlatformFavorite: NhentaiNetwork().logged,
      needLoadFolderData: false,
      favoriteOnPlatform: data!.favorite,
      initialFolder: NhentaiNetwork().logged ? "0" : null,
      localFavoriteItem: toLocalFavoriteItem(),
      setFavorite: (b) {
        if (favorite != b) {
          favorite = b;
          update();
        }
      },
      folders: const {"0": "Nhentai"},
      selectFolderCallback: (folder, page) async {
        if (page == 0) {
          var res = await NhentaiNetwork().favoriteComic(id, data!.token);
          if (res.success) {
            data!.favorite = true;
          }
          return res;
        } else {
          LocalFavoritesManager().addComic(
            folder,
            FavoriteItem.fromNhentai(
              NhentaiComicBrief(
                data!.title,
                data!.cover,
                id,
                "Unknown",
                data!.tags["Tags"] ?? const <String>[],
              ),
            ),
          );
          return const Res(true);
        }
      },
      cancelPlatformFavorite: () async {
        var res = await NhentaiNetwork().unfavoriteComic(id, data!.token);
        if(res.success) {
          data!.favorite = false;
        }
        return res;
      },
    ));
  }

  @override
  ActionFunc? get openComments => () {
        showComments(App.globalContext!, id);
      };

  @override
  String? get cover => comicCover ?? data?.cover;

  @override
  void download() {
    final id = "nhentai${data!.id}";
    if (DownloadManager().isExists(id)) {
      showToast(message: "已下载".tl);
      return;
    }
    for (var i in DownloadManager().downloading) {
      if (i.id == id) {
        showToast(message: "下载中".tl);
        return;
      }
    }
    
    // 检查是否配置了服务器
    final serverUrl = appdata.settings[90];
    if (serverUrl.isEmpty) {
      // 本地下载
      DownloadManager().addNhentaiDownload(data!);
      showToast(message: "已加入下载队列".tl);
      return;
    }
    
    // 显示选择对话框
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("选择下载位置".tl),
        content: Text("请选择下载到本地还是服务器".tl),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              DownloadManager().addNhentaiDownload(data!);
              showToast(message: "已加入本地下载队列".tl);
            },
            child: Text("本地设备".tl),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _downloadToServer();
            },
            child: Text("远程服务器".tl),
          ),
        ],
      ),
    );
  }
  
  Future<void> _downloadToServer() async {
    showLoadingDialog(App.globalContext!, allowCancel: false);
    try {
      // 获取图片 URL
      final network = NhentaiNetwork();
      final pagesRes = await network.getImages(data!.id);
      if (pagesRes.error) {
        throw Exception("获取图片列表失败: ${pagesRes.errorMessage}");
      }
      
      // 构建章节数据（NHentai 只有一个章节）
      final episodes = [
        DirectEpisode(
          order: 1,
          name: "第一章".tl,
          pageUrls: pagesRes.data,
        ),
      ];
      
      // 发送到服务器
      final serverUrl = appdata.settings[90];
      final client = ServerClient(serverUrl);
      await client.submitDirectDownload(
        comicId: "nhentai${data!.id}",
        source: "nhentai",
        title: data!.title,
        author: "",
        cover: data!.cover,
        tags: data!.tags,
        description: "",
        episodes: episodes,
      );
      
      Navigator.pop(App.globalContext!);
      showToast(message: "已提交到服务器下载 (${pagesRes.data.length} 张图片)".tl);
    } catch (e) {
      Navigator.pop(App.globalContext!);
      showToast(message: "提交失败: $e");
    }
  }

  @override
  EpsData? get eps => null;

  @override
  String? get introduction => null;

  @override
  bool get enableTranslationToCN => App.locale.languageCode == "zh";

  @override
  Future<Res<NhentaiComic>> loadData() => NhentaiNetwork().getComicInfo(_id);

  @override
  int? get pages => int.tryParse(data?.tags["Pages"]?.elementAtOrNull(0) ?? "");

  @override
  String? get subTitle => data?.subTitle;

  @override
  void read(History? history) async {
    history = await History.createIfNull(history, data!);
    App.globalTo(() => ComicReadingPage.nhentai(
        data!.id,
        data!.title,
        initialPage: history!.page,
      )
    );
  }

  @override
  void onThumbnailTapped(int index) async {
    await History.findOrCreate(data!);
    App.globalTo(
      () => ComicReadingPage.nhentai(
        data!.id,
        data!.title,
        initialPage: index + 1,
      ),
    );
  }

  @override
  Future<bool> loadFavorite(NhentaiComic data) async {
    return data.favorite ||
        (await LocalFavoritesManager().findWithModel(toLocalFavoriteItem())).isNotEmpty;
  }

  @override
  Widget? recommendationBuilder(NhentaiComic data) =>
      SliverGridComics(comics: data.recommendations, sourceKey: sourceKey);

  @override
  String get tag => "Nhentai $_id";

  Map<String, List<String>> generateTags() {
    var tags = Map<String, List<String>>.from(data!.tags);
    tags.remove("Pages");
    tags.removeWhere((key, value) => value.isEmpty);
    return tags;
  }

  @override
  Map<String, List<String>>? get tags => generateTags();

  @override
  void tapOnTag(String tag, String key) {
    if (tag.contains(" | ")) {
      tag = tag.replaceAll(' | ', '-');
    }
    if (tag.contains(" ")) {
      tag = tag.replaceAll(' ', '-');
    }
    String? categoryParam = switch (key) {
      "Parodies" => "/parody/$tag",
      "Character" => "/character/$tag",
      "Tags" => "/tag/$tag",
      "Artists" => "/artist/$tag",
      "Groups" => "/group/$tag",
      "Languages" => "/language/$tag",
      "Categories" => "/category/$tag",
      _ => null
    };

    if (categoryParam == null) {
      context.to(
        () => SearchResultPage(
          keyword: tag,
          sourceKey: sourceKey,
        ),
      );
    } else {
      context.to(
        () => CategoryComicsPage(
          category: tag,
          categoryKey: ComicSource.find(sourceKey)!.categoryData!.key,
          param: categoryParam,
        ),
      );
    }
  }

  @override
  ThumbnailsData? get thumbnailsCreator =>
      ThumbnailsData(data!.thumbnails, (page) async => const Res([]), 1);

  @override
  String? get title => data?.title;

  @override
  Card? get uploaderInfo => null;

  @override
  String get source => "Nhentai";

  @override
  FavoriteItem toLocalFavoriteItem() =>
      FavoriteItem.fromNhentai(NhentaiComicBrief(data!.title, data!.cover, id,
          "Unknown", data!.tags["Tags"] ?? const <String>[]));

  @override
  String get downloadedId => "nhentai${data!.id}";

  @override
  String get sourceKey => 'nhentai';
}
