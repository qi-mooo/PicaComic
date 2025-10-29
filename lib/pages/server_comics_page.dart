/// 服务器漫画浏览页面
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/network/server_client.dart';
import 'package:pica_comic/pages/comic_page.dart';
import 'package:pica_comic/pages/reader/comic_reading_page.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:pica_comic/pages/jm/jm_comic_page.dart';
import 'package:pica_comic/pages/picacg/comic_page.dart';
import 'package:pica_comic/pages/nhentai/comic_page.dart';
import 'package:pica_comic/pages/htmanga/ht_comic_page.dart';

class ServerComicsPage extends StatefulWidget {
  const ServerComicsPage({Key? key}) : super(key: key);

  @override
  State<ServerComicsPage> createState() => _ServerComicsPageState();
}

class _ServerComicsPageState extends State<ServerComicsPage> {
  ServerClient? _client;
  List<ServerComicDetail> _comics = [];
  List<ServerComicDetail> _baseComics = [];
  bool _isLoading = true;
  bool _isConnected = false;
  String? _error;
  
  // 搜索相关
  bool _searchMode = false;
  String _keyword = "";
  String _keyword_ = "";
  
  // 排序相关 (0: 时间, 1: 名称, 2: 大小)
  int _sortMode = 0;
  bool _sortReverse = false;

  @override
  void initState() {
    super.initState();
    _loadSortSettings();
    _initClient();
  }
  
  void _loadSortSettings() {
    // 从设置中加载排序模式 (使用 settings[92] 存储服务器漫画排序)
    if (appdata.settings[92].isNotEmpty) {
      final parts = appdata.settings[92].split(',');
      if (parts.isNotEmpty) _sortMode = int.tryParse(parts[0]) ?? 0;
      if (parts.length > 1) _sortReverse = parts[1] == '1';
    }
  }
  
