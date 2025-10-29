import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/network/app_dio.dart';
import 'package:pica_comic/network/base_comic.dart';
import 'package:pica_comic/network/custom_download_model.dart';
import 'package:pica_comic/network/download.dart';
import 'package:pica_comic/network/hitomi_network/hitomi_download_model.dart';
import 'package:pica_comic/network/download_model.dart';
import 'package:pica_comic/network/htmanga_network/ht_download_model.dart';
import 'package:pica_comic/network/nhentai_network/download.dart';
import 'package:pica_comic/network/nhentai_network/nhentai_main_network.dart';
import 'package:pica_comic/pages/comic_page.dart';
import 'package:pica_comic/pages/picacg/comic_page.dart';
import 'package:pica_comic/pages/reader/comic_reading_page.dart';
import 'package:pica_comic/tools/extensions.dart';
import 'package:pica_comic/tools/io_tools.dart';
import 'package:pica_comic/foundation/ui_mode.dart';
import 'package:pica_comic/tools/pdf.dart';
import 'package:pica_comic/tools/tags_translation.dart';
import 'package:pica_comic/pages/downloading_page.dart';
import 'package:pica_comic/pages/ehentai/eh_gallery_page.dart';
import 'package:pica_comic/pages/hitomi/hitomi_comic_page.dart';
import 'package:pica_comic/pages/jm/jm_comic_page.dart';
import 'package:pica_comic/pages/nhentai/comic_page.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/network/eh_network/eh_download_model.dart';
import 'package:pica_comic/network/jm_network/jm_download.dart';
import 'package:pica_comic/network/picacg_network/picacg_download_model.dart';
import 'package:pica_comic/network/server_client.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:pica_comic/components/components.dart';

import 'htmanga/ht_comic_page.dart';

extension ReadComic on DownloadedItem {
  void read({int? ep}) async {
    final comic = this;
    if (comic.type == DownloadType.picacg) {
      var history =
          await History.findOrCreate((comic as DownloadedComic).comicItem);
      App.globalTo(
        () => ComicReadingPage.picacg(
          comic.id,
          ep ?? history.ep,
          comic.eps,
          comic.name,
          initialPage: ep == null ? history.page : 0,
        ),
      );
    } else if (comic.type == DownloadType.ehentai) {
      var history =
          await History.findOrCreate((comic as DownloadedGallery).gallery);
      App.globalTo(
        () => ComicReadingPage.ehentai(
          (comic).gallery,
          initialPage: ep == null ? history.page : 0,
        ),
      );
    } else if (comic.type == DownloadType.jm) {
      var history =
          await History.findOrCreate((comic as DownloadedJmComic).comic);
      App.globalTo(
        () => ComicReadingPage.jmComic(
          comic.comic,
          ep ?? history.ep,
          initialPage: ep == null ? history.page : 0,
        ),
      );
    } else if (comic.type == DownloadType.hitomi) {
      var history =
          await History.findOrCreate((comic as DownloadedHitomiComic).comic);
      App.globalTo(
        () => ComicReadingPage.hitomi(
          comic.comic,
          comic.link,
          initialPage: ep == null ? history.page : 0,
        ),
      );
    } else if (comic.type == DownloadType.htmanga) {
      var history =
          await History.findOrCreate((comic as DownloadedHtComic).comic);
      App.globalTo(
        () => ComicReadingPage.htmanga(
          comic.comic.id,
          comic.comic.title,
          initialPage: ep == null ? history.page : 0,
        ),
      );
    } else if (comic.type == DownloadType.nhentai) {
      var nc = NhentaiComic(
          comic.id.replaceFirst("nhentai", ""),
          comic.name,
          comic.subTitle,
          (comic as NhentaiDownloadedComic).cover,
          {},
          false,
          [],
          [],
          "");
      var history = await History.findOrCreate(nc);
      App.globalTo(
        () => ComicReadingPage.nhentai(
          comic.id.replaceFirst("nhentai", ""),
          comic.title,
          initialPage: ep == null ? history.page : 0,
        ),
      );
    } else if (comic.type == DownloadType.other) {
      comic as CustomDownloadedItem;
      var data = ComicInfoData(
        name,
        subTitle,
        comic.cover,
        null,
        {},
        null,
        null,
        null,
        0,
        null,
        comic.sourceKey,
        comic.id.replaceFirst("${comic.sourceKey}-", ""),
      );
      var history = await History.findOrCreate(data);
      App.globalTo(
        () => ComicReadingPage(
          CustomReadingData(
            data.target,
            data.title,
            ComicSource.find(comic.sourceKey),
            comic.chapters,
          ),
          ep == null ? history.page : 0,
          ep ?? history.ep,
        ),
      );
    }
  }
}

class DownloadPageLogic extends StateController {
  ///是否正在加载
  bool loading = true;

  ///是否处于选择状态
  bool selecting = false;

  ///已选择的数量
  int selectedNum = 0;

  ///已选择的漫画
  var selected = <bool>[];

  ///已下载的漫画
  var comics = <DownloadedItem>[];

  var baseComics = <DownloadedItem>[];

  bool searchMode = false;

  bool searchInit = false;

  String keyword = "";
  String keyword_ = "";

  void change() {
    loading = !loading;
    try {
      update();
    } catch (e) {
      //忽视
    }
  }

  void find() {
    if (keyword == keyword_) {
      return;
    }
    keyword_ = keyword;
    comics.clear();
    if (keyword == "") {
      comics.addAll(baseComics);
    } else {
      for (var element in baseComics) {
        if (element.name.toLowerCase().contains(keyword) ||
            element.subTitle.toLowerCase().contains(keyword)) {
          comics.add(element);
        }
      }
    }
    resetSelected(comics.length);
  }

  @override
  void refresh() {
    searchMode = false;
    selecting = false;
    selectedNum = 0;
    selected.clear();
    comics.clear();
    change();
  }

