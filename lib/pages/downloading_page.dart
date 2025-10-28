import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/image_loader/cached_image.dart';
import 'package:pica_comic/network/download.dart';
import 'package:pica_comic/network/eh_network/eh_download_model.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:pica_comic/network/download_model.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/network/server_client.dart';

class DownloadingPage extends StatefulWidget {
  const DownloadingPage({Key? key}) : super(key: key);

  @override
  State<DownloadingPage> createState() => _DownloadingPageState();
}

class _DownloadingPageState extends State<DownloadingPage> with SingleTickerProviderStateMixin {
  var comics = <DownloadingItem>[];
  late TabController _tabController;
  
  // 服务器下载队列
  ServerDownloadQueueResponse? _serverQueue;
  bool _loadingServerQueue = false;
  Timer? _serverQueueTimer;

  @override
  void dispose() {
    downloadManager.removeListener(onChange);
    _tabController.dispose();
    _serverQueueTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1) {
        _loadServerQueue();
      }
    });
    downloadManager.addListener(onChange);
    comics = List.from(downloadManager.downloading);
    
    // 如果服务器URL已配置，加载服务器队列
    if (appdata.settings[90] != null && (appdata.settings[90] as String).isNotEmpty) {
      _loadServerQueue();
    }
  }
  
  Future<void> _loadServerQueue({bool showLoading = true}) async {
    final serverUrl = appdata.settings[90] as String?;
    if (serverUrl == null || serverUrl.isEmpty) {
      return;
    }
    
    // 只在首次加载时显示 loading，避免定时刷新时闪烁
    if (showLoading && mounted) {
      setState(() {
        _loadingServerQueue = true;
      });
    }
    
    try {
      final client = ServerClient(serverUrl);
      final queue = await client.getDownloadQueue();
      
      if (mounted) {
        setState(() {
          _serverQueue = queue;
          _loadingServerQueue = false;
        });
      }
      
      // 启动定时器，每3秒刷新一次
      _serverQueueTimer?.cancel();
      if (queue.isDownloading && mounted) {
        _serverQueueTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
          if (!mounted || _tabController.index != 1) {
            timer.cancel();
            return;
          }
          // 定时刷新时不显示 loading，避免闪烁
          _loadServerQueue(showLoading: false);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingServerQueue = false;
        });
      }
      print('加载服务器下载队列失败: $e');
    }
  }

  void onChange() {
    if(downloadManager.error) {
      setState(() {});
    } else if (downloadManager.downloading.length != comics.length) {
      rebuild();
    } else if (key.currentState != null){
      key.currentState!.updateUi();
    }
  }

  void rebuild() {
    key = GlobalKey<_DownloadingTileState>();
    setState(() {
      comics = List.from(downloadManager.downloading);
    });
  }

  var key = GlobalKey<_DownloadingTileState>();

  @override
  Widget build(BuildContext context) {
    final hasServerUrl = appdata.settings[90] != null && (appdata.settings[90] as String).isNotEmpty;
    
    if (!hasServerUrl) {
      // 如果没有配置服务器，只显示本地下载
      return PopUpWidgetScaffold(
        title: "下载管理器".tl,
        body: _buildLocalDownloadList(),
      );
    }
    
    // 有服务器配置，显示标签页
    return PopUpWidgetScaffold(
      title: "下载管理器".tl,
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: '本地下载'),
              Tab(text: '服务器下载'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildLocalDownloadList(),
                _buildServerDownloadList(),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildLocalDownloadList() {
    var widgets = <Widget>[];
    for (var i in comics) {
      var key = Key(i.id);
      if(i == comics.first) {
        key = this.key;
      }

      widgets.add(_DownloadingTile(
        comic: i,
        cancel: () {
          showConfirmDialog(context, "取消".tl, "取消下载任务?".tl, () {
            setState(() {
              downloadManager.cancel(i.id);
            });
          });
        },
        onComicPositionChange: rebuild,
        key: key,
      ));
    }

    return ListView.builder(
        itemCount: downloadManager.downloading.length + 1,
        padding: EdgeInsets.zero,
        itemBuilder: (context, index) {
          if (index == 0) {
            String downloadStatus;
            if (downloadManager.isDownloading) {
              downloadStatus = " 下载中".tl;
            } else if (downloadManager.downloading.isNotEmpty) {
              downloadStatus = " 已暂停".tl;
            } else {
              downloadStatus = "";
            }

            String downloadTaskText = "@length 项下载任务".tlParams(
                {"length": downloadManager.downloading.length.toString()});

            String displayText = downloadManager.error
                ? "下载出错".tl
                : downloadTaskText + downloadStatus;
            return Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
                height: 48,
                child: Row(
                  children: [
                    const SizedBox(
                      width: 16,
                    ),
                    downloadManager.isDownloading
                        ? const Icon(
                            Icons.downloading,
                            color: Colors.blue,
                          )
                        : const Icon(
                            Icons.pause_circle_outline_outlined,
                            color: Colors.red,
                          ),
                    const SizedBox(
                      width: 12,
                    ),
                    Text(displayText),
                    const Spacer(),
                    if (downloadManager.downloading.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          downloadManager.isDownloading
                              ? downloadManager.pause()
                              : downloadManager.start();
                          setState(() {});
                        },
                        child: downloadManager.isDownloading
                            ? Text("暂停".tl)
                            : (downloadManager.error
                                ? Text("重试".tl)
                                : Text("继续".tl)),
                      ),
                    const SizedBox(
                      width: 16,
                    ),
                  ],
                ));
          } else {
            return widgets[index - 1];
          }
        });
  }
  
  Widget _buildServerDownloadList() {
    if (_loadingServerQueue) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (_serverQueue == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text('无法连接到服务器', style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadServerQueue,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    
    return ListView.builder(
      itemCount: _serverQueue!.queue.length + 1,
      padding: EdgeInsets.zero,
      itemBuilder: (context, index) {
        if (index == 0) {
          // 状态栏
          String downloadStatus;
          if (_serverQueue!.isDownloading) {
            downloadStatus = " 下载中";
          } else if (_serverQueue!.queue.isNotEmpty) {
            downloadStatus = " 已暂停";
          } else {
            downloadStatus = "";
          }
          
          return Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            height: 48,
            child: Row(
              children: [
                const SizedBox(width: 16),
                _serverQueue!.isDownloading
                    ? const Icon(Icons.downloading, color: Colors.blue)
                    : const Icon(Icons.pause_circle_outline_outlined, color: Colors.red),
                const SizedBox(width: 12),
                Text('${_serverQueue!.total} 项下载任务$downloadStatus'),
                const Spacer(),
                if (_serverQueue!.queue.isNotEmpty)
                  TextButton(
                    onPressed: () async {
                      try {
                        final serverUrl = appdata.settings[90] as String;
                        final client = ServerClient(serverUrl);
                        if (_serverQueue!.isDownloading) {
                          await client.pauseDownload();
                        } else {
                          await client.startDownload();
                        }
                        // 操作完成后静默刷新，避免闪烁
                        await _loadServerQueue(showLoading: false);
                      } catch (e) {
                        showToast(message: '操作失败: $e');
                      }
                    },
                    child: Text(_serverQueue!.isDownloading ? '暂停' : '继续'),
                  ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadServerQueue,
                ),
                const SizedBox(width: 8),
              ],
            ),
          );
        }
        
        final task = _serverQueue!.queue[index - 1];
        return _ServerDownloadTaskTile(task: task, onRefresh: _loadServerQueue);
      },
    );
  }
}

