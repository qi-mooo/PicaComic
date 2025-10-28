/// 服务器漫画浏览页面
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/network/server_client.dart';
import 'package:pica_comic/pages/comic_page.dart';
import 'package:pica_comic/pages/reader/comic_reading_page.dart';
import 'package:pica_comic/tools/translations.dart';

class ServerComicsPage extends StatefulWidget {
  const ServerComicsPage({Key? key}) : super(key: key);

  @override
  State<ServerComicsPage> createState() => _ServerComicsPageState();
}

class _ServerComicsPageState extends State<ServerComicsPage> {
  ServerClient? _client;
  List<ServerComicDetail> _comics = [];
  bool _isLoading = true;
  bool _isConnected = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initClient();
  }

  Future<void> _initClient() async {
    final serverUrl = appdata.settings[90];

    if (serverUrl.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = '请先在设置中配置服务器地址'.tl;
      });
      return;
    }

    try {
      _client = ServerClient(serverUrl);
      final isHealthy = await _client!.checkHealth();

      if (isHealthy) {
        setState(() => _isConnected = true);
        await _loadComics();
      } else {
        setState(() {
          _isLoading = false;
          _error = '无法连接到服务器'.tl;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = '连接失败: $e';
      });
    }
  }

  Future<void> _loadComics() async {
    if (_client == null) return;

    setState(() => _isLoading = true);
    
    try {
      final response = await _client!.getComics();
      setState(() {
        _comics = response.comics;
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = '加载失败: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('服务器漫画'.tl),
        actions: [
          IconButton(
            icon: Icon(_isConnected ? Icons.cloud_done : Icons.cloud_off),
            color: _isConnected ? Colors.green : Colors.grey,
            onPressed: () => _showServerInfo(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isConnected ? _loadComics : null,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _initClient(),
              child: Text('重试'.tl),
            ),
          ],
        ),
      );
    }

    if (_comics.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('服务器上暂无漫画'.tl),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadComics,
      child: CustomScrollView(
        slivers: [
          SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final comic = _comics[index];
                return Padding(
                  padding: const EdgeInsets.all(2),
                  child: ServerComicTile(
                    comic: comic,
                    serverUrl: _client!.serverUrl,
                    onTap: () => _showServerComicDetail(comic),
                    onLongTap: () => _showComicMenu(comic),
                    onSecondaryTap: (details) => _showComicMenu(comic),
                  ),
                );
              },
              childCount: _comics.length,
            ),
            gridDelegate: SliverGridDelegateWithComics(),
          ),
        ],
      ),
    );
  }

  void _showServerInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('服务器信息'.tl),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('地址: ${appdata.settings[90]}'),
            const SizedBox(height: 8),
            Text('状态: ${_isConnected ? '已连接' : '未连接'}'.tl),
            const SizedBox(height: 8),
            Text('漫画数量: ${_comics.length}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('关闭'.tl),
          ),
        ],
      ),
    );
  }

  void _showServerComicDetail(ServerComicDetail comic) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.only(left: 16, right: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            // 标题
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 16, 0, 16),
              child: Text(
                comic.title,
                style: const TextStyle(fontSize: 22),
              ),
            ),
            // 章节列表
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 300,
                  childAspectRatio: 4,
                ),
                itemCount: comic.epsCount,
                itemBuilder: (context, index) {
                  final epOrder = (comic.downloadedEps != null && 
                                   index < comic.downloadedEps!.length)
                      ? comic.downloadedEps![index]
                      : index + 1;
                  final epName = (comic.eps != null && 
                                 index < comic.eps!.length)
                      ? comic.eps![index]
                      : '第 ${epOrder} 话';
                  final isDownloaded = comic.downloadedEps?.contains(epOrder) ?? false;
                  
                  return Padding(
                    padding: const EdgeInsets.all(4),
                    child: InkWell(
                      borderRadius: const BorderRadius.all(Radius.circular(16)),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.all(Radius.circular(16)),
                          color: isDownloaded
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(context).colorScheme.surfaceContainerHighest,
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 16),
                            Expanded(child: Text(epName)),
                            const SizedBox(width: 4),
                            if (isDownloaded) const Icon(Icons.download_done),
                            const SizedBox(width: 16),
                          ],
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _readComic(comic, epOrder);
                      },
                    ),
                  );
                },
              ),
            ),
            // 底部按钮
            SizedBox(
              height: 50,
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _showComicInfoDialog(comic);
                      },
                      child: Text("查看详情".tl),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _readComic(comic, 1);
                      },
                      child: Text("阅读".tl),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  void _readComic(ServerComicDetail comic, int ep) {
    final readingData = ServerReadingData(
      serverUrl: _client!.serverUrl,
      comic: comic,
    );
    
    App.globalTo(() => ComicReadingPage(readingData, 1, ep));
  }

  void _showComicInfoDialog(ServerComicDetail comic) {
    // 如果是 Picacg 漫画且有有效 ID，跳转到在线详情页
    if (comic.type == 'picacg' && comic.id.length == 24) {
      App.globalTo(() => ComicPage(
        sourceKey: 'picacg',
        id: comic.id,
      ));
    } else {
      // 其他情况显示简单信息
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(comic.title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (comic.author.isNotEmpty)
                Text('作者: ${comic.author}'),
              const SizedBox(height: 8),
              Text('类型: ${comic.type}'),
              const SizedBox(height: 8),
              Text('章节: ${comic.epsCount}'),
              const SizedBox(height: 8),
              Text('大小: ${comic.formattedSize}'),
              if (comic.tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  children: comic.tags.map((tag) => Chip(label: Text(tag))).toList(),
                ),
              ],
              if (comic.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(comic.description),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('关闭'.tl),
            ),
          ],
        ),
      );
    }
  }

  void _showComicMenu(ServerComicDetail comic) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete),
              title: Text('删除'.tl),
              onTap: () {
                Navigator.pop(context);
                _deleteComic(comic);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info),
              title: Text('详情'.tl),
              onTap: () {
                Navigator.pop(context);
                _showComicInfoDialog(comic);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteComic(ServerComicDetail comic) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('确认删除'.tl),
        content: Text('确定要从服务器删除《${comic.title}》吗？'.tl),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取消'.tl),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('删除'.tl),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _client!.deleteComic(comic.id);
        showToast(message: '删除成功'.tl);
        _loadComics();
      } catch (e) {
        showToast(message: '删除失败: $e');
      }
    }
  }
}

// 服务器漫画卡片
class ServerComicTile extends ComicTile {
  final ServerComicDetail comic;
  final String serverUrl;
  final VoidCallback onTap;
  final VoidCallback onLongTap;
  final void Function(TapDownDetails) onSecondaryTap;

  @override
  List<String>? get tags => comic.tags.isNotEmpty ? comic.tags : null;

  @override
  String get description => comic.formattedSize;

  @override
  Widget get image => Image.network(
    '$serverUrl/api/comics/${comic.id}/cover',
    fit: BoxFit.cover,
    height: double.infinity,
    errorBuilder: (_, __, ___) => Container(
      color: Colors.grey[300],
      child: const Icon(Icons.book, size: 64),
    ),
  );

  @override
  void onTap_() => onTap();

  @override
  String get subTitle => comic.author.isNotEmpty ? comic.author : '未知作者';

  @override
  String get title => comic.title;

  @override
  void onLongTap_() => onLongTap();

  @override
  void onSecondaryTap_(details) => onSecondaryTap(details);

  @override
  String? get badge => comic.type;

  const ServerComicTile({
    required this.comic,
    required this.serverUrl,
    required this.onTap,
    required this.onLongTap,
    required this.onSecondaryTap,
    super.key,
  });
}
