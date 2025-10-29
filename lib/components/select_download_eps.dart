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
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "下载位置".tl,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildTargetButton(
                  context: context,
                  label: "本地设备".tl,
                  icon: Icons.phone_android,
                  isSelected: target == DownloadTarget.local,
                  enabled: true,
                  onTap: () {
                    setState(() {
                      target = DownloadTarget.local;
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTargetButton(
                  context: context,
                  label: "远程服务器".tl,
                  icon: Icons.cloud_upload,
                  isSelected: target == DownloadTarget.server,
                  enabled: serverEnabled,
                  onTap: serverEnabled
                      ? () {
                          setState(() {
                            target = DownloadTarget.server;
                          });
                        }
                      : null,
                ),
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
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTargetButton({
    required BuildContext context,
    required String label,
    required IconData icon,
    required bool isSelected,
    required bool enabled,
    required VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final color = isSelected
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    final textColor = isSelected
        ? theme.colorScheme.onPrimaryContainer
        : enabled
            ? theme.colorScheme.onSurface
            : theme.colorScheme.onSurface.withOpacity(0.38);

    return Material(
      color: color,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: isSelected
                ? Border.all(
                    color: theme.colorScheme.primary.withOpacity(0.5),
                    width: 2,
                  )
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: textColor,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: textColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.check_circle,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 20, 0, 16),
            child: Text(
              "下载漫画".tl,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          _buildDestinationSelector(context),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 300,
                childAspectRatio: 4,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemBuilder: (BuildContext context, int i) {
                final isDownloaded = widget.downloadedEps.contains(i);
                final isSelected = selected.contains(i);
                
                return InkWell(
                  borderRadius: const BorderRadius.all(Radius.circular(12)),
                  onTap: isDownloaded
                      ? null
                      : () {
                          setState(() {
                            if (isSelected) {
                              selected.remove(i);
                            } else {
                              selected.add(i);
                            }
                          });
                        },
                  child: AnimatedContainer(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.all(Radius.circular(12)),
                      color: isDownloaded
                          ? theme.colorScheme.surfaceContainerHighest
                          : isSelected
                              ? theme.colorScheme.primaryContainer
                              : theme.colorScheme.surfaceContainerHighest,
                      border: isSelected && !isDownloaded
                          ? Border.all(
                              color: theme.colorScheme.primary.withOpacity(0.5),
                              width: 2,
                            )
                          : null,
                    ),
                    duration: const Duration(milliseconds: 200),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.eps[i],
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                color: isDownloaded
                                    ? theme.colorScheme.onSurface.withOpacity(0.6)
                                    : theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (isSelected && !isDownloaded)
                            Icon(
                              Icons.check_circle,
                              size: 20,
                              color: theme.colorScheme.primary,
                            ),
                          if (isDownloaded)
                            Icon(
                              Icons.download_done,
                              size: 20,
                              color: theme.colorScheme.primary.withOpacity(0.6),
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
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () async {
                    var res = <int>[];
                    for (int i = 0; i < widget.eps.length; i++) {
                      if (!widget.downloadedEps.contains(i)) {
                        res.add(i);
                      }
                    }
                    await _handleDownload(res);
                  },
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    "下载全部".tl,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonal(
                  onPressed: () async {
                    await _handleDownload(selected);
                  },
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    "下载选择".tl,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(
            height: MediaQuery.of(context).padding.bottom + 12,
          )
        ],
      ),
    );
  }
}
