/// PicaComic 服务器客户端
///
/// 用于与 PicaComic 服务器通信，支持远程下载和访问漫画

import 'dart:convert';
import 'package:dio/dio.dart';

class ServerClient {
  final String serverUrl;
  final Dio _dio;

  ServerClient(this.serverUrl)
      : _dio = Dio(BaseOptions(
          baseUrl: serverUrl,
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(minutes: 5),
          headers: {
            'Content-Type': 'application/json',
          },
        ));

  // ==================== 服务器状态 ====================

  /// 检查服务器健康状态
  Future<bool> checkHealth() async {
    try {
      final response = await _dio.get('/health');
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // ==================== 漫画管理 ====================

  /// 获取所有已下载的漫画
  Future<ServerComicsResponse> getComics() async {
    try {
      final response = await _dio.get('/api/comics');
      return ServerComicsResponse.fromJson(response.data);
    } catch (e) {
      throw ServerException('获取漫画列表失败: $e');
    }
  }

  /// 获取漫画详情
  Future<ServerComicDetail> getComicDetail(String id) async {
    try {
      final encodedId = Uri.encodeComponent(id);
      final response = await _dio.get('/api/comics/$encodedId');
      return ServerComicDetail.fromJson(response.data);
    } catch (e) {
      throw ServerException('获取漫画详情失败: $e');
    }
  }

  /// 获取漫画封面 URL
  String getComicCoverUrl(String id) {
    final encodedId = Uri.encodeComponent(id);
    return '$serverUrl/api/comics/$encodedId/cover';
  }

  /// 获取漫画图片 URL
  String getComicPageUrl(String id, int ep, int page) {
    final encodedId = Uri.encodeComponent(id);
    return '$serverUrl/api/comics/$encodedId/$ep/$page';
  }

  /// 获取章节的页面数量
  Future<int> getEpisodePageCount(String id, int ep) async {
    try {
      final encodedId = Uri.encodeComponent(id);
      final response = await _dio.get('/api/comics/$encodedId/$ep/info');
      return response.data['page_count'] as int;
    } catch (e) {
      throw ServerException('获取章节页面数量失败: $e');
    }
  }

  /// 删除漫画
  Future<void> deleteComic(String id) async {
    try {
      final encodedId = Uri.encodeComponent(id);
      await _dio.delete('/api/comics/$encodedId');
    } catch (e) {
      throw ServerException('删除漫画失败: $e');
    }
  }

  // ==================== 下载管理 ====================

  /// 添加下载任务
  Future<ServerDownloadTask> addDownloadTask({
    required String comicId,
    required String source,
    required String title,
    String author = '',
    String cover = '',
    Map<String, List<String>> tags = const {},
    String description = '',
    List<int> eps = const [],
    List<String> epNames = const [],
    Map<String, dynamic> extra = const {},
  }) async {
    try {
      final response = await _dio.post('/api/download', data: {
        'type': source,
        'comic_id': comicId,
        'title': title,
        'author': author,
        'cover': cover,
        'tags': tags,
        'description': description,
        'ep_names': epNames,
        'extra': extra,
        'eps': eps,
      });
      return ServerDownloadTask.fromJson(response.data['task']);
    } catch (e) {
      throw ServerException('添加下载任务失败: $e');
    }
  }

  /// 直接下载模式：客户端已获取URL，直接发送到服务器
  Future<String> submitDirectDownload({
    required String comicId,
    required String source,
    required String title,
    String author = '',
    String cover = '',
    Map<String, List<String>> tags = const {},
    String description = '',
    String? detailUrl,
    required List<DirectEpisode> episodes,
  }) async {
    try {
      final data = {
        'comic_id': comicId,
        'type': source,
        'title': title,
        'author': author,
        'cover': cover,
        'tags': tags,
        'description': description,
        'episodes': episodes.map((e) => e.toJson()).toList(),
      };
      
      // 只在有 detailUrl 时添加
      if (detailUrl != null && detailUrl.isNotEmpty) {
        data['detail_url'] = detailUrl;
      }
      
      final response = await _dio.post('/api/download/direct', data: data);
      return response.data['task_id'];
    } catch (e) {
      throw ServerException('提交直接下载任务失败: $e');
    }
  }

  /// 获取下载队列
  Future<ServerDownloadQueueResponse> getDownloadQueue() async {
    try {
      final response = await _dio.get('/api/download/queue');
      return ServerDownloadQueueResponse.fromJson(response.data);
    } catch (e) {
      throw ServerException('获取下载队列失败: $e');
    }
  }

  /// 开始/继续下载
  Future<void> startDownload() async {
    try {
      await _dio.post('/api/download/start');
    } catch (e) {
      throw ServerException('启动下载失败: $e');
    }
  }

  /// 暂停下载
  Future<void> pauseDownload() async {
    try {
      await _dio.post('/api/download/pause');
    } catch (e) {
      throw ServerException('暂停下载失败: $e');
    }
  }

  /// 取消下载任务
  Future<void> cancelDownload(String taskId) async {
    try {
      await _dio.delete('/api/download/$taskId');
    } catch (e) {
      throw ServerException('取消下载失败: $e');
    }
  }

  // ==================== PicaComic API ====================

  /// PicaComic 登录
  Future<String> picacgLogin(String email, String password) async {
    try {
      final response = await _dio.post('/api/picacg/login', data: {
        'email': email,
        'password': password,
      });
      return response.data['token'];
    } catch (e) {
      throw ServerException('PicaComic 登录失败: $e');
    }
  }

  /// 获取 PicaComic 分类
  Future<dynamic> picacgGetCategories() async {
    try {
      final response = await _dio.get('/api/picacg/categories');
      return response.data['categories'];
    } catch (e) {
      throw ServerException('获取分类失败: $e');
    }
  }

  /// PicaComic 搜索
  Future<dynamic> picacgSearch({
    required String keyword,
    String sort = 'dd',
    int page = 1,
  }) async {
    try {
      final response = await _dio.get('/api/picacg/search', queryParameters: {
        'keyword': keyword,
        'sort': sort,
        'page': page,
      });
      return response.data;
    } catch (e) {
      throw ServerException('搜索失败: $e');
    }
  }

  /// 获取 PicaComic 漫画信息
  Future<dynamic> picacgGetComic(String id) async {
    try {
      final response = await _dio.get('/api/picacg/comic/$id');
      return response.data;
    } catch (e) {
      throw ServerException('获取漫画信息失败: $e');
    }
  }

  /// 获取 PicaComic 漫画章节
  Future<List<String>> picacgGetEps(String id) async {
    try {
      final response = await _dio.get('/api/picacg/comic/$id/eps');
      return List<String>.from(response.data['eps']);
    } catch (e) {
      throw ServerException('获取章节失败: $e');
    }
  }

  // ==================== 直接下载模式 ====================
  // 客户端拦截下载链接并发送到服务器
  // 无需在服务器上登录账号
}

// ==================== 数据模型 ====================

/// 服务器异常
class ServerException implements Exception {
  final String message;
  ServerException(this.message);

  @override
  String toString() => message;
}

/// 漫画列表响应
class ServerComicsResponse {
  final List<ServerComicDetail> comics;
  final int total;

  ServerComicsResponse({
    required this.comics,
    required this.total,
  });

  factory ServerComicsResponse.fromJson(Map<String, dynamic> json) {
    return ServerComicsResponse(
      comics: (json['comics'] as List?)
              ?.map((e) => ServerComicDetail.fromJson(e))
              .toList() ??
          [],
      total: json['total'] ?? 0,
    );
  }
}

/// 服务器漫画详情
class ServerComicDetail {
  final String id;
  final String title;
  final String author;
  final String description;
  final String cover;
  final List<String> tags;
  final List<String> categories;
  final int epsCount;
  final int pagesCount;
  final String type;
  final DateTime time;
  final int size;
  final List<String>? eps;
  final List<int>? downloadedEps;
  final String? directory;
  final String? detailUrl;  // 详情页链接

  ServerComicDetail({
    required this.id,
    required this.title,
    required this.author,
    required this.description,
    required this.cover,
    required this.tags,
    required this.categories,
    required this.epsCount,
    required this.pagesCount,
    required this.type,
    required this.time,
    required this.size,
    this.eps,
    this.downloadedEps,
    this.directory,
    this.detailUrl,  // 详情页链接
  });

  factory ServerComicDetail.fromJson(Map<String, dynamic> json) {
    // 解析时间字段，支持字符串和整数两种格式
    DateTime parseTime(dynamic timeValue) {
      if (timeValue == null) {
        return DateTime.now();
      }
      if (timeValue is String) {
        try {
          return DateTime.parse(timeValue);
        } catch (e) {
          return DateTime.now();
        }
      }
      if (timeValue is int) {
        return DateTime.fromMillisecondsSinceEpoch(timeValue * 1000);
      }
      return DateTime.now();
    }

    return ServerComicDetail(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      author: json['author'] ?? '',
      description: json['description'] ?? '',
      cover: json['cover'] ?? '',
      tags: List<String>.from(json['tags'] ?? []),
      categories: json['categories'] != null 
          ? List<String>.from(json['categories']) 
          : [],
      epsCount: json['eps_count'] ?? 0,
      pagesCount: json['pages_count'] ?? 0,
      type: json['type'] ?? '',
      time: parseTime(json['time']),
      size: json['size'] ?? 0,
      eps: json['eps'] != null ? List<String>.from(json['eps']) : null,
      downloadedEps: json['downloaded_eps'] != null
          ? (json['downloaded_eps'] as List).map((e) {
              // 处理可能是字符串或整数的情况
              if (e is int) return e;
              if (e is String) return int.tryParse(e) ?? 0;
              return 0;
            }).toList()
          : null,
      directory: json['directory'],
      detailUrl: json['detail_url'],  // 详情页链接
    );
  }

  /// 格式化文件大小
  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(2)} KB';
    if (size < 1024 * 1024 * 1024)
      return '${(size / 1024 / 1024).toStringAsFixed(2)} MB';
    return '${(size / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}

/// 下载队列响应
class ServerDownloadQueueResponse {
  final List<ServerDownloadTask> queue;
  final int total;
  final bool isDownloading;

  ServerDownloadQueueResponse({
    required this.queue,
    required this.total,
    required this.isDownloading,
  });

  factory ServerDownloadQueueResponse.fromJson(Map<String, dynamic> json) {
    return ServerDownloadQueueResponse(
      queue: (json['queue'] as List?)
              ?.map((e) => ServerDownloadTask.fromJson(e))
              .toList() ??
          [],
      total: json['total'] ?? 0,
      isDownloading: json['is_downloading'] ?? false,
    );
  }
}

/// 下载任务
class ServerDownloadTask {
  final String id;
  final String comicId;
  final String title;
  final String type;
  final String cover;
  final int totalPages;
  final int downloadedPages;
  final int currentEp;
  final String status;
  final String? error;
  final DateTime createdAt;
  final DateTime updatedAt;

  ServerDownloadTask({
    required this.id,
    required this.comicId,
    required this.title,
    required this.type,
    required this.cover,
    required this.totalPages,
    required this.downloadedPages,
    required this.currentEp,
    required this.status,
    this.error,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ServerDownloadTask.fromJson(Map<String, dynamic> json) {
    return ServerDownloadTask(
      id: json['id'] ?? '',
      comicId: json['comic_id'] ?? '',
      title: json['title'] ?? '',
      type: json['type'] ?? '',
      cover: json['cover'] ?? '',
      totalPages: json['total_pages'] ?? 0,
      downloadedPages: json['downloaded_pages'] ?? 0,
      currentEp: json['current_ep'] ?? 0,
      status: json['status'] ?? 'pending',
      error: json['error'],
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
    );
  }

  /// 下载进度 (0.0 - 1.0)
  double get progress {
    if (totalPages == 0) return 0;
    return downloadedPages / totalPages;
  }

  /// 进度百分比字符串
  String get progressText {
    return '${(progress * 100).toStringAsFixed(1)}%';
  }

  /// 状态文字
  String get statusText {
    switch (status) {
      case 'pending':
        return '等待中';
      case 'downloading':
        return '下载中';
      case 'paused':
        return '已暂停';
      case 'completed':
        return '已完成';
      case 'error':
        return '错误';
      default:
        return status;
    }
  }

  /// 是否正在下载
  bool get isDownloading => status == 'downloading';

  /// 是否已完成
  bool get isCompleted => status == 'completed';

  /// 是否有错误
  bool get hasError => status == 'error';
}

/// 直接下载模式的章节数据
class DirectEpisode {
  final int order;        // 章节序号 (1-based)
  final String name;      // 章节名称
  final List<String> pageUrls; // 图片URL列表
  final Map<String, String>? headers; // HTTP请求头（可选）
  final Map<String, String>? descrambleParams; // 反混淆参数（可选，用于JM等）

  DirectEpisode({
    required this.order,
    required this.name,
    required this.pageUrls,
    this.headers,
    this.descrambleParams,
  });

  Map<String, dynamic> toJson() => {
    'order': order,
    'name': name,
    'page_urls': pageUrls,
    if (headers != null) 'headers': headers,
    if (descrambleParams != null) 'descramble_params': descrambleParams,
  };
}
