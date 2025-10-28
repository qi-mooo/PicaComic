import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:pica_comic/foundation/image_manager.dart';
import 'package:pica_comic/network/download_model.dart';
import 'package:pica_comic/network/server_client.dart';
import 'package:pica_comic/tools/extensions.dart';
import 'package:pica_comic/tools/io_tools.dart';
import '../../base.dart';
import '../download.dart';
import 'methods.dart';
import 'models.dart';
import 'dart:io';

class DownloadedComic extends DownloadedItem {
  ComicItem comicItem;
  List<String> chapters;
  List<int> downloadedChapters;
  double? size;

  DownloadedComic(
      this.comicItem, this.chapters, this.size, this.downloadedChapters);

  @override
  Map<String, dynamic> toJson() => {
        "comicItem": comicItem.toJson(),
        "chapters": chapters,
        "size": size,
        "downloadedChapters": downloadedChapters
      };

  DownloadedComic.fromJson(Map<String, dynamic> json)
      : comicItem = ComicItem.fromJson(json["comicItem"]),
        chapters = List<String>.from(json["chapters"]),
        size = json["size"],
        downloadedChapters = [] {
    if (json["downloadedChapters"] == null) {
      //旧版本中的数据不包含这一项
      for (int i = 0; i < chapters.length; i++) {
        downloadedChapters.add(i);
      }
    } else {
      downloadedChapters = List<int>.from(json["downloadedChapters"]);
    }
  }

  @override
  DownloadType get type => DownloadType.picacg;

  @override
  List<int> get downloadedEps => downloadedChapters;

  @override
  List<String> get eps => chapters.getNoBlankList();

  @override
  String get name => comicItem.title;

  @override
  String get id => comicItem.id;

  @override
  String get subTitle => comicItem.author;

  @override
  double? get comicSize => size;

  @override
  set comicSize(double? value) => size = value;

  @override
  List<String> get tags => comicItem.tags;
}

///picacg的下载进程模型
class PicDownloadingItem extends DownloadingItem {
  PicDownloadingItem(this.comic, this._downloadEps, super.whenFinish,
      super.whenError, super.updateInfo, super.id,
      {super.type = DownloadType.picacg, this.downloadToServer = false, this.serverUrl});

  ///漫画模型
  final ComicItem comic;

  ///章节名称
  var _eps = <String>[];

  ///要下载的章节序号
  final List<int> _downloadEps;

  /// 是否下载到服务器
  final bool downloadToServer;

  /// 服务器 URL（如果下载到服务器）
  final String? serverUrl;

  ///获取各章节名称
  List<String> get eps => _eps;

  @override
  get cover => getImageUrl(comic.thumbUrl);

  @override
  String get title => comic.title;

  @override
  Future<Map<int, List<String>>> getLinks() async {
    var res = <int, List<String>>{};
    _eps = (await network.getEps(id)).data;
    for (var i in _downloadEps) {
      res[i + 1] = (await network.getComicContent(id, i + 1)).data;
    }

    // 🆕 如果选择下载到服务器，发送直接下载请求
    if (downloadToServer && serverUrl != null) {
      await _sendDirectDownloadToServer(res);
    }

    return res;
  }

  /// 发送直接下载请求到服务器
  Future<void> _sendDirectDownloadToServer(Map<int, List<String>> links) async {
    try {
      final client = ServerClient(serverUrl!);
      
      // 构建章节数据
      final episodes = <DirectEpisode>[];
      for (var entry in links.entries) {
        final epIndex = entry.key - 1; // 转换为 0-based 索引
        final epName = epIndex < _eps.length ? _eps[epIndex] : '第 ${entry.key} 话';
        episodes.add(DirectEpisode(
          order: entry.key,
          name: epName,
          pageUrls: entry.value,
        ));
      }

      // 发送到服务器
      await client.submitDirectDownload(
        comicId: id,
        source: 'picacg',
        title: comic.title,
        author: comic.author ?? '',
        cover: getImageUrl(comic.thumbUrl),
        tags: {'category': comic.categories},
        description: comic.description ?? '',
        episodes: episodes,
      );

      // 下载到服务器后，本地不再需要下载，抛出特殊异常停止
      throw ServerDownloadException('已提交到服务器下载');
    } catch (e) {
      if (e is ServerDownloadException) {
        rethrow;
      }
      throw Exception('发送到服务器失败: $e');
    }
  }

  @override
  Stream<DownloadProgress> downloadImage(String link) {
    return ImageManager().getImage(getImageUrl(link));
  }

  @override
  Map<String, dynamic> toMap() => {
        "comic": comic.toJson(),
        "_eps": _eps,
        "_downloadEps": _downloadEps,
        ...super.toBaseMap()
      };

  PicDownloadingItem.fromMap(
      Map<String, dynamic> map,
      DownloadProgressCallback whenFinish,
      DownloadProgressCallback whenError,
      DownloadProgressCallbackAsync updateInfo,
      String id)
      : comic = ComicItem.fromJson(map["comic"]),
        _eps = List<String>.from(map["_eps"]),
        _downloadEps = List<int>.from(map["_downloadEps"]),
        downloadToServer = false,  // 从持久化恢复时，默认为本地下载
        serverUrl = null,           // 从持久化恢复时，服务器URL为空
        super.fromMap(map, whenFinish, whenError, updateInfo);

  @override
  FutureOr<DownloadedItem> toDownloadedItem() async {
    var previous = <int>[];
    if (DownloadManager().isExists(id)) {
      var comic =
          (await DownloadManager().getComicOrNull(id))! as DownloadedComic;
      previous = comic.downloadedEps;
    }
    var downloaded = (_downloadEps + previous).toSet().toList();
    downloaded.sort();
    return DownloadedComic(
      comic,
      eps,
      await getFolderSize(Directory(path)),
      downloaded,
    );
  }
}

/// 服务器下载异常（用于标记已提交到服务器下载）
class ServerDownloadException implements Exception {
  final String message;
  ServerDownloadException(this.message);

  @override
  String toString() => message;
}
