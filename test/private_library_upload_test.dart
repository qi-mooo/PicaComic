import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/network/private_library_client.dart';
import 'package:pica_comic/utils/private_library_archive.dart';
import 'package:pica_comic/utils/private_library_upload.dart';

class RecordingAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions, List<int>) respond;
  RecordingAdapter(this.respond);

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancelFuture) async {
    final bytes = <int>[];
    if (stream != null) {
      await for (final chunk in stream) {
        bytes.addAll(chunk);
      }
    }
    return respond(options, bytes);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody response(Object body, [int status = 200]) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      'content-type': ['application/json']
    });

ResponseBody uploaded() => response({
      'files': 1,
      'images': 1,
      'uploads': [
        {'title': 'ok'}
      ],
      'skipped': [],
    });

ResponseBody skipped() => response({
      'files': 0,
      'images': 0,
      'uploads': [],
      'skipped': [
        {'filename': 'comic.zip', 'reason': 'exists'}
      ],
    });

void main() {
  late Directory temp;
  late Directory cache;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('pica-upload-test-');
    cache = Directory('${temp.path}/cache')..createSync();
  });
  tearDown(() => temp.deleteSync(recursive: true));

  LibraryArchiveInput comic(String name) {
    final dir = Directory('${temp.path}/$name')..createSync();
    File('${dir.path}/1.jpg').writeAsBytesSync([1, 2, 3]);
    return LibraryArchiveInput(name, dir.path, []);
  }

  PrivateLibraryClient client(RecordingAdapter adapter,
      {String? Function()? readToken, Future<bool> Function()? refreshLogin}) {
    final dio = Dio()..httpClientAdapter = adapter;
    return PrivateLibraryClient(
      sourceUrl: 'http://localhost:8787/library/source.js',
      readToken: readToken ?? () => 'test-token',
      refreshLogin: refreshLogin ?? () async => false,
      dio: dio,
    );
  }

  test('archive keeps cover, chapter numbers, and only downloaded images', () {
    final input = comic('book');
    File('${input.directory}/1.jpg').deleteSync();
    File('${input.directory}/cover.jpg').writeAsBytesSync([4, 5]);
    File('${input.directory}/info.json')
        .writeAsStringSync('{"token":"secret"}');
    for (final chapter in [1, 3, 10]) {
      final directory = Directory('${input.directory}/$chapter')..createSync();
      File('${directory.path}/2.jpg').writeAsBytesSync([chapter, 2]);
      File('${directory.path}/10.jpg').writeAsBytesSync([chapter, 10]);
    }
    final outside = File('${temp.path}/private.jpg')..writeAsBytesSync([99]);
    Link('${input.directory}/link.jpg').createSync(outside.path);
    final output = '${cache.path}/comic.zip';
    createLibraryArchive(
        LibraryArchiveInput(
            'book', input.directory, List.filled(10, 'Repeated / chapter')),
        output);
    final archive =
        ZipDecoder().decodeBytes(File(output).readAsBytesSync(), verify: true);
    expect(archive.map((file) => file.name).toList()..sort(), [
      '00001 - Repeated   chapter/10.jpg',
      '00001 - Repeated   chapter/2.jpg',
      '00003 - Repeated   chapter/10.jpg',
      '00003 - Repeated   chapter/2.jpg',
      '00010 - Repeated   chapter/10.jpg',
      '00010 - Repeated   chapter/2.jpg',
      'cover.jpg',
    ]);
    expect(archive.findFile('cover.jpg')!.content, [4, 5]);
  });

  test('titles respect UTF-8 filename limits and forbidden characters', () {
    expect(privateLibraryTitle(' .a/b:*? '), 'a b');
    final title = privateLibraryTitle(List.filled(200, '漫画😀').join());
    expect(utf8.encode(title).length, lessThanOrEqualTo(240));
    expect(title.runes.length, lessThanOrEqualTo(120));
    expect(() => privateLibraryTitle('...'), throwsFormatException);
  });

  test('base URL preserves deployment prefix and rejects invalid URLs', () {
    expect(
        privateLibraryBase('https://example.org/library/source.js?ignored=1')
            .resolve('api/uploads')
            .toString(),
        'https://example.org/library/api/uploads');
    for (final url in [
      'file:///source.js',
      'https://user:pass@example.org/source.js',
      'https://example.org/unknown'
    ]) {
      expect(() => privateLibraryBase(url),
          throwsA(isA<LibraryUploadException>()));
    }
  });

  test('auth retry sends a fresh multipart body with new token', () async {
    var token = 'old';
    var attempts = 0;
    var logins = 0;
    final archive = File('${cache.path}/input.zip')
      ..writeAsBytesSync([80, 75, 1, 2]);
    final api = client(
        RecordingAdapter((options, bytes) async {
          expect(options.uri.path, '/library/api/uploads');
          expect(options.followRedirects, false);
          final text = utf8.decode(bytes, allowMalformed: true);
          expect(text, contains('name="titles"'));
          expect(text, contains('name="files"; filename="comic.zip"'));
          expect(text, contains('Example'));
          expect(text, contains('PK'));
          expect(options.headers['Authorization'],
              attempts == 0 ? 'Bearer old' : 'Bearer new');
          return attempts++ == 0
              ? response({'detail': 'expired'}, 401)
              : uploaded();
        }),
        readToken: () => token,
        refreshLogin: () async {
          logins++;
          token = 'new';
          return true;
        });
    expect(await api.upload(archive, 'Example', CancelToken()), true);
    expect(attempts, 2);
    expect(logins, 1);
    api.close();
  });

  test('queue continues after duplicates and failures, cleaning each ZIP',
      () async {
    var uploads = 0;
    final api = client(RecordingAdapter((options, bytes) async {
      if (options.method == 'GET') return response({'admin': true});
      expect(cache.listSync().length, 1);
      uploads++;
      if (uploads == 1) return skipped();
      if (uploads == 2) return response({'detail': 'invalid ZIP'}, 400);
      return uploaded();
    }));
    final result = await uploadLibraryQueue(
        [comic('duplicate'), comic('bad'), comic('good')],
        api,
        cache,
        CancelToken());
    expect(result.uploaded, ['good']);
    expect(result.skipped, ['duplicate']);
    expect(result.failed.single, contains('invalid ZIP'));
    expect(result.remaining, 0);
    expect(result.stoppedReason, null);
    expect(cache.listSync(), isEmpty);
    api.close();
  });

  test('packaging failure does not block later comics', () async {
    final api = client(RecordingAdapter((options, bytes) async =>
        options.method == 'GET' ? response({'admin': true}) : uploaded()));
    final result = await uploadLibraryQueue([
      LibraryArchiveInput('missing', '${temp.path}/missing', []),
      comic('good')
    ], api, cache, CancelToken());
    expect(result.uploaded, ['good']);
    expect(result.failed, hasLength(1));
    expect(cache.listSync(), isEmpty);
    api.close();
  });

  test('cancelling while packaging prevents upload and cleans cache', () async {
    var uploads = 0;
    final cancel = CancelToken();
    final api = client(RecordingAdapter((options, bytes) async {
      if (options.method == 'GET') return response({'admin': true});
      uploads++;
      return uploaded();
    }));
    final result = await uploadLibraryQueue(
        [comic('one'), comic('two')], api, cache, cancel,
        onProgress: (index, total, title, phase, progress) {
      cancel.cancel();
    });
    expect(uploads, 0);
    expect(result.remaining, 2);
    expect(result.stoppedReason, contains('已取消'));
    expect(cache.listSync(), isEmpty);
    api.close();
  });

  test('reader account is refused before any ZIP is packaged', () async {
    final api = client(
        RecordingAdapter((options, bytes) async => response({'admin': false})));
    final result =
        await uploadLibraryQueue([comic('one')], api, cache, CancelToken());
    expect(result.stoppedReason, contains('管理员'));
    expect(result.remaining, 1);
    expect(cache.listSync(), isEmpty);
    api.close();
  });

  test('unexpected successful response is not treated as a skipped comic',
      () async {
    final api = client(
        RecordingAdapter((options, bytes) async => response({'ok': true})));
    final archive = File('${cache.path}/input.zip')..writeAsBytesSync([80, 75]);
    await expectLater(api.upload(archive, 'one', CancelToken()),
        throwsA(isA<LibraryUploadException>()));
    api.close();
  });
}
