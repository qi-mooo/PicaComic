import 'dart:io';

import 'package:dio/dio.dart';
import 'package:pica_comic/network/private_library_client.dart';
import 'package:pica_comic/utils/private_library_archive.dart';

class LibraryUploadResult {
  final uploaded = <String>[];
  final skipped = <String>[];
  final failed = <String>[];
  int remaining = 0;
  String? stoppedReason;
}

typedef LibraryUploadProgress = void Function(
    int index, int total, String title, String phase, double? progress);

Future<LibraryUploadResult> uploadLibraryQueue(
  List<LibraryArchiveInput> comics,
  PrivateLibraryClient client,
  Directory cache,
  CancelToken cancelToken, {
  LibraryUploadProgress? onProgress,
}) async {
  final result = LibraryUploadResult()..remaining = comics.length;
  try {
    await client.checkAccount(cancelToken);
    for (var i = 0; i < comics.length; i++) {
      if (cancelToken.isCancelled) throw cancelToken.cancelError!;
      final comic = comics[i];
      Directory? temp;
      try {
        final title = privateLibraryTitle(comic.title);
        onProgress?.call(i + 1, comics.length, title, '正在打包', null);
        temp = await cache.createTemp('private-library-');
        final archivePath = '${temp.path}/comic.zip';
        await createLibraryArchiveInIsolate(comic, archivePath);
        if (cancelToken.isCancelled) throw cancelToken.cancelError!;
        onProgress?.call(i + 1, comics.length, title, '正在上传', 0);
        final uploaded = await client.upload(
          File(archivePath),
          title,
          cancelToken,
          onSendProgress: (sent, total) => onProgress?.call(
              i + 1,
              comics.length,
              title,
              sent == total ? '正在入库' : '正在上传',
              total > 0 && sent < total ? sent / total : null),
        );
        (uploaded ? result.uploaded : result.skipped).add(comic.title);
      } catch (error) {
        if (cancelToken.isCancelled) rethrow;
        if (error is LibraryUploadException && error.stopQueue) rethrow;
        final reason = error is DioException
            ? '网络异常，请检查服务器连接后重试'
            : error is FormatException
                ? error.message
                : error.toString();
        result.failed.add('${comic.title}：$reason');
      } finally {
        if (temp != null && await temp.exists()) {
          await temp.delete(recursive: true);
        }
      }
      result.remaining--;
    }
  } catch (error) {
    result.stoppedReason = cancelToken.isCancelled
        ? '已取消；正在入库的漫画可能已保存，重试时会自动跳过重名漫画'
        : error is DioException
            ? '无法连接服务器，请检查网络'
            : error.toString();
  }
  return result;
}