  void _saveSortSettings() {
    appdata.settings[92] = '$_sortMode,${_sortReverse ? '1' : '0'}';
    appdata.updateSettings();
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
      _baseComics = response.comics;
      _applyFiltersAndSort();
      setState(() {
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
  
  void _applyFiltersAndSort() {
    // 1. 应用搜索过滤
    if (_keyword.isEmpty) {
      _comics = List.from(_baseComics);
    } else {
      _comics = _baseComics.where((comic) {
        return comic.title.toLowerCase().contains(_keyword.toLowerCase()) ||
               comic.author.toLowerCase().contains(_keyword.toLowerCase());
      }).toList();
    }
    
    // 2. 应用排序
    _comics.sort((a, b) {
      int result;
      switch (_sortMode) {
        case 0: // 时间
          result = a.time.compareTo(b.time);
          break;
        case 1: // 名称
          result = a.title.compareTo(b.title);
          break;
        case 2: // 大小
          result = a.size.compareTo(b.size);
          break;
        default:
          result = 0;
      }
      return _sortReverse ? -result : result;
    });
  }
  
  void _performSearch() {
    if (_keyword == _keyword_) return;
    _keyword_ = _keyword;
    setState(() {
      _applyFiltersAndSort();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _searchMode ? _buildSearchField() : Text('服务器漫画'.tl),
        actions: _buildActions(),
      ),
      body: _buildBody(),
    );
  }
  
  Widget _buildSearchField() {
    return TextField(
      autofocus: true,
      decoration: InputDecoration(
        border: InputBorder.none,
        hintText: "搜索".tl,
      ),
      onChanged: (s) {
        _keyword = s.toLowerCase();
        _performSearch();
      },
    );
  }
  
  List<Widget> _buildActions() {
    if (_searchMode) {
      return [
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            setState(() {
              _searchMode = false;
              _keyword = "";
              _keyword_ = "";
              _applyFiltersAndSort();
            });
          },
        ),
      ];
    }
    
    return [
      Tooltip(
        message: "排序".tl,
        child: IconButton(
          icon: const Icon(Icons.sort),
          onPressed: _showSortDialog,
        ),
      ),
      Tooltip(
        message: "搜索".tl,
        child: IconButton(
          icon: const Icon(Icons.search),
          onPressed: () {
            setState(() {
              _searchMode = true;
            });
          },
        ),
      ),
      IconButton(
        icon: Icon(_isConnected ? Icons.cloud_done : Icons.cloud_off),
        color: _isConnected ? Colors.green : Colors.grey,
        onPressed: () => _showServerInfo(),
      ),
      IconButton(
        icon: const Icon(Icons.refresh),
        onPressed: _isConnected ? _loadComics : null,
      ),
    ];
  }
  
  Future<void> _showSortDialog() async {
    bool changed = false;
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => SimpleDialog(
          title: Text("漫画排序模式".tl),
          children: [
            SizedBox(
              width: 400,
              child: Column(
                children: [
                  ListTile(
                    title: Text("漫画排序模式".tl),
                    trailing: Select(
                      initialValue: _sortMode,
                      onChange: (i) {
                        setDialogState(() {
                          setState(() {
                            _sortMode = i;
                            _saveSortSettings();
                            _applyFiltersAndSort();
                            changed = true;
                          });
                        });
                      },
                      values: ["时间".tl, "名称".tl, "大小".tl],
                      width: 156,
                    ),
                  ),
                  ListTile(
                    title: Text("倒序".tl),
                    trailing: Switch(
                      value: _sortReverse,
                      onChanged: (b) {
                        setDialogState(() {
                          setState(() {
                            _sortReverse = b;
                            _saveSortSettings();
                            _applyFiltersAndSort();
                            changed = true;
                          });
                        });
                      },
                    ),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
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
                        // 如果有在线详情且支持在客户端内打开，则打开在线详情页
                        if (comic.detailUrl != null && 
                            comic.detailUrl!.isNotEmpty && 
                            _canOpenComicInApp(comic.type)) {
                          _openComicDetailPage(comic);
                        } else {
                          _showComicInfoDialog(comic);
                        }
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

  Future<void> _readComic(ServerComicDetail comic, int ep) async {
    final readingData = ServerReadingData(
      serverUrl: _client!.serverUrl,
      comic: comic,
    );
    
    // 尝试从历史记录中获取或创建阅读进度
    var history = HistoryManager().findSync(comic.id);
    if (history == null) {
      // 如果历史记录不存在，创建一个新的
      history = History(
        HistoryType(99), // 使用特殊类型表示服务器漫画
        DateTime.now(),
        comic.title,
        '',
        _client!.getComicCoverUrl(comic.id),
        0,
        0,
        comic.id,
        {},
        null,
      );
      await HistoryManager().addHistory(history);
    }
    
    int initialPage = 1;
    int initialEp = ep;
    
    if (history.ep > 0) {
      // 如果有阅读位置，使用历史记录中的位置
      initialEp = history.ep;
      initialPage = history.page;
    }
    
    App.globalTo(() => ComicReadingPage(readingData, initialPage, initialEp));
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
    // 如果有在线详情，根据漫画源类型判断是否可以在客户端内打开
    final hasOnlineDetail = comic.detailUrl != null && comic.detailUrl!.isNotEmpty;
    final canOpenInApp = _canOpenComicInApp(comic.type);
    
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasOnlineDetail && canOpenInApp)
              ListTile(
                leading: const Icon(Icons.book),
                title: Text('查看在线详情'.tl),
                onTap: () {
                  Navigator.pop(context);
                  _openComicDetailPage(comic);
                },
              ),
            if (!hasOnlineDetail || !canOpenInApp)
              ListTile(
                leading: const Icon(Icons.info),
                title: Text('详情'.tl),
                onTap: () {
                  Navigator.pop(context);
                  _showComicInfoDialog(comic);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: Text('删除'.tl),
              onTap: () {
                Navigator.pop(context);
                _deleteComic(comic);
              },
            ),
          ],
        ),
      ),
    );
  }

  // 检查是否可以在客户端内打开
  bool _canOpenComicInApp(String type) {
    return ['jm', 'picacg', 'nhentai', 'htmanga'].contains(type);
  }

  // 在客户端内打开漫画详情页
  void _openComicDetailPage(ServerComicDetail comic) {
    try {
      String actualId = comic.id;
      
      // 从 ID 中提取实际的漫画 ID
      if (comic.type == 'jm' && actualId.startsWith('jm')) {
        actualId = actualId.substring(2); // 移除 'jm' 前缀
      } else if (comic.type == 'nhentai' && actualId.startsWith('nhentai')) {
        actualId = actualId.substring(7); // 移除 'nhentai' 前缀
      } else if (comic.type == 'htmanga' && actualId.startsWith('Ht')) {
        actualId = actualId.substring(2); // 移除 'Ht' 前缀
      } else if (comic.type == 'hitomi' && actualId.startsWith('hitomi')) {
        actualId = actualId.substring(6); // 移除 'hitomi' 前缀
      }
      
      // 根据类型跳转到对应的详情页
      switch (comic.type) {
        case 'jm':
          context.to(() => JmComicPage(actualId));
          break;
        case 'picacg':
          context.to(() => PicacgComicPage(actualId, null));
          break;
        case 'nhentai':
          context.to(() => NhentaiComicPage(actualId));
          break;
        case 'htmanga':
          context.to(() => HtComicPage(actualId));
          break;
        default:
          showToast(message: '不支持的漫画源'.tl);
      }
    } catch (e) {
      showToast(message: '打开详情页失败: $e');
    }
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
