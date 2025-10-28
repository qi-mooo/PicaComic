/// 导出已下载漫画到服务器
///
/// 此模块提供将本地已下载的漫画导出到服务器的功能

import 'dart:io';
import 'package:pica_comic/network/server_client.dart';
import 'package:pica_comic/network/download.dart';
import 'package:pica_comic/network/download_model.dart';
import 'package:path/path.dart' as path;

class ComicExporter {
  final String serverUrl;
  final ServerClient _client;

  ComicExporter(this.serverUrl) : _client = ServerClient(serverUrl);

  /// 导出单个已下载漫画到服务器
  /// 
  /// [comic] - 已下载的漫画
  /// [onProgress] - 进度回调 (当前, 总数, 状态描述)
  Future<void> exportComic(
    DownloadedItem comic, {
    Function(int current, int total, String status)? onProgress,
  }) async {
    final downloadPath = comic.path;
    final comicDir = Directory(downloadPath);
    
    if (!await comicDir.exists()) {
      throw Exception('漫画目录不存在: $downloadPath');
    }

    // 1. 收集所有章节的图片
    final episodes = <DirectEpisode>[];
    final downloadedEps = comic.downloadedEps;
    final allEps = comic.eps;

    for (var epIndex in downloadedEps) {
      final epOrder = epIndex + 1; // 转换为 1-based
      final epName = epIndex < allEps.length ? allEps[epIndex] : '第 $epOrder 话';
      final epDir = Directory(path.join(downloadPath, epOrder.toString()));

      if (!await epDir.exists()) {
        continue;
      }

      // 读取章节中的所有图片文件
      final pageFiles = await epDir
          .list()
          .where((entity) => entity is File)
          .cast<File>()
          .toList();
      
      pageFiles.sort((a, b) => a.path.compareTo(b.path));

      if (pageFiles.isEmpty) {
        continue;
      }

      onProgress?.call(episodes.length, downloadedEps.length, '正在处理章节: $epName');

      // 🔄 将本地文件路径转换为可访问的URL
      // 注意：这里我们需要先上传文件，或者创建本地文件服务器
      // 为简化，我们使用占位符，实际应用中需要上传文件
      final pageUrls = pageFiles.map((f) => 'file://${f.path}').toList();

      episodes.add(DirectEpisode(
        order: epOrder,
        name: epName,
        pageUrls: pageUrls,
      ));
    }

    if (episodes.isEmpty) {
      throw Exception('没有找到可导出的章节');
    }

    // 2. 提交到服务器
    onProgress?.call(episodes.length, downloadedEps.length, '正在上传到服务器...');

    await _client.submitDirectDownload(
      comicId: comic.id,
      source: _getSourceType(comic.type),
      title: comic.name,
      author: comic.subTitle,
      cover: '', // 封面需要从本地读取
      tags: {'tags': comic.tags},
      description: '',
      episodes: episodes,
    );

    onProgress?.call(episodes.length, downloadedEps.length, '导出完成');
  }

  /// 批量导出多个漫画
  Future<void> exportMultipleComics(
    List<DownloadedItem> comics, {
    Function(int current, int total, String comicName, String status)? onProgress,
  }) async {
    for (var i = 0; i < comics.length; i++) {
      final comic = comics[i];
      try {
        await exportComic(
          comic,
          onProgress: (cur, tot, status) {
            onProgress?.call(i + 1, comics.length, comic.name, status);
          },
        );
      } catch (e) {
        onProgress?.call(i + 1, comics.length, comic.name, '失败: $e');
      }
    }
  }

  String _getSourceType(DownloadType type) {
    switch (type) {
      case DownloadType.picacg:
        return 'picacg';
      case DownloadType.jm:
        return 'jm';
      case DownloadType.ehentai:
        return 'eh';
      case DownloadType.hitomi:
        return 'hitomi';
      case DownloadType.htmanga:
        return 'htmanga';
      case DownloadType.nhentai:
        return 'nhentai';
      default:
        return 'other';
    }
  }
}

