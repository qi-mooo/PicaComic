/// 服务器管理页面
/// 
/// 显示服务器连接状态、已下载漫画、下载队列等

import 'package:flutter/material.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/network/server_client.dart';
import 'package:pica_comic/tools/translations.dart';

class ServerPage extends StatefulWidget {
  const ServerPage({Key? key}) : super(key: key);

  @override
  State<ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends State<ServerPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  ServerClient? _serverClient;
  bool _isConnected = false;
  String _serverUrl = '';
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadServerUrl();
  }

  void _loadServerUrl() {
    // 从设置中加载服务器地址
    _serverUrl = appdata.settings[90];
    if (_serverUrl.isNotEmpty) {
      _connectToServer();
    }
  }

  Future<void> _connectToServer() async {
    try {
      _serverClient = ServerClient(_serverUrl);
      final isHealthy = await _serverClient!.checkHealth();
      setState(() {
        _isConnected = isHealthy;
      });
      if (isHealthy) {
        showToast('服务器连接成功'.tl);
      } else {
        showToast('服务器连接失败'.tl);
      }
    } catch (e) {
      setState(() {
        _isConnected = false;
      });
      showToast('服务器连接失败: $e'.tl);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('服务器管理'.tl),
        actions: [
          IconButton(
            icon: Icon(_isConnected ? Icons.cloud_done : Icons.cloud_off),
            onPressed: _showServerSettings,
            tooltip: _isConnected ? '已连接'.tl : '未连接'.tl,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: '已下载'.tl),
            Tab(text: '下载队列'.tl),
            Tab(text: '设置'.tl),
          ],
        ),
      ),
      body: _isConnected
          ? TabBarView(
              controller: _tabController,
              children: [
                _ServerComicsTab(serverClient: _serverClient!),
                _DownloadQueueTab(serverClient: _serverClient!),
                _ServerSettingsTab(
                  serverClient: _serverClient!,
                  onServerUrlChanged: (url) {
                    _serverUrl = url;
                    _connectToServer();
                  },
                ),
              ],
            )
          : _buildNotConnectedView(),
    );
  }

  Widget _buildNotConnectedView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text('未连接到服务器'.tl, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _showServerSettings,
            child: Text('配置服务器'.tl),
          ),
        ],
      ),
    );
  }

  void _showServerSettings() {
    showDialog(
      context: context,
      builder: (context) => _ServerSettingsDialog(
        initialUrl: _serverUrl,
        onSave: (url) {
          setState(() {
            _serverUrl = url;
            appdata.settings[90] = url;
            appdata.writeData();
          });
          _connectToServer();
        },
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}

// ==================== 已下载漫画标签页 ====================

class _ServerComicsTab extends StatefulWidget {
  final ServerClient serverClient;

  const _ServerComicsTab({required this.serverClient});

  @override
  State<_ServerComicsTab> createState() => _ServerComicsTabState();
}

class _ServerComicsTabState extends State<_ServerComicsTab> {
  List<ServerComicDetail> _comics = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadComics();
  }

  Future<void> _loadComics() async {
    setState(() => _isLoading = true);
    try {
      final response = await widget.serverClient.getComics();
      setState(() {
        _comics = response.comics;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      showToast('加载失败: $e'.tl);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_comics.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.book_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text('暂无已下载的漫画'.tl),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadComics,
      child: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 0.65,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: _comics.length,
        itemBuilder: (context, index) {
          final comic = _comics[index];
          return _ComicCard(
            comic: comic,
            serverClient: widget.serverClient,
            onTap: () => _openComic(comic),
            onDelete: () => _deleteComic(comic),
          );
        },
      ),
    );
  }

  void _openComic(ServerComicDetail comic) {
    // TODO: 打开漫画阅读页面
    showToast('打开漫画: ${comic.title}');
  }

  Future<void> _deleteComic(ServerComicDetail comic) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('确认删除'.tl),
        content: Text('确定要删除《${comic.title}》吗？'.tl),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取消'.tl),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('删除'.tl),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await widget.serverClient.deleteComic(comic.id);
        showToast('删除成功'.tl);
        _loadComics();
      } catch (e) {
        showToast('删除失败: $e'.tl);
      }
    }
  }
}