  void resetSelected(int length) {
    selected = List.generate(length, (index) => false);
    selectedNum = 0;
  }
}

class DownloadPage extends StatelessWidget {
  const DownloadPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StateBuilder<DownloadPageLogic>(
        init: DownloadPageLogic(),
        builder: (logic) {
          if (logic.loading) {
            Future.wait([
              getComics(logic),
              Future.delayed(const Duration(milliseconds: 300))
            ]).then((v) {
              logic.resetSelected(logic.comics.length);
              logic.change();
            });
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          } else {
            return Scaffold(
              floatingActionButton: buildFAB(context, logic),
              body: SmoothCustomScrollView(
                slivers: [
                  buildAppbar(context, logic),
                  buildComics(context, logic)
                ],
              ),
            );
          }
        });
  }

  Widget buildComics(BuildContext context, DownloadPageLogic logic) {
    logic.find();
    final comics = logic.comics;
    return SliverGrid(
      delegate: SliverChildBuilderDelegate(childCount: comics.length,
          (context, index) {
        return buildItem(context, logic, index);
      }),
      gridDelegate: SliverGridDelegateWithComics(),
    );
  }

  Future<void> getComics(DownloadPageLogic logic) async {
    var order = '', direction = 'desc';
    switch (appdata.settings[26][0]) {
      case "0":
        order = 'time';
      case "1":
        order = 'title';
      case "2":
        order = 'subtitle';
      case "3":
        order = 'size';
      default:
        throw UnimplementedError();
    }
    if (appdata.settings[26][1] == "1") {
      direction = 'asc';
    }
    logic.comics = DownloadManager().getAll(order, direction);
    logic.baseComics = logic.comics.toList();
  }

  Future<void> export(DownloadPageLogic logic) async {
    var comics = <DownloadedItem>[];
    for (int i = 0; i < logic.selected.length; i++) {
      if (logic.selected[i]) {
        comics.add(logic.comics[i]);
      }
    }
    if (comics.isEmpty) {
      return;
    }
    bool res;
    if (comics.length > 1) {
      res = await exportComics(comics);
    } else {
      res = await exportComic(
          comics.first.id, comics.first.name, comics.first.eps);
    }
    App.globalBack();
    if (!res) {
      showToast(message: "导出失败".tl);
    }
  }

  void downloadFont() async {
    bool canceled = false;
    var cancelToken = CancelToken();
    var controller = showLoadingDialog(
      App.globalContext!,
      onCancel: () {
        canceled = true;
        cancelToken.cancel();
      },
      barrierDismissible: false,
      allowCancel: true,
      message: "Downloading",
    );
    var dio = logDio();
    try {
      await dio.download(
        "https://raw.githubusercontent.com/Pacalini/PicaComic/master/fonts/NotoSansSC-Regular.ttf",
        "${App.dataPath}/font.ttf",
        cancelToken: cancelToken,
      );
    } catch (e) {
      showToast(message: "下载失败".tl);
      controller.close();
      return;
    }
    if (!canceled) {
      controller.close();
      showToast(message: "下载完成".tl);
    }
  }

  void exportAsPdf(DownloadedItem? comic, DownloadPageLogic logic) async {
    if (comic == null) {
      for (int i = 0; i < logic.selected.length; i++) {
        if (logic.selected[i]) {
          comic = logic.comics[i];
        }
      }
    }
    if (comic == null) {
      showToast(message: "请选择一个漫画".tl);
      return;
    }
    var file = File("${App.dataPath}/font.ttf");
    if (!App.isWindows && !await file.exists()) {
      showConfirmDialog(App.globalContext!, "缺少字体".tl,
          "需要下载字体文件(10.1MB), 是否继续?".tl, downloadFont);
    } else {
      bool canceled = false;
      var controller = showLoadingDialog(
        App.globalContext!,
        onCancel: () => canceled = true,
        allowCancel: false,
      );
      var fileName = "${comic.name}.pdf";
      fileName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
      await createPdfFromComicWithIsolate(
          title: comic.name,
          comicPath: "${downloadManager.path}/${downloadManager.getDirectory(comic.id)}",
          savePath: "${App.cachePath}/$fileName",
          chapters: comic.eps,
          chapterIndexes: comic.downloadedEps);
      if (!canceled) {
        controller.close();
        await exportPdf("${App.cachePath}/$fileName");
      }
    }
  }

  Widget buildItem(BuildContext context, DownloadPageLogic logic, int index) {
    bool selected = logic.selected[index];
    var type = logic.comics[index].type.name;
    if (logic.comics[index].type == DownloadType.other) {
      type = (logic.comics[index] as CustomDownloadedItem).sourceName;
    }
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Container(
        decoration: BoxDecoration(
            color: selected
                ? Theme.of(context).colorScheme.surfaceContainerHighest
                : Colors.transparent,
            borderRadius: const BorderRadius.all(Radius.circular(16))),
        child: DownloadedComicTile(
          name: logic.comics[index].name,
          author: logic.comics[index].subTitle,
          imagePath: downloadManager.getCover(logic.comics[index].id),
          type: type,
          tag: logic.comics[index].tags,
          onTap: () async {
            if (logic.selecting) {
              logic.selected[index] = !logic.selected[index];
              logic.selected[index] ? logic.selectedNum++ : logic.selectedNum--;
              if (logic.selectedNum == 0) {
                logic.selecting = false;
              }
              logic.update();
            } else {
              showInfo(index, logic, context);
            }
          },
          size: () {
            if (logic.comics[index].comicSize != null) {
              return logic.comics[index].comicSize!.toStringAsFixed(2);
            } else {
              return "未知大小".tl;
            }
          }.call(),
          onLongTap: () {
            if (logic.selecting) return;
            logic.selected[index] = true;
            logic.selectedNum++;
            logic.selecting = true;
            logic.update();
          },
          onSecondaryTap: (details) {
            showDesktopMenu(App.globalContext!,
                Offset(details.globalPosition.dx, details.globalPosition.dy), [
              DesktopMenuEntry(
                text: "阅读".tl,
                onClick: () {
                  logic.comics[index].read();
                },
              ),
              DesktopMenuEntry(
                text: "删除".tl,
                onClick: () {
                  showConfirmDialog(context, "确认删除".tl, "此操作无法撤销, 是否继续?".tl,
                      () {
                    downloadManager.delete([logic.comics[index].id]);
                    logic.comics.removeAt(index);
                    logic.selected.removeAt(index);
                    logic.update();
                  });
                },
              ),
              DesktopMenuEntry(
                text: "导出".tl,
                onClick: () =>
                    Future.delayed(const Duration(milliseconds: 200), () {
                  Future<void>.delayed(
                    const Duration(milliseconds: 200),
                    () => showDialog(
                      context: App.globalContext!,
                      barrierDismissible: false,
                      barrierColor: Colors.black26,
                      builder: (context) => SimpleDialog(
                        children: [
                          SizedBox(
                            width: 200,
                            height: 200,
                            child: Center(
                              child: SizedBox(
                                width: 50,
                                height: 80,
                                child: Column(
                                  children: [
                                    const SizedBox(
                                      height: 10,
                                    ),
                                    const CircularProgressIndicator(),
                                    const SizedBox(
                                      height: 9,
                                    ),
                                    Text("打包中".tl)
                                  ],
                                ),
                              ),
                            ),
                          )
                        ],
                      ),
                    ),
                  );
                  Future<void>.delayed(const Duration(milliseconds: 500),
                      () async {
                    var res = await exportComic(logic.comics[index].id,
                        logic.comics[index].name, logic.comics[index].eps);
                    App.globalBack();
                    if (res) {
                      //忽视
                    } else {
                      showToast(message: "导出失败".tl);
                    }
                  });
                }),
              ),
              DesktopMenuEntry(
                text: "导出为pdf".tl,
                onClick: () {
                  exportAsPdf(logic.comics[index], logic);
                },
              ),
              DesktopMenuEntry(
                text: "查看漫画详情".tl,
                onClick: () {
                  Future.delayed(const Duration(milliseconds: 300), () {
                    toComicInfoPage(logic.comics[index]);
                  });
                },
              ),
              DesktopMenuEntry(
                text: "复制路径".tl,
                onClick: () {
                  Future.delayed(const Duration(milliseconds: 300), () {
                    var path =
                        "${downloadManager.path}/${downloadManager.getDirectory(logic.comics[index].id)}";
                    Clipboard.setData(ClipboardData(text: path));
                  });
                },
              ),
            ]);
          },
        ),
      ),
    );
  }

  void toComicInfoPage(DownloadedItem comic) => _toComicInfoPage(comic);

  void showInfo(int index, DownloadPageLogic logic, BuildContext context) {
    if (UiMode.m1(context)) {
      showModalBottomSheet(
          context: context,
          builder: (context) {
            return DownloadedComicInfoView(logic.comics[index], logic);
          });
    } else {
      showSideBar(App.globalContext!,
          DownloadedComicInfoView(logic.comics[index], logic),
          useSurfaceTintColor: true);
    }
  }

  Widget buildFAB(BuildContext context, DownloadPageLogic logic) =>
      FloatingActionButton(
        enableFeedback: true,
        onPressed: () {
          if (!logic.selecting) {
            logic.selecting = true;
            logic.update();
          } else {
            if (logic.selectedNum == 0) return;
            showDialog(
                context: context,
                builder: (dialogContext) {
                  return AlertDialog(
                    title: Text("删除".tl),
                    content: Text("要删除已选择的项目吗? 此操作无法撤销".tl),
                    actions: [
                      TextButton(
                          onPressed: () => App.globalBack(),
                          child: Text("取消".tl)),
                      TextButton(
                          onPressed: () async {
                            App.globalBack();
                            var comics = <String>[];
                            for (int i = 0; i < logic.selected.length; i++) {
                              if (logic.selected[i]) {
                                comics.add(logic.comics[i].id);
                              }
                            }
                            await downloadManager.delete(comics);
                            logic.refresh();
                          },
                          child: Text("确认".tl)),
                    ],
                  );
                });
          }
        },
        child: logic.selecting
            ? const Icon(Icons.delete_forever_outlined)
            : const Icon(Icons.checklist_outlined),
      );

  Widget buildTitle(BuildContext context, DownloadPageLogic logic) {
    if (logic.searchMode && !logic.selecting) {
      final FocusNode focusNode = FocusNode();
      focusNode.requestFocus();
      bool focus = logic.searchInit;
      logic.searchInit = false;
      return TextField(
        focusNode: focus ? focusNode : null,
        decoration:
        InputDecoration(border: InputBorder.none, hintText: "搜索".tl),
        onChanged: (s) {
          logic.keyword = s.toLowerCase();
          logic.update();
        },
      );
    } else {
      return logic.selecting
          ? Text("已选择 @num 个项目".tlParams({"num": logic.selectedNum.toString()}))
          : Text("已下载".tl);
    }
  }

  Widget buildAppbar(BuildContext context, DownloadPageLogic logic) {
    return SliverAppbar(
      radius: UiMode.m1(context) ? 0 : 16,
      color: logic.selecting
        ? Theme.of(context).colorScheme.primaryContainer
        : null,
      leading: logic.selecting
          ? IconButton(
          onPressed: () {
            logic.selecting = false;
            logic.selectedNum = 0;
            for (int i = 0; i < logic.selected.length; i++) {
              logic.selected[i] = false;
            }
            logic.update();
          },
          icon: const Icon(Icons.close))
          : IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back)),
      title: buildTitle(context, logic),
      actions: buildActions(context, logic),
    );
  }

  List<Widget> buildActions(BuildContext context, DownloadPageLogic logic) {
    return [
      if (!logic.selecting && !logic.searchMode)
        Tooltip(
          message: "排序".tl,
          child: IconButton(
            icon: const Icon(Icons.sort),
            onPressed: () async {
              bool changed = false;
              await showDialog(
                  context: context,
                  builder: (context) => SimpleDialog(
                    title: Text("漫画排序模式".tl),
                    children: [
                      SizedBox(
                        width: 400,
                        child: Column(
                          children: [
                            ListTile(
                              title: Text("漫画排序模式".tl),
                              trailing: Select(
                                initialValue:
                                int.parse(appdata.settings[26][0]),
                                onChange: (i) {
                                  appdata.settings[26] = appdata
                                      .settings[26]
                                      .setValueAt(i.toString(), 0);
                                  appdata.updateSettings();
                                  changed = true;
                                },
                                values: ["时间", "漫画名", "作者名", "大小"].tl,
                              ),
                            ),
                            ListTile(
                              title: Text("倒序".tl),
                              trailing: StatefulSwitch(
                                initialValue:
                                appdata.settings[26][1] == "1",
                                onChanged: (b) {
                                  if (b) {
                                    appdata.settings[26] = appdata
                                        .settings[26]
                                        .setValueAt("1", 1);
                                  } else {
                                    appdata.settings[26] = appdata
                                        .settings[26]
                                        .setValueAt("0", 1);
                                  }
                                  appdata.updateSettings();
                                  changed = true;
                                },
                              ),
                            ),
                          ],
                        ),
                      )
                    ],
                  ));
              if (changed) {
                logic.refresh();
              }
            },
          ),
        ),
      if (!logic.selecting && !logic.searchMode)
        Tooltip(
          message: "下载管理器".tl,
          child: IconButton(
            icon: const Icon(Icons.download_for_offline),
            onPressed: () {
              showPopUpWidget(
                App.globalContext!,
                const DownloadingPage(),
              );
            },
          ),
        )
      else if (logic.selecting)
        Tooltip(
          message: "更多".tl,
          child: IconButton(
            icon: const Icon(Icons.more_horiz),
            onPressed: () {
              showMenu(
                  context: context,
                  position: RelativeRect.fromLTRB(
                      MediaQuery.of(context).size.width - 60,
                      50,
                      MediaQuery.of(context).size.width - 60,
                      50),
                  items: [
                    PopupMenuItem(
                      child: Text("全选".tl),
                      onTap: () {
                        for (int i = 0; i < logic.selected.length; i++) {
                          logic.selected[i] = true;
                        }
                        logic.selectedNum = logic.comics.length;
                        logic.update();
                      },
                    ),
                    PopupMenuItem(
                      child: Text("导出".tl),
                      onTap: () => exportSelectedComic(context, logic),
                    ),
                    PopupMenuItem(
                      child: Text("导出为pdf".tl),
                      onTap: () => exportAsPdf(null, logic),
                    ),
                    PopupMenuItem(
                      child: Text("导出到服务器".tl),
                      onTap: () => exportToServer(context, logic),
                    ),
                    PopupMenuItem(
                      child: Text("查看漫画详情".tl),
                      onTap: () => Future.delayed(
                          const Duration(milliseconds: 200), () {
                        if (logic.selectedNum != 1) {
                          showToast(message: "请选择一个漫画".tl);
                        } else {
                          for (int i = 0; i < logic.selected.length; i++) {
                            if (logic.selected[i]) {
                              toComicInfoPage(logic.comics[i]);
                            }
                          }
                        }
                      }),
                    ),
                    PopupMenuItem(
                      child: Text("添加至本地收藏".tl),
                      onTap: () => Future.delayed(
                        const Duration(milliseconds: 200),
                            () => addToLocalFavoriteFolder(
                            App.globalContext!, logic),
                      ),
                    ),
                  ]);
            },
          ),
        ),
      if (!logic.selecting)
        Tooltip(
          message: "搜索".tl,
          child: IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              logic.searchMode = !logic.searchMode;
              logic.searchInit = true;
              if (!logic.searchMode) {
                logic.keyword = "";
              }
              logic.update();
            },
          ),
        )
    ];
  }

  void exportSelectedComic(BuildContext context, DownloadPageLogic logic) {
    if (logic.selectedNum == 0) {
      showToast(message: "请选择漫画".tl);
    } else {
      Future<void>.delayed(
        const Duration(milliseconds: 200),
        () => showDialog(
          context: App.globalContext!,
          barrierColor: Colors.black26,
          barrierDismissible: false,
          builder: (context) => const SimpleDialog(
            children: [
              SizedBox(
                width: 200,
                height: 200,
                child: Center(
                  child: SizedBox(
                    width: 50,
                    height: 75,
                    child: Column(
                      children: [
                        SizedBox(
                          height: 10,
                        ),
                        CircularProgressIndicator(),
                        SizedBox(
                          height: 9,
                        ),
                        Text("打包中")
                      ],
                    ),
                  ),
                ),
              )
            ],
          ),
        ),
      );
      Future<void>.delayed(
          const Duration(milliseconds: 500), () => export(logic));
    }
  }

  void exportToServer(BuildContext context, DownloadPageLogic logic) async {
    print('\n╔════════════════════════════════════════╗');
    print('║   开始执行导出到服务器功能           ║');
    print('╚════════════════════════════════════════╝');
    
    // 检查是否选择了漫画
    print('[导出] 检查选中的漫画数量: ${logic.selectedNum}');
    if (logic.selectedNum == 0) {
      print('[导出] ❌ 错误: 没有选中任何漫画');
      showToast(message: "请选择漫画".tl);
      return;
    }

    // 检查服务器配置
    var serverUrl = appdata.settings[90];
    print('[导出] 服务器URL配置: $serverUrl');
    
    if (serverUrl == null || serverUrl.isEmpty) {
      print('[导出] ❌ 错误: 服务器URL未配置');
      showToast(message: "请先在设置中配置服务器地址".tl);
      return;
    }

    // 获取选中的漫画
    var selectedComics = <DownloadedItem>[];
    for (int i = 0; i < logic.selected.length; i++) {
      if (logic.selected[i]) {
        selectedComics.add(logic.comics[i]);
      }
    }

    print('[导出] 实际选中的漫画数量: ${selectedComics.length}');
    for (int i = 0; i < selectedComics.length; i++) {
      print('[导出]   ${i + 1}. ${selectedComics[i].name} (${selectedComics[i].downloadedEps.length} 章节)');
    }

    if (selectedComics.isEmpty) {
      print('[导出] ❌ 错误: 选中列表为空');
      return;
    }
    
    print('[导出] ✓ 准备显示确认对话框\n');

    // 显示确认对话框
    showDialog(
      context: App.globalContext!,
      builder: (context) => AlertDialog(
        title: Text("导出到服务器".tl),
        content: Text("要将 ${selectedComics.length} 个已下载的漫画上传到服务器吗？\n\n将会上传漫画的所有图片和元数据。"),
        actions: [
          TextButton(
            onPressed: () => App.globalBack(),
            child: Text("取消".tl),
          ),
          FilledButton(
            onPressed: () async {
              print('[导出] 用户点击了确认按钮');
              App.globalBack();
              
              print('[导出] 显示加载对话框...');
              // 显示加载对话框
              var progressController = showLoadingDialog(
                App.globalContext!,
                allowCancel: false,
              );
              
              print('[导出] 开始批量上传...');
              try {
                int successCount = 0;
                int failCount = 0;

                for (var i = 0; i < selectedComics.length; i++) {
                  var comic = selectedComics[i];
                  print('\n[导出队列] 正在处理第 ${i + 1}/${selectedComics.length} 个漫画: ${comic.name}');
                  
                  try {
                    await _uploadComicToServer(comic, serverUrl);
                    successCount++;
                    print('[导出队列] ✅ 漫画 "${comic.name}" 上传成功\n');
                  } catch (e, stackTrace) {
                    print('[导出队列] ❌ 漫画 "${comic.name}" 上传失败');
                    print('[导出队列] 错误信息: $e');
                    print('[导出队列] 堆栈跟踪: $stackTrace\n');
                    failCount++;
                  }
                }

                progressController.close();
                
                print('\n╔════════════════════════════════════════╗');
                print('║   导出完成                           ║');
                print('╚════════════════════════════════════════╝');
                print('[导出] 成功: $successCount 个');
                print('[导出] 失败: $failCount 个');
                print('[导出] 总计: ${successCount + failCount} 个\n');
                
                if (failCount == 0) {
                  showToast(message: "导出成功，共 $successCount 个漫画".tl);
                } else {
                  showToast(message: "导出完成: $successCount 成功, $failCount 失败".tl);
                }
              } catch (e, stackTrace) {
                print('\n╔════════════════════════════════════════╗');
                print('║   导出失败（异常）                   ║');
                print('╚════════════════════════════════════════╝');
                print('[导出] 异常: $e');
                print('[导出] 堆栈: $stackTrace\n');
                progressController.close();
                showToast(message: "导出失败: $e");
              }
            },
            child: Text("确认".tl),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadComicToServer(DownloadedItem comic, String serverUrl) async {
    print('========================================');
    print('[导出] *** 开始导出漫画到服务器 ***');
    print('[导出] 漫画名称: ${comic.name}');
    print('[导出] 漫画ID: ${comic.id}');
    print('[导出] 漫画类型: ${comic.type}');
    print('========================================');
    
    final dio = Dio();
    final downloadManager = DownloadManager();
    
    // 使用 downloadManager.getDirectory() 获取正确的目录名（和导出PDF一样的方式）
    final downloadPath = downloadManager.path!;
    final directory = downloadManager.getDirectory(comic.id);
    final comicPath = '$downloadPath/$directory';
    
    print('[导出] 下载根路径: $downloadPath');
    print('[导出] 漫画目录名: $directory');
    print('[导出] 完整路径: $comicPath');
    print('[导出] 已下载章节数量: ${comic.downloadedEps.length}');
    print('[导出] 已下载章节列表: ${comic.downloadedEps}');
    print('[导出] 章节名称列表: ${comic.eps}');
    print('========================================');
    
    // 提取tags和描述（转换为Map<String, List<String>>格式）
    Map<String, List<String>> tagsMap = {};
    String description = '';
    
    if (comic is DownloadedComic) {
      // Picacg漫画
      tagsMap = {
        "category": comic.comicItem.categories,
        "tags": comic.comicItem.tags,
      };
      description = comic.comicItem.description ?? '';
    } else if (comic is DownloadedGallery) {
      // EHentai漫画
      tagsMap = {
        "type": [comic.gallery.type],
        "uploader": [comic.gallery.uploader],
        ...comic.gallery.tags
      };
      description = 'EHentai Gallery';
    } else if (comic is DownloadedHitomiComic) {
      // Hitomi漫画
      tagsMap = {
        "artists": comic.comic.artists ?? [],
        "groups": comic.comic.group,
        "type": [comic.comic.type],
        "tags": comic.comic.tags.map((e) => e.name).toList(),
      };
      description = 'Hitomi Comic';
    } else if (comic is DownloadedJmComic) {
      // JM漫画
      tagsMap = {
        "tags": comic.tags,
      };
      description = comic.comic.description ?? '';
    } else if (comic is NhentaiDownloadedComic) {
      // NHentai漫画
      tagsMap = {
        "tags": comic.tags,
      };
      description = 'NHentai Comic';
    } else if (comic is DownloadedHtComic) {
      // HTManga漫画
      tagsMap = {
        "tags": comic.tags,
      };
      description = 'HTManga Comic';
    } else {
      // 其他漫画源，使用简单的tags列表
      tagsMap = {"tags": comic.tags};
      description = '';
    }
    
    // 计算文件总数用于进度显示
    int totalFiles = 0;
    int uploadedFiles = 0;
    
    // 统计需要上传的文件数量
    print('[导出] 开始统计文件...');
    for (int ep in comic.downloadedEps) {
      final actualEp = ep + 1;  // downloadedEps 是索引(从0开始)，目录名是章节号(从1开始)
      final epDir = Directory('$comicPath/$actualEp');
      if (await epDir.exists()) {
        final files = await epDir.list().toList();
        int epFileCount = 0;
        for (var file in files) {
          if (file is File && _isImageFile(file.path)) {
            totalFiles++;
            epFileCount++;
          }
        }
        print('[导出] 章节 $actualEp: $epFileCount 个图片文件');
      } else {
        print('[导出] 警告: 章节目录不存在: ${epDir.path}');
      }
    }
    print('[导出] 统计完成: 总共 $totalFiles 个图片文件需要上传');
    
    // 创建FormData并添加基本信息
    final formData = FormData();
    formData.fields.addAll([
      MapEntry('comic_id', comic.id),
      MapEntry('title', comic.name),
      MapEntry('type', comic.type.toString().split('.').last),
      MapEntry('author', comic.subTitle),
      MapEntry('description', description),
      MapEntry('tags', jsonEncode(tagsMap)),
      MapEntry('eps', jsonEncode(comic.eps)),
      MapEntry('downloaded_eps', jsonEncode(comic.downloadedEps)),
      MapEntry('download_time', comic.time?.toIso8601String() ?? DateTime.now().toIso8601String()),
    ]);
    
    // 上传封面
    print('[导出] 检查封面文件...');
    final coverPath = '$comicPath/cover.jpg';
    final coverFile = File(coverPath);
    if (await coverFile.exists()) {
      print('[导出] 找到封面: cover.jpg');
      formData.files.add(MapEntry(
        'files',
        await MultipartFile.fromFile(coverPath, filename: 'cover.jpg'),
      ));
      uploadedFiles++;
    } else {
      // 尝试 PNG 格式封面
      final coverPngPath = '$comicPath/cover.png';
      final coverPngFile = File(coverPngPath);
      if (await coverPngFile.exists()) {
        print('[导出] 找到封面: cover.png');
        formData.files.add(MapEntry(
          'files',
          await MultipartFile.fromFile(coverPngPath, filename: 'cover.png'),
        ));
        uploadedFiles++;
      } else {
        print('[导出] 警告: 未找到封面文件');
      }
    }
    
    // 上传所有章节的图片
    print('[导出] 开始上传章节图片...');
    print('[导出] 已下载章节列表 (索引): ${comic.downloadedEps}');
    print('[导出] 漫画类型: ${comic.type}');
    
    // 检查是否是 EHentai（图片在根目录，不在章节子目录）
    bool isEhentai = comic is DownloadedGallery;
    
    if (isEhentai) {
      print('[导出] 检测到 EHentai 漫画，图片在根目录');
      // EHentai 的图片直接在根目录，文件名格式为: 0.jpg, 1.jpg, 2.jpg...
      final files = await Directory(comicPath).list().toList();
      print('[导出] 根目录中共有 ${files.length} 个条目');
      
      // 对文件进行排序
      final imageFiles = files
          .whereType<File>()
          .where((file) => _isImageFile(file.path) && !file.path.contains('cover'))
          .toList();
      
      print('[导出] 过滤后有 ${imageFiles.length} 个图片文件');
      
      // 按文件名数字排序
      imageFiles.sort((a, b) {
        final aNum = _extractPageNumber(a.path);
        final bNum = _extractPageNumber(b.path);
        return aNum.compareTo(bNum);
      });
      
      for (var file in imageFiles) {
        final filename = file.path.split('/').last;
        final pageNum = _extractPageNumber(file.path);
        final ext = filename.split('.').last;
        final uploadFilename = 'ep1_page${pageNum.toString().padLeft(3, '0')}.$ext';
        
        print('[导出] 添加文件到队列: $uploadFilename (来源: $filename, 页码: $pageNum)');
        
        formData.files.add(MapEntry(
          'files',
          await MultipartFile.fromFile(
            file.path,
            filename: uploadFilename,
          ),
        ));
        
        uploadedFiles++;
        
        // 更新进度
        if (totalFiles > 0 && uploadedFiles % 10 == 0) {
          final progress = uploadedFiles / totalFiles;
          print('[导出] 上传进度: ${(progress * 100).toStringAsFixed(1)}% ($uploadedFiles/$totalFiles)');
        }
      }
    } else {
      // 其他漫画源，章节在子目录中
      for (int ep in comic.downloadedEps) {
        final actualEp = ep + 1;  // downloadedEps 是索引(从0开始)，目录名是章节号(从1开始)
        final epDir = Directory('$comicPath/$actualEp');
        print('[导出] 检查章节索引 $ep -> 目录 $actualEp: ${epDir.path}');
        
        if (await epDir.exists()) {
          print('[导出] ✓ 章节 $actualEp 目录存在');
          final files = await epDir.list().toList();
          print('[导出] 章节 $actualEp 目录中共有 ${files.length} 个条目');
          
          // 列出所有文件用于调试
          for (var file in files) {
            if (file is File) {
              print('[导出] 发现文件: ${file.path.split('/').last}');
            }
          }
          
          // 对文件进行排序，确保按正确顺序上传
          final imageFiles = files
              .whereType<File>()
              .where((file) => _isImageFile(file.path))
              .toList();
          
          print('[导出] 章节 $actualEp: 过滤后有 ${imageFiles.length} 个图片文件');
          
          if (imageFiles.isEmpty) {
            print('[导出] ⚠️ 警告: 章节 $actualEp 没有找到任何图片文件！');
            continue;
          }
          
          // 按文件名排序
          imageFiles.sort((a, b) {
            final aNum = _extractPageNumber(a.path);
            final bNum = _extractPageNumber(b.path);
            return aNum.compareTo(bNum);
          });
          
          for (var file in imageFiles) {
            final filename = file.path.split('/').last;
            final pageNum = _extractPageNumber(file.path);
            final ext = filename.split('.').last;
            final uploadFilename = 'ep${actualEp}_page${pageNum.toString().padLeft(3, '0')}.$ext';
            
            print('[导出] 添加文件到队列: $uploadFilename (来源: $filename, 页码: $pageNum)');
            
            formData.files.add(MapEntry(
              'files',
              await MultipartFile.fromFile(
                file.path,
                filename: uploadFilename,
              ),
            ));
            
            uploadedFiles++;
            
            // 更新进度
            if (totalFiles > 0 && uploadedFiles % 10 == 0) { // 每10个文件打印一次
              final progress = uploadedFiles / totalFiles;
              print('[导出] 上传进度: ${(progress * 100).toStringAsFixed(1)}% ($uploadedFiles/$totalFiles)');
            }
          }
        } else {
          print('[导出] ✗ 错误: 章节目录不存在: ${epDir.path}');
        }
      }
    }
    
    print('[导出] 所有文件已添加到上传队列，共 ${formData.files.length} 个文件');
    
    // 发送上传请求
    print('[导出] 开始发送HTTP请求到服务器...');
    print('[导出] 服务器地址: $serverUrl/api/download/import');
    
    final response = await dio.post(
      '$serverUrl/api/download/import',
      data: formData,
      options: Options(
        headers: {'Content-Type': 'multipart/form-data'},
        sendTimeout: const Duration(minutes: 30),
        receiveTimeout: const Duration(minutes: 30),
      ),
      onSendProgress: (sent, total) {
        if (total > 0) {
          final progress = sent / total;
          if (sent % (total ~/ 10).clamp(1, 1024 * 1024) == 0 || sent == total) { // 每10%打印一次
            print('[导出] 网络传输进度: ${(progress * 100).toStringAsFixed(1)}% (${(sent / 1024 / 1024).toStringAsFixed(2)}MB / ${(total / 1024 / 1024).toStringAsFixed(2)}MB)');
          }
        }
      },
    );
    
    print('[导出] 服务器响应状态码: ${response.statusCode}');
    
    if (response.statusCode != 200) {
      print('[导出] 错误: 上传失败 - ${response.data}');
      throw Exception('上传失败: ${response.data}');
    }
    
    print('[导出] ✅ 导出成功！');
  }
  
  // 检查是否是图片文件
  bool _isImageFile(String path) {
    final ext = path.toLowerCase().split('.').last;
    return ext == 'jpg' || ext == 'jpeg' || ext == 'png' || ext == 'webp' || ext == 'gif';
  }
  
  // 从文件名中提取页码
  int _extractPageNumber(String path) {
    final filename = path.split('/').last;
    
    // 尝试多种格式:
    // 1. 纯数字文件名: 001.jpg, 1.jpg, 0001.png
    // 2. page_001.jpg
    // 3. p1.jpg
    // 4. image_1.jpg
    
    // 移除扩展名
    final nameWithoutExt = filename.substring(0, filename.lastIndexOf('.'));
    
    // 提取所有数字
    final numbers = RegExp(r'\d+').allMatches(nameWithoutExt);
    
    if (numbers.isNotEmpty) {
      // 优先使用最后一个数字（通常是页码）
      final lastNumber = numbers.last.group(0);
      return int.tryParse(lastNumber!) ?? 0;
    }
    
    return 0;
  }

  void addToLocalFavoriteFolder(BuildContext context, DownloadPageLogic logic) {
    String? folder;
    showDialog(
        context: App.globalContext!,
        builder: (context) => SimpleDialog(
              title: const Text("复制到..."),
              children: [
                SizedBox(
                  width: 400,
                  height: 132,
                  child: Column(
                    children: [
                      ListTile(
                        title: Text("收藏夹".tl),
                        trailing: Select(
                          width: 156,
                          values: LocalFavoritesManager().folderNames,
                          initialValue: null,
                          onChange: (i) =>
                              folder = LocalFavoritesManager().folderNames[i],
                        ),
                      ),
                      const Spacer(),
                      Center(
                        child: FilledButton(
                          child: Text("确认".tl),
                          onPressed: () {
                            if (folder == null) {
                              return;
                            }
                            for (int i = 0; i < logic.selected.length; i++) {
                              if (logic.selected[i]) {
                                var comic = logic.comics[i];
                                LocalFavoritesManager().addComic(
                                    folder!,
                                    switch (comic.type) {
                                      DownloadType.picacg =>
                                        FavoriteItem.fromPicacg(
                                            (comic as DownloadedComic)
                                                .comicItem
                                                .toBrief()),
                                      DownloadType.ehentai =>
                                        FavoriteItem.fromEhentai(
                                            (comic as DownloadedGallery)
                                                .gallery
                                                .toBrief()),
                                      DownloadType.jm =>
                                        FavoriteItem.fromJmComic(
                                            (comic as DownloadedJmComic)
                                                .comic
                                                .toBrief()),
                                      DownloadType.nhentai => FavoriteItem
                                          .fromNhentai(NhentaiComicBrief(
                                              comic.name,
                                              (comic as NhentaiDownloadedComic)
                                                  .cover,
                                              comic.id,
                                              "",
                                              const [])),
                                      DownloadType.hitomi =>
                                        FavoriteItem.fromHitomi((comic
                                                as DownloadedHitomiComic)
                                            .comic
                                            .toBrief(comic.link, comic.cover)),
                                      DownloadType.htmanga =>
                                        FavoriteItem.fromHtcomic(
                                            (comic as DownloadedHtComic)
                                                .comic
                                                .toBrief()),
                                      DownloadType.other => () {
                                          var c =
                                              (comic as CustomDownloadedItem);
                                          return FavoriteItem.custom(
                                              CustomComic(
                                                  c.name,
                                                  c.subTitle,
                                                  c.cover,
                                                  c.comicId,
                                                  c.tags,
                                                  "",
                                                  c.sourceKey));
                                        }(),
                                      DownloadType.favorite =>
                                        throw UnimplementedError(),
                                    });
                              }
                            }
                            App.globalBack();
                          },
                        ),
                      ),
                      const SizedBox(
                        height: 16,
                      ),
                    ],
                  ),
                )
              ],
            ));
  }
}

class DownloadedComicInfoView extends StatefulWidget {
  const DownloadedComicInfoView(this.item, this.logic, {Key? key})
      : super(key: key);
  final DownloadedItem item;
  final DownloadPageLogic logic;

  @override
  State<DownloadedComicInfoView> createState() =>
      _DownloadedComicInfoViewState();
}

class _DownloadedComicInfoViewState extends State<DownloadedComicInfoView> {
  String name = "";
  List<String> eps = [];
  List<int> downloadedEps = [];
  late final comic = widget.item;

  deleteEpisode(int i) {
    showConfirmDialog(context, "确认删除".tl, "要删除这个章节吗".tl, () async {
      var message = await DownloadManager().deleteEpisode(comic, i);
      if (message == null) {
        setState(() {});
      } else {
        showToast(message: message);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    getInfo();
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 16, 0, 16),
            child: Text(
              name,
              style: const TextStyle(fontSize: 22),
            ),
          ),
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
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius:
                            const BorderRadius.all(Radius.circular(16)),
                        color: downloadedEps.contains(i)
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                      ),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 16,
                          ),
                          Expanded(
                            child: Text(
                              eps[i],
                            ),
                          ),
                          const SizedBox(
                            width: 4,
                          ),
                          if (downloadedEps.contains(i))
                            const Icon(Icons.download_done),
                          const SizedBox(
                            width: 16,
                          ),
                        ],
                      ),
                    ),
                    onTap: () => readSpecifiedEps(i),
                    onLongPress: () {
                      deleteEpisode(i);
                    },
                    onSecondaryTapDown: (details) {
                      deleteEpisode(i);
                    },
                  ),
                );
              },
              itemCount: eps.length,
            ),
          ),
          SizedBox(
              height: 50,
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton(
                        onPressed: () {
                          App.globalBack();
                          _toComicInfoPage(widget.item);
                        },
                        child: Text("查看详情".tl)),
                  ),
                  const SizedBox(
                    width: 16,
                  ),
                  Expanded(
                    child: FilledButton(
                        onPressed: () => read(), child: Text("阅读".tl)),
                  ),
                ],
              )),
          SizedBox(
            height: MediaQuery.of(context).padding.bottom,
          )
        ],
      ),
    );
  }

  void getInfo() {
    name = comic.name;
    eps = comic.eps;
    downloadedEps = comic.downloadedEps;
  }

  void read() {
    comic.read();
  }

  void readSpecifiedEps(int i) {
    comic.read(ep: i + 1);
  }
}

