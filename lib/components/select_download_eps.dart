import 'package:flutter/material.dart';
import 'package:pica_comic/tools/translations.dart';

enum DownloadTarget { local, server }

class SelectDownloadChapter extends StatefulWidget {
  const SelectDownloadChapter({
    super.key,
    required this.eps,
    required this.onLocalDownload,
    required this.downloadedEps,
    this.onServerDownload,
    this.serverAvailable = false,
    this.serverStatus,
    DownloadTarget? initialTarget,
  }) : initialTarget = initialTarget ?? DownloadTarget.local;

  final List<String> eps;
  final void Function(List<int>) onLocalDownload;
  final Future<void> Function(List<int>)? onServerDownload;
  final List<int> downloadedEps;
  final bool serverAvailable;
  final String? serverStatus;
  final DownloadTarget initialTarget;

  @override
  State<SelectDownloadChapter> createState() => _SelectDownloadChapterState();
}

class _SelectDownloadChapterState extends State<SelectDownloadChapter> {
  List<int> selected = [];
  late DownloadTarget target;

  @override
  void initState() {
    super.initState();
    target = widget.onServerDownload != null
        ? widget.initialTarget
        : DownloadTarget.local;
  }

  Future<void> _handleDownload(List<int> chapters) async {
    if (target == DownloadTarget.server && widget.onServerDownload != null) {
      await widget.onServerDownload!(chapters);
    } else {
      widget.onLocalDownload(chapters);
    }
  }

  Widget _buildDestinationSelector(BuildContext context) {
    if (widget.onServerDownload == null) {
      return const SizedBox.shrink();
    }

    final bool serverEnabled = widget.serverAvailable;
    final theme = Theme.of(context);
    final status = widget.serverStatus;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "下载位置".tl,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: Text("本地设备".tl),
                selected: target == DownloadTarget.local,
                onSelected: (value) {
                  if (value) {
                    setState(() {
                      target = DownloadTarget.local;
                    });
                  }
                },
              ),
              ChoiceChip(
                label: Text("远程服务器".tl),
                selected: target == DownloadTarget.server,
                onSelected: serverEnabled
                    ? (value) {
                        if (value) {
                          setState(() {
                          target = DownloadTarget.server;
                          });
                        }
                      }
                    : null,
              ),
            ],
          ),
          if (status != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                status,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: serverEnabled
                      ? theme.textTheme.bodySmall?.color
                      : theme.colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 16, 0, 16),
            child: Text(
              "下载漫画".tl,
              style: const TextStyle(fontSize: 22),
            ),
          ),
          _buildDestinationSelector(context),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 300,
                childAspectRatio: 4,
              ),
              itemBuilder: (BuildContext context, int i) {
                return Padding(
                  padding: const EdgeInsets.all(4),
                  child: InkWell(
                    borderRadius: const BorderRadius.all(Radius.circular(16)),
                    onTap: widget.downloadedEps.contains(i)
                        ? null
                        : () {
                            setState(() {
                              if (selected.contains(i)) {
                                selected.remove(i);
                              } else {
                                selected.add(i);
                              }
                            });
                          },
                    child: AnimatedContainer(
                      decoration: BoxDecoration(
                        borderRadius:
                            const BorderRadius.all(Radius.circular(16)),
                        color: (selected.contains(i) ||
                                widget.downloadedEps.contains(i))
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                      ),
                      duration: const Duration(milliseconds: 200),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 16,
                          ),
                          Expanded(
                            child: Text(
                              widget.eps[i],
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (selected.contains(i)) const Icon(Icons.done),
                          if (widget.downloadedEps.contains(i))
                            const Icon(Icons.download_done),
                          const SizedBox(
                            width: 16,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
              itemCount: widget.eps.length,
            ),
          ),
          SizedBox(
            height: 50,
            child: Row(
              children: [
                const SizedBox(
                  width: 16,
                ),
                Expanded(
                  child: FilledButton.tonal(
                      onPressed: () async {
                        var res = <int>[];
                        for (int i = 0; i < widget.eps.length; i++) {
                          if (!widget.downloadedEps.contains(i)) {
                            res.add(i);
                          }
                        }
                        await _handleDownload(res);
                      },
                      child: Text("下载全部".tl)),
                ),
                const SizedBox(
                  width: 16,
                ),
                Expanded(
                  child: FilledButton.tonal(
                      onPressed: () async {
                        await _handleDownload(selected);
                      },
                      child: Text("下载选择".tl)),
                ),
                const SizedBox(
                  width: 16,
                ),
              ],
            ),
          ),
          SizedBox(
            height: MediaQuery.of(context).padding.bottom + 4,
          )
        ],
      ),
    );
  }
}
