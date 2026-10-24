import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';

String privateLibraryTitle(String value) {
  var title = value
      .replaceAll(RegExp(r'[\\/<>:"|?*\x00-\x1f\x7f]'), ' ')
      .trim()
      .replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');
  final result = StringBuffer();
  var bytes = 0;
  var characters = 0;
  for (final rune in title.runes) {
    final character = String.fromCharCode(rune);
    final size = utf8.encode(character).length;
    if (characters >= 120 || bytes + size > 240) break;
    result.write(character);
    bytes += size;
    characters++;
  }
  title = result.toString().replaceAll(RegExp(r'[. ]+$'), '');
  if (title.isEmpty) throw const FormatException('漫画名称无效');
  return title;
}

class LibraryArchiveInput {
  final String title;
  final String directory;
  final List<String> chapters;

  const LibraryArchiveInput(this.title, this.directory, this.chapters);
}

/// Runs the synchronous ZIP walk in a fresh isolate without capturing the
/// upload page's callbacks, Dio client, or CancelToken.
Future<void> createLibraryArchiveInIsolate(
    LibraryArchiveInput input, String outputPath) {
  return Isolate.run(() => createLibraryArchive(input, outputPath));
}

void createLibraryArchive(LibraryArchiveInput input, String outputPath) {
  final root = Directory(input.directory);
  if (!root.existsSync() || FileSystemEntity.isLinkSync(root.path)) {
    throw const FormatException('本地漫画目录不存在');
  }
  final encoder = ZipFileEncoder();
  var opened = false;
  var pages = 0;
  var entries = 0;
  var bytes = 0;
  final images =
      RegExp(r'\.(jpg|jpeg|png|webp|gif|bmp|avif)$', caseSensitive: false);
  final covers =
      RegExp(r'^(cover|folder|poster|thumbnail)\.', caseSensitive: false);

  void walk(Directory directory, List<String> parts) {
    for (final entry in directory.listSync(followLinks: false)) {
      final name = entry.path.split(Platform.pathSeparator).last;
      if (name.startsWith('.') || name == '__MACOSX') continue;
      if (entry is Directory) {
        var chapterName = privateLibraryTitle(name);
        final number = int.tryParse(name);
        if (parts.isEmpty && number != null && number > 0) {
          final label = number <= input.chapters.length
              ? input.chapters[number - 1]
              : '第 $number 章';
          chapterName =
              '${number.toString().padLeft(5, '0')} - ${privateLibraryTitle(label)}';
        }
        walk(entry, [...parts, chapterName]);
      } else if (entry is File && images.hasMatch(name)) {
        if (++entries > 50000 ||
            (bytes += entry.lengthSync()) > 20 * 1024 * 1024 * 1024) {
          throw const FormatException('漫画超过服务器的图片数量或解压大小限制');
        }
        if (!covers.hasMatch(name)) pages++;
        encoder.addFile(entry, [...parts, name].join('/'));
      }
    }
  }

  try {
    encoder.create(outputPath, level: 0);
    opened = true;
    walk(root, []);
    if (pages == 0) throw const FormatException('本地漫画没有可上传的正文图片');
  } finally {
    if (opened) encoder.close();
  }
}