class DownloadedComicTile extends ComicTile {
  final String size;
  final File imagePath;
  final String author;
  final String name;
  final String type;
  final List<String> tag;
  final void Function() onTap;
  final void Function() onLongTap;
  final void Function(TapDownDetails details) onSecondaryTap;

  @override
  List<String>? get tags => tag.map((e) =>
    App.locale.languageCode == "zh"
        ? e.translateTagsToCN
        : e
  ).toList();

  @override
  String get description => "${size}MB";

  @override
  Widget get image => Image.file(
        imagePath,
        fit: BoxFit.cover,
        height: double.infinity,
      );

  @override
  void onTap_() => onTap();

  @override
  String get subTitle => author;

  @override
  String get title => name;

  @override
  void onLongTap_() => onLongTap();

  @override
  void onSecondaryTap_(details) => onSecondaryTap(details);

  @override
  String? get badge => type;

  const DownloadedComicTile(
      {required this.size,
      required this.imagePath,
      required this.author,
      required this.name,
      required this.onTap,
      required this.onLongTap,
      required this.onSecondaryTap,
      required this.type,
      required this.tag,
      super.key});
}

void _toComicInfoPage(DownloadedItem comic) {
  var context = App.mainNavigatorKey!.currentContext!;
  if (comic is DownloadedComic) {
    context.to(() => PicacgComicPage((comic).comicItem.id, null));
  } else if (comic is DownloadedGallery) {
    context.to(() => EhGalleryPage((comic).gallery.toBrief()));
  } else if (comic is DownloadedJmComic) {
    context.to(() => JmComicPage((comic).comic.id));
  } else if (comic is DownloadedHitomiComic) {
    context.to(() => HitomiComicPage(comic.toBrief()));
  } else if (comic is DownloadedHtComic) {
    context.to(() => HtComicPage(comic.id.replaceFirst('Ht', '')));
  } else if (comic is NhentaiDownloadedComic) {
    context.to(() => NhentaiComicPage(comic.id.replaceFirst("nhentai", "")));
  } else if (comic is CustomDownloadedItem) {
    context.to(() => ComicPage(sourceKey: comic.sourceKey, id: comic.comicId));
  }
}
