import 'dart:io';

import 'package:dio/dio.dart';

class LibraryUploadException implements Exception {
  final String message;
  final bool stopQueue;

  const LibraryUploadException(this.message, {this.stopQueue = false});

  @override
  String toString() => message;
}

Uri privateLibraryBase(String sourceUrl) {
  final uri = Uri.tryParse(sourceUrl);
  if (uri == null ||
      !{'http', 'https'}.contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      !uri.path.endsWith('/source.js')) {
    throw const LibraryUploadException('私人漫画库地址无效，请重新导入漫画源', stopQueue: true);
  }
  return uri.resolve('.');
}

class PrivateLibraryClient {
  final Uri base;
  final String? Function() readToken;
  final Future<bool> Function() refreshLogin;
  final Dio dio;

  PrivateLibraryClient({
    required String sourceUrl,
    required this.readToken,
    required this.refreshLogin,
    Dio? dio,
  })  : base = privateLibraryBase(sourceUrl),
        dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              sendTimeout: const Duration(minutes: 30),
              receiveTimeout: const Duration(minutes: 10),
            ));

  Future<Response<dynamic>> _request(
    String path, {
    required CancelToken cancelToken,
    Future<FormData> Function()? body,
    ProgressCallback? onSendProgress,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      if (cancelToken.isCancelled) throw cancelToken.cancelError!;
      final token = readToken();
      if (token != null && token.isNotEmpty) {
        final response = await dio.requestUri(
          base.resolve(path),
          data: body == null ? null : await body(),
          options: Options(
            method: body == null ? 'GET' : 'POST',
            headers: {'Authorization': 'Bearer $token'},
            followRedirects: false,
            validateStatus: (_) => true,
          ),
          cancelToken: cancelToken,
          onSendProgress: onSendProgress,
        );
        if (response.statusCode != 401) return response;
      }
      if (attempt == 1 || !await refreshLogin()) break;
    }
    throw const LibraryUploadException('登录已失效，请到账号管理重新登录私人漫画库',
        stopQueue: true);
  }

  Map _check(Response<dynamic> response) {
    final status = response.statusCode ?? 0;
    if (status == 403) {
      throw const LibraryUploadException('当前账号没有上传权限，请使用管理员账号',
          stopQueue: true);
    }
    if (status == 404) {
      throw const LibraryUploadException('服务器不支持 App 上传，请更新服务端',
          stopQueue: true);
    }
    if (status < 200 || status >= 300) {
      final body = response.data;
      final detail = body is Map ? body['detail'] : null;
      throw LibraryUploadException(
          detail is String ? detail : '服务器返回错误（$status）');
    }
    if (response.data is! Map) {
      throw const LibraryUploadException('服务器响应格式错误');
    }
    return response.data as Map;
  }

  Future<void> checkAccount(CancelToken cancelToken) async {
    final body =
        _check(await _request('api/auth/me', cancelToken: cancelToken));
    if (body['admin'] != true) {
      throw const LibraryUploadException('当前账号没有上传权限，请使用管理员账号',
          stopQueue: true);
    }
  }

  Future<bool> upload(
    File archive,
    String title,
    CancelToken cancelToken, {
    ProgressCallback? onSendProgress,
  }) async {
    if (await archive.length() > 2 * 1024 * 1024 * 1024) {
      throw const LibraryUploadException('单部漫画 ZIP 超过 2 GB 上传限制');
    }
    final response = await _request(
      'api/uploads',
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      body: () async => FormData.fromMap({
        'titles': title,
        'files': await MultipartFile.fromFile(
          archive.path,
          filename: 'comic.zip',
          contentType: DioMediaType('application', 'zip'),
        ),
      }),
    );
    final result = _check(response);
    if (result['files'] == 1 &&
        result['uploads'] is List &&
        (result['uploads'] as List).length == 1) {
      return true;
    }
    if (result['files'] == 0 &&
        result['skipped'] is List &&
        (result['skipped'] as List).length == 1) {
      return false;
    }
    throw const LibraryUploadException('服务器未确认上传结果，请检查漫画库后重试');
  }

  void close() => dio.close();
}