class _DownloadingTile extends StatefulWidget {
  const _DownloadingTile({
    required this.comic,
    required this.cancel,
    required this.onComicPositionChange,
    super.key,
  });

  final DownloadingItem comic;

  final void Function() cancel;

  final void Function() onComicPositionChange;

  @override
  State<_DownloadingTile> createState() => _DownloadingTileState();
}

class _DownloadingTileState extends State<_DownloadingTile> {
  late DownloadingItem comic;

  double value = 0.0;
  int downloadPages = 0;
  int? pagesCount;
  int? speed;

  @override
  initState() {
    super.initState();
    comic = widget.comic;
    updateStatistic();
  }

  @override
  void didUpdateWidget(covariant _DownloadingTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.comic != comic) {
      setState(() {
        comic = widget.comic;
      });
    }
  }

  void updateStatistic() {
    if(comic != DownloadManager().downloading.first) {
      return;
    }
    comic = DownloadManager().downloading.first;
    speed = comic.currentSpeed;
    downloadPages = comic.downloadedPages;
    pagesCount = comic.totalPages;
    if (pagesCount == 0) {
      pagesCount = null;
    }
    if (pagesCount != null && pagesCount! > 0) {
      value = downloadPages / pagesCount!;
    }
  }

  void updateUi() {
    setState(() {
      updateStatistic();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: SizedBox(
        height: 114,
        width: double.infinity,
        child: Row(
          children: [
            Container(
              width: 84,
              height: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: context.colorScheme.secondaryContainer,
              ),
              clipBehavior: Clip.antiAlias,
              child: AnimatedImage(
                image: CachedImageProvider(comic.cover,
                    headers: {"User-Agent": webUA}),
                width: 84,
                height: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    comic.title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Spacer(),
                  Text(
                    getProgressText(),
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(value: value),
                  const SizedBox(height: 4),
                ],
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 50,
              child: Column(
                children: [
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: widget.cancel,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.vertical_align_top),
                    onPressed: () {
                      DownloadManager().moveToFirst(comic);
                      widget.onComicPositionChange();
                    },
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _bytesToSize(int bytes) {
    if (bytes < 1024) {
      return "$bytes B";
    } else if (bytes < 1024 * 1024) {
      return "${(bytes / 1024).toStringAsFixed(2)} KB";
    } else if (bytes < 1024 * 1024 * 1024) {
      return "${(bytes / 1024 / 1024).toStringAsFixed(2)} MB";
    } else {
      return "${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB";
    }
  }

  String getProgressText() {
    if (pagesCount == null) {
      if (comic == DownloadManager().downloading.first) {
        return "获取图片信息...".tl;
      } else {
        return "";
      }
    }

    String speedInfo = "";
    if (speed != null) {
      speedInfo = "${_bytesToSize(speed!)}/s";
    }

    String status = "${"已下载".tl}$downloadPages/$pagesCount";

    if (comic is EhDownloadingItem
        && (comic as EhDownloadingItem).downloadType != 0) {
      status = "${_bytesToSize(downloadPages).split(' ').first}"
          "/${_bytesToSize(pagesCount!)}";
    }

    return "$status  $speedInfo";
  }
}

/// 服务器下载任务卡片
class _ServerDownloadTaskTile extends StatelessWidget {
  const _ServerDownloadTaskTile({
    required this.task,
    required this.onRefresh,
  });

  final ServerDownloadTask task;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    String statusText;
    Color statusColor;
    
    switch (task.status) {
      case 'downloading':
        statusText = '下载中';
        statusColor = Colors.blue;
        break;
      case 'pending':
        statusText = '等待中';
        statusColor = Colors.orange;
        break;
      case 'completed':
        statusText = '已完成';
        statusColor = Colors.green;
        break;
      case 'failed':
        statusText = '失败';
        statusColor = Colors.red;
        break;
      case 'paused':
        statusText = '已暂停';
        statusColor = Colors.grey;
        break;
      default:
        statusText = task.status;
        statusColor = Colors.grey;
    }
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: SizedBox(
        height: 114,
        width: double.infinity,
        child: Row(
          children: [
            // 封面
            Container(
              width: 84,
              height: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: context.colorScheme.secondaryContainer,
              ),
              clipBehavior: Clip.antiAlias,
              child: task.cover.isNotEmpty
                  ? Image.network(
                      task.cover,
                      width: 84,
                      height: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.book, size: 48),
                    )
                  : const Icon(Icons.book, size: 48),
            ),
            const SizedBox(width: 8),
            
            // 信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题
                  Text(
                    task.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  
                  // 来源
                  Text(
                    task.type.toUpperCase(),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  
                  const Spacer(),
                  
                  // 状态和进度
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 11,
                            color: statusColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (task.currentEp > 0)
                        Text(
                          '第${task.currentEp}话',
                          style: const TextStyle(fontSize: 12),
                        ),
                    ],
                  ),
                  
                  const SizedBox(height: 4),
                  
                  // 进度条
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(
                        value: task.progress,
                        backgroundColor: Colors.grey[300],
                        valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${task.downloadedPages}/${task.totalPages} (${(task.progress * 100).toStringAsFixed(1)}%)',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                  
                  // 错误信息
                  if (task.error != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '错误: ${task.error}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.red,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            
            const SizedBox(width: 4),
            
            // 操作按钮
            SizedBox(
              width: 50,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (task.status == 'failed')
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      onPressed: () async {
                        // TODO: 实现重试功能
                        showToast(message: '重试功能待实现');
                      },
                      tooltip: '重试',
                    ),
                  if (task.status != 'completed')
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () async {
                        try {
                          final serverUrl = appdata.settings[90] as String;
                          final client = ServerClient(serverUrl);
                          await client.cancelDownload(task.id);
                          onRefresh();
                          showToast(message: '已取消下载任务');
                        } catch (e) {
                          showToast(message: '取消失败: $e');
                        }
                      },
                      tooltip: '取消',
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