class _ComicCard extends StatelessWidget {
  final ServerComicDetail comic;
  final ServerClient serverClient;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ComicCard({
    required this.comic,
    required this.serverClient,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onDelete,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Image.network(
                serverClient.getComicCoverUrl(comic.id),
                fit: BoxFit.cover,
                width: double.infinity,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Colors.grey[300],
                    child: const Icon(Icons.broken_image, size: 48),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    comic.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    comic.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${comic.epsCount}章',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      Text(
                        comic.formattedSize,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== 下载队列标签页 ====================

class _DownloadQueueTab extends StatefulWidget {
  final ServerClient serverClient;

  const _DownloadQueueTab({required this.serverClient});

  @override
  State<_DownloadQueueTab> createState() => _DownloadQueueTabState();
}

class _DownloadQueueTabState extends State<_DownloadQueueTab> {
  List<ServerDownloadTask> _queue = [];
  bool _isDownloading = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadQueue();
  }

  Future<void> _loadQueue() async {
    setState(() => _isLoading = true);
    try {
      final response = await widget.serverClient.getDownloadQueue();
      setState(() {
        _queue = response.queue;
        _isDownloading = response.isDownloading;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      showToast('加载失败: $e'.tl);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildControlBar(),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _queue.isEmpty
                  ? Center(child: Text('下载队列为空'.tl))
                  : RefreshIndicator(
                      onRefresh: _loadQueue,
                      child: ListView.builder(
                        itemCount: _queue.length,
                        itemBuilder: (context, index) {
                          return _DownloadTaskCard(
                            task: _queue[index],
                            onCancel: () => _cancelTask(_queue[index]),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildControlBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          ElevatedButton.icon(
            onPressed: _isDownloading ? null : _startDownload,
            icon: const Icon(Icons.play_arrow),
            label: Text('开始'.tl),
          ),
          ElevatedButton.icon(
            onPressed: _isDownloading ? _pauseDownload : null,
            icon: const Icon(Icons.pause),
            label: Text('暂停'.tl),
          ),
          ElevatedButton.icon(
            onPressed: _loadQueue,
            icon: const Icon(Icons.refresh),
            label: Text('刷新'.tl),
          ),
        ],
      ),
    );
  }

  Future<void> _startDownload() async {
    try {
      await widget.serverClient.startDownload();
      showToast('已开始下载'.tl);
      await Future.delayed(const Duration(seconds: 1));
      _loadQueue();
    } catch (e) {
      showToast('操作失败: $e'.tl);
    }
  }

  Future<void> _pauseDownload() async {
    try {
      await widget.serverClient.pauseDownload();
      showToast('已暂停下载'.tl);
      await Future.delayed(const Duration(seconds: 1));
      _loadQueue();
    } catch (e) {
      showToast('操作失败: $e'.tl);
    }
  }

  Future<void> _cancelTask(ServerDownloadTask task) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('确认取消'.tl),
        content: Text('确定要取消《${task.title}》的下载吗？'.tl),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('否'.tl),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('是'.tl),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await widget.serverClient.cancelDownload(task.id);
        showToast('已取消'.tl);
        _loadQueue();
      } catch (e) {
        showToast('取消失败: $e'.tl);
      }
    }
  }
}

class _DownloadTaskCard extends StatelessWidget {
  final ServerDownloadTask task;
  final VoidCallback onCancel;

  const _DownloadTaskCard({
    required this.task,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        title: Text(task.title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            LinearProgressIndicator(value: task.progress),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${task.statusText} ${task.progressText}'),
                Text('${task.downloadedPages}/${task.totalPages}'),
              ],
            ),
            if (task.hasError && task.error != null)
              Text(
                task.error!,
                style: const TextStyle(color: Colors.red),
              ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.close),
          onPressed: onCancel,
        ),
      ),
    );
  }
}

// ==================== 服务器设置标签页 ====================

class _ServerSettingsTab extends StatefulWidget {
  final ServerClient serverClient;
  final Function(String) onServerUrlChanged;

  const _ServerSettingsTab({
    required this.serverClient,
    required this.onServerUrlChanged,
  });

  @override
  State<_ServerSettingsTab> createState() => _ServerSettingsTabState();
}

class _ServerSettingsTabState extends State<_ServerSettingsTab> {
  late TextEditingController _emailController;
  late TextEditingController _passwordController;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController();
    _passwordController = TextEditingController();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PicaComic 登录'.tl,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: '邮箱'.tl,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: '密码'.tl,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _login,
                    child: Text('登录'.tl),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      showToast('请输入邮箱和密码'.tl);
      return;
    }

    try {
      final token = await widget.serverClient.picacgLogin(email, password);
      showToast('登录成功'.tl);
    } catch (e) {
      showToast('登录失败: $e'.tl);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}

// ==================== 服务器设置对话框 ====================

class _ServerSettingsDialog extends StatefulWidget {
  final String initialUrl;
  final Function(String) onSave;

  const _ServerSettingsDialog({
    required this.initialUrl,
    required this.onSave,
  });

  @override
  State<_ServerSettingsDialog> createState() => _ServerSettingsDialogState();
}

class _ServerSettingsDialogState extends State<_ServerSettingsDialog> {
  late TextEditingController _urlController;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.initialUrl);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('服务器设置'.tl),
      content: TextField(
        controller: _urlController,
        decoration: InputDecoration(
          labelText: '服务器地址'.tl,
          hintText: 'http://192.168.1.100:8080',
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('取消'.tl),
        ),
        TextButton(
          onPressed: () {
            final url = _urlController.text.trim();
            if (url.isNotEmpty) {
              widget.onSave(url);
              Navigator.pop(context);
            }
          },
          child: Text('保存'.tl),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }
}

void showToast(String message) {
  // TODO: 实现 Toast 显示
  print(message);
}

