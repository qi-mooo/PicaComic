import 'package:flutter/material.dart';
import 'package:pica_comic/network/eh_network/eh_main_network.dart';
import 'package:pica_comic/network/jm_network/jm_image.dart';
import 'package:pica_comic/network/picacg_network/models.dart';
import 'package:pica_comic/network/server_client.dart';
import 'package:pica_comic/pages/comic_page.dart';
import 'package:pica_comic/pages/reader/comic_reading_page.dart';
import 'package:pica_comic/tools/time.dart';
import 'package:pica_comic/foundation/history.dart';
import '../base.dart';
import '../foundation/app.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:pica_comic/components/components.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({Key? key}) : super(key: key);

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final comics = HistoryManager().getAll();
  bool searchInit = false;
  bool searchMode = false;
  String keyword = "";
  var results = <History>[];
  bool isModified = false;

  @override
  void dispose() {
    if (isModified) {
      appdata.history.saveData();
    }
    super.dispose();
  }

  Widget buildTitle() {
    if (searchMode) {
      final FocusNode focusNode = FocusNode();
      focusNode.requestFocus();
      bool focus = searchInit;
      searchInit = false;
      return TextField(
        focusNode: focus ? focusNode : null,
        decoration:
        InputDecoration(border: InputBorder.none, hintText: "搜索".tl),
        onChanged: (s) {
          setState(() {
            keyword = s.toLowerCase();
          });
        },
      );
    } else {
      return Text("${"历史记录".tl}(${comics.length})");
    }
  }

  void find() {
    results.clear();
    if (keyword == "") {
      results.addAll(comics);
    } else {
      for (var element in comics) {
        if (element.title.toLowerCase().contains(keyword) ||
            element.subtitle.toLowerCase().contains(keyword)) {
          results.add(element);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (searchMode) {
      find();
    }
    return Scaffold(
      body: SmoothCustomScrollView(
        slivers: [
          SliverAppbar(
            title: buildTitle(),
            actions: [
              Tooltip(
                message: "清除".tl,
                child: IconButton(
                  icon: const Icon(Icons.delete_forever),
                  onPressed: () => showDialog(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                            title: Text("清除记录".tl),
                            content: Text("要清除历史记录吗?".tl),
                            actions: [
                              TextButton(
                                  onPressed: () => App.globalBack(),
                                  child: Text("取消".tl)),
                              TextButton(
                                  onPressed: () {
                                    appdata.history.clearHistory();
                                    setState(() => comics.clear());
                                    isModified = true;
                                    App.globalBack();
                                  },
                                  child: Text("清除".tl)),
                            ],
                          )),
                ),
              ),
              Tooltip(
                message: "搜索".tl,
                child: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () {
                    setState(() {
                      searchMode = !searchMode;
                      searchInit = true;
                      if (!searchMode) {
                        keyword = "";
                      }
                    });
                  },
                ),
              )
            ],
          ),
          if (!searchMode) buildComics(comics) else buildComics(results),
          SliverPadding(
            padding:
                EdgeInsets.only(top: MediaQuery.of(context).padding.bottom),
          )
        ],
      ),
    );
  }

  Widget buildComics(List<History> comics_) {
    return SliverGrid(
      delegate:
          SliverChildBuilderDelegate(childCount: comics_.length, (context, i) {
        final comic = ComicItemBrief(
          comics_[i].title,
          comics_[i].subtitle,
          0,
          comics_[i].cover != ""
              ? comics_[i].cover
              : getJmCoverUrl(comics_[i].target),
          comics_[i].target,
          [],
        );
        return NormalComicTile(
          key: Key(comics_[i].target),
          sourceKey: comics_[i].type.comicSource?.key,
          onLongTap: () {
            showDialog(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    title: Text("删除".tl),
                    content: Text("要删除这条历史记录吗".tl),
                    actions: [
                      TextButton(
                          onPressed: () => App.globalBack(),
                          child: Text("取消".tl)),
                      TextButton(
                          onPressed: () {
                            appdata.history.remove(comics_[i].target);
                            setState(() {
                              isModified = true;
                              comics.removeWhere((element) =>
                                  element.target == comics_[i].target);
                            });
                            App.globalBack();
                          },
                          child: Text("删除".tl)),
                    ],
                  );
                });
          },
          description_: timeToString(comics_[i].time),
          coverPath: comic.path,
          name: comic.title,
          subTitle_: comic.author,
          badgeName: comics_[i].type.name,
          headers: {
            if (comics_[i].type == HistoryType.ehentai)
              "cookie": EhNetwork().cookiesStr,
            if (comics_[i].type == HistoryType.ehentai ||
                comics_[i].type == HistoryType.hitomi)
              "User-Agent": webUA,
            if (comics_[i].type == HistoryType.hitomi)
              "Referer": "https://hitomi.la/"
          },
          onTap: () {
            toComicPageWithHistory(context, comics_[i]);
          },
        );
      }),
      gridDelegate: SliverGridDelegateWithComics(),
    );
  }
}

void toComicPageWithHistory(BuildContext context, History history) {
  // 检查是否是服务器漫画（HistoryType == 99）
  if (history.type.value == 99) {
    _openServerComic(context, history);
    return;
  }
  
  var source = history.type.comicSource;
  if (source == null) {
    showToast(message: "Comic Source Not Found");
    return;
  }
  context.to(
    () => ComicPage(
      sourceKey: source.key,
      id: history.target,
      cover: history.cover,
    ),
  );
}

Future<void> _openServerComic(BuildContext context, History history) async {
  final serverUrl = appdata.settings[90];
  
  if (serverUrl.isEmpty) {
    showToast(message: '请先在设置中配置服务器地址'.tl);
    return;
  }
  
  try {
    showLoadingDialog(context, barrierDismissible: false, allowCancel: false);
    
    final client = ServerClient(serverUrl);
    final comic = await client.getComicDetail(history.target);
    
    Navigator.pop(context); // 关闭加载对话框
    
    final readingData = ServerReadingData(
      serverUrl: serverUrl,
      comic: comic,
    );
    
    // 使用历史记录中的位置
    int initialPage = history.page > 0 ? history.page : 1;
    int initialEp = history.ep > 0 ? history.ep : 1;
    
    context.to(() => ComicReadingPage(readingData, initialPage, initialEp));
  } catch (e) {
    Navigator.pop(context); // 确保关闭加载对话框
    showToast(message: '打开失败: $e');
  }
}
