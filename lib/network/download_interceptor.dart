/// 下载拦截器 - 用于将客户端下载拦截并发送到服务器
///
/// 此模块提供通用的下载拦截功能，所有漫画源都可以使用

import 'package:pica_comic/network/server_client.dart';
import 'package:pica_comic/base.dart';

/// 下载拦截器混入类
mixin DownloadInterceptorMixin {
  /// 拦截下载并发送到服务器
  /// 
  /// [links] - 章节URL映射 {章节序号: [图片URL列表]}
  /// [serverUrl] - 服务器地址
  /// [comicId] - 漫画ID
  /// [source] - 漫画源类型 (picacg, jm, eh, etc.)
  /// [title] - 漫画标题
  /// [author] - 作者
  /// [cover] - 封面URL
  /// [tags] - 标签
  /// [description] - 描述
  /// [epNames] - 章节名称列表
  Future<void> interceptAndSendToServer({
    required Map<int, List<String>> links,
    required String serverUrl,
    required String comicId,
    required String source,
    required String title,
    String author = '',
    String cover = '',
    Map<String, List<String>> tags = const {},
    String description = '',
    List<String> epNames = const [],
  }) async {
    final client = ServerClient(serverUrl);
    
    // 构建章节数据
    final episodes = <DirectEpisode>[];
    for (var entry in links.entries) {
      final order = entry.key;
      final epIndex = order - 1; // 转换为 0-based 索引
      final epName = epIndex < epNames.length ? epNames[epIndex] : '第 $order 话';
      
      episodes.add(DirectEpisode(
        order: order,
        name: epName,
        pageUrls: entry.value,
      ));
    }
    
    // 发送到服务器
    await client.submitDirectDownload(
      comicId: comicId,
      source: source,
      title: title,
      author: author,
      cover: cover,
      tags: tags,
      description: description,
      episodes: episodes,
    );
  }
}

/// 服务器下载异常（用于标记已提交到服务器下载，停止本地下载）
class ServerDownloadException implements Exception {
  final String message;
  ServerDownloadException(this.message);

  @override
  String toString() => message;
}

