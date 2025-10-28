library pica_settings;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_reorderable_grid_view/widgets/reorderable_builder.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/comic_source/built_in/picacg.dart';
import 'package:pica_comic/comic_source/built_in/jm.dart';
import 'package:pica_comic/foundation/cache_manager.dart';
import 'package:pica_comic/foundation/ui_mode.dart';
import 'package:pica_comic/main.dart';
import 'package:pica_comic/network/app_dio.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/pages/logs_page.dart';
import 'package:pica_comic/tools/extensions.dart';
import 'package:pica_comic/tools/io_tools.dart';
import 'package:url_launcher/url_launcher_string.dart';
import '../../comic_source/comic_source.dart';
import '../../foundation/app.dart';
import '../../foundation/local_favorites.dart';
import '../../network/cookie_jar.dart';
import '../../network/download.dart';
import '../../network/eh_network/eh_main_network.dart';
import '../../network/http_client.dart';
import '../../network/http_proxy.dart';
import '../../network/jm_network/jm_network.dart';
import '../../network/nhentai_network/nhentai_main_network.dart';
import '../../network/update.dart';
import '../../network/webdav.dart';
import '../../tools/background_service.dart';
import '../../tools/debug.dart';
import '../welcome_page.dart';
import 'package:pica_comic/tools/translations.dart';
import '../server_settings_page.dart';
import '../server_comics_page.dart';

part "reading_settings.dart";
part "picacg_settings.dart";
part "network_setting.dart";
part "multi_pages_filter.dart";
part "local_favorite_settings.dart";
part "jm_settings.dart";
part "hi_settings.dart";
part "ht_settings.dart";
part "explore_settings.dart";
part "eh_settings.dart";
part "nh_settings.dart";
part "comic_source_settings.dart";
part "blocking_keyword_page.dart";
part "app_settings.dart";
part 'components.dart';

class SettingsPage extends StatefulWidget {
  static void open([int initialPage = -1]) {
    App.globalTo(() => SettingsPage(initialPage: initialPage));
  }

  const SettingsPage({this.initialPage = -1, super.key});

  final int initialPage;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> implements PopEntry{
  int currentPage = -1;

  ColorScheme get colors => Theme.of(context).colorScheme;

  bool get enableTwoViews => !UiMode.m1(context);

  final categories = <String>["浏览", "漫画源", "阅读", "外观", "本地收藏", "服务器", "APP", "网络", "关于"];

  final icons = <IconData>[
    Icons.explore,
    Icons.source,
    Icons.book,
    Icons.color_lens,
    Icons.collections_bookmark_rounded,
    Icons.cloud,
    Icons.apps,
    Icons.public,
    Icons.info
  ];

  double offset = 0;

  late final HorizontalDragGestureRecognizer gestureRecognizer;

  ModalRoute? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ModalRoute<dynamic>? nextRoute = ModalRoute.of(context);
    if (nextRoute != _route) {
      _route?.unregisterPopEntry(this);
      _route = nextRoute;
      _route?.registerPopEntry(this);
    }
  }

  @override
  void initState() {
    currentPage = widget.initialPage;
    gestureRecognizer = HorizontalDragGestureRecognizer(debugOwner: this)
      ..onUpdate = ((details) => setState(() => offset += details.delta.dx))
      ..onEnd = (details) async {
        if (details.velocity.pixelsPerSecond.dx.abs() > 1 &&
            details.velocity.pixelsPerSecond.dx >= 0) {
          setState(() {
            Future.delayed(const Duration(milliseconds: 300), () => offset = 0);
            currentPage = -1;
          });
        } else if (offset > MediaQuery.of(context).size.width / 2) {
          setState(() {
            Future.delayed(const Duration(milliseconds: 300), () => offset = 0);
            currentPage = -1;
          });
        } else {
          int i = 10;
          while (offset != 0) {
            setState(() {
              offset -= i;
              i *= 10;
              if (offset < 0) {
                offset = 0;
              }
            });
            await Future.delayed(const Duration(milliseconds: 10));
          }
        }
      }
      ..onCancel = () async {
        int i = 10;
        while (offset != 0) {
          setState(() {
            offset -= i;
            i *= 10;
            if (offset < 0) {
              offset = 0;
            }
          });
          await Future.delayed(const Duration(milliseconds: 10));
        }
      };
    super.initState();
  }

  @override
  dispose() {
    super.dispose();
    gestureRecognizer.dispose();
    App.temporaryDisablePopGesture = false;
    _route?.unregisterPopEntry(this);
  }

  @override
  Widget build(BuildContext context) {
    if (currentPage != -1 && !enableTwoViews) {
      canPop.value = false;
      App.temporaryDisablePopGesture = true;
    } else {
      canPop.value = true;
      App.temporaryDisablePopGesture = false;
    }
    return Material(
      child: buildBody(),
    );
  }

  Widget buildBody() {
    if (enableTwoViews) {
      return Row(
        children: [
          SizedBox(
            width: 320,
            height: double.infinity,
            child: buildLeft(),
          ),
          Container(
            height: double.infinity,
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: context.colorScheme.outlineVariant,
                  width: 0.6,
                ),
              ),
            ),
          ),
          Expanded(child: buildRight())
        ],
      );
    } else {
      return Stack(
        children: [
          Positioned.fill(child: buildLeft()),
          Positioned(
            left: offset,
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            child: Listener(
              onPointerDown: handlePointerDown,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                reverseDuration: const Duration(milliseconds: 300),
                switchInCurve: Curves.fastOutSlowIn,
                switchOutCurve: Curves.fastOutSlowIn,
                transitionBuilder: (child, animation) {
                  var tween = Tween<Offset>(
                      begin: const Offset(1, 0), end: const Offset(0, 0));

                  return SlideTransition(
                    position: tween.animate(animation),
                    child: child,
                  );
                },
                child: currentPage == -1
                    ? const SizedBox(
                        key: Key("1"),
                      )
                    : buildRight(),
              ),
            ),
          )
        ],
      );
    }
  }

  void handlePointerDown(PointerDownEvent event) {
    if (event.position.dx < 20) {
      gestureRecognizer.addPointer(event);
    }
  }

  Widget buildLeft() {
    return Material(
      child: Column(
        children: [
          SizedBox(
            height: MediaQuery.of(context).padding.top,
          ),
          SizedBox(
            height: 56,
            child: Row(children: [
              const SizedBox(
                width: 8,
              ),
              Tooltip(
                message: "Back",
                child: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => App.globalBack(),
                ),
              ),
              const SizedBox(
                width: 24,
              ),
              Text(
                "设置".tl,
                style: Theme.of(context).textTheme.headlineSmall,
              )
            ]),
          ),
          const SizedBox(
            height: 4,
          ),
          Expanded(
            child: buildCategories(),
          )
        ],
      ),
    );
  }

  Widget buildCategories() {
    Widget buildItem(String name, int id) {
      final bool selected = id == currentPage;

      Widget content = AnimatedContainer(
        key: ValueKey(id),
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        height: 48,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        decoration: BoxDecoration(
            color: selected ? colors.primaryContainer : null,
            borderRadius: BorderRadius.circular(16)
        ),
        child: Row(children: [
          Icon(icons[id]),
          const SizedBox(
            width: 16,
          ),
          Text(
            name,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Spacer(),
          if (selected) const Icon(Icons.arrow_right)
        ]),
      );

      return Padding(
        padding: enableTwoViews
            ? const EdgeInsets.fromLTRB(16, 0, 16, 0)
            : EdgeInsets.zero,
        child: InkWell(
          onTap: () => setState(() => currentPage = id),
          borderRadius: BorderRadius.circular(16),
          child: content,
        ).paddingVertical(4),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: categories.length,
      itemBuilder: (context, index) => buildItem(categories[index].tl, index),
    );
  }

  Widget buildReadingSettings() {
    return const Placeholder();
  }

  Widget buildAppearanceSettings() => Column(
        children: [
          ListTile(
            leading: const Icon(Icons.color_lens),
            title: Text("主题选择".tl),
            trailing: Select(
              initialValue: int.parse(appdata.settings[27]),
              values: const [
                "dynamic",
                "red",
                "pink",
                "purple",
                "indigo",
                "blue",
                "cyan",
                "teal",
                "green",
                "lime",
                "yellow",
                "amber",
                "orange",
              ],
              onChange: (i) {
                appdata.settings[27] = i.toString();
                appdata.updateSettings();
                MyApp.updater?.call();
              },
              width: 140,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dark_mode),
            title: Text("深色模式".tl),
            trailing: Select(
              initialValue: int.parse(appdata.settings[32]),
              values: ["跟随系统".tl, "禁用".tl, "启用".tl],
              onChange: (i) {
                appdata.settings[32] = i.toString();
                appdata.updateSettings();
                MyApp.updater?.call();
              },
              width: 140,
            ),
          ),
          if (appdata.settings[32] == "0" || appdata.settings[32] == "2")
            ListTile(
              leading: const Icon(Icons.remove_red_eye),
              title: Text("纯黑色模式".tl),
              trailing: Switch(
                value: appdata.settings[84] == "1",
                onChanged: (i) {
                  setState(() {
                    appdata.settings[84] = i ? "1" : "0";
                  });
                  appdata.updateSettings();
                  MyApp.updater?.call();
                },
              ),
            ),
          if (App.isAndroid)
            ListTile(
              leading: const Icon(Icons.smart_screen_outlined),
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("高刷新率模式".tl),
                  const SizedBox(
                    width: 2,
                  ),
                  InkWell(
                    borderRadius: const BorderRadius.all(Radius.circular(18)),
                    onTap: () => showDialogMessage(
                        context,
                        "高刷新率模式".tl,
                        "${"尝试强制设置高刷新率".tl}\n${"可能不起作用".tl}"),
                    child: const Icon(
                      Icons.info_outline,
                      size: 18,
                    ),
                  )
                ],
              ),
              trailing: Switch(
                value: appdata.settings[38] == "1",
                onChanged: (b) {
                  setState(() {
                    appdata.settings[38] = b ? "1" : "0";
                  });
                  appdata.updateSettings();
                  if (b) {
                    try {
                      FlutterDisplayMode.setHighRefreshRate();
                    } catch (e) {
                      // ignore
                    }
                  } else {
                    try {
                      FlutterDisplayMode.setLowRefreshRate();
                    } catch (e) {
                      // ignore
                    }
                  }
                },
              ),
            )
        ],
      );

  Widget buildAppSettings() {
    return Column(
      children: [
        ListTile(
          title: Text("日志".tl),
        ),
        ListTile(
          leading: const Icon(Icons.bug_report),
          title: const Text("Logs"),
          trailing: const Icon(Icons.arrow_right),
          onTap: () => context.to(() => const LogsPage()),
        ),
        ListTile(
          title: Text("更新".tl),
        ),
        ListTile(
          leading: const Icon(Icons.update),
          title: Text("检查更新".tl),
          subtitle: Text("${"当前:".tl} $appVersion"),
          onTap: () {
            findUpdate(context);
          },
        ),
        SwitchSetting(
          title: "启动时检查更新".tl,
          settingsIndex: 2,
          icon: const Icon(Icons.security_update),
        ),
        ListTile(
          title: Text("数据".tl),
        ),
        if (App.isDesktop || App.isAndroid)
          ListTile(
            leading: const Icon(Icons.folder),
            title: Text("设置下载目录".tl),
            trailing: const Icon(Icons.arrow_right),
            onTap: () => setDownloadFolder(),
          ),
        ListTile(
          leading: const Icon(Icons.sd_storage_outlined),
          title: Text("缓存大小限制".tl),
          subtitle: Text('${bytesLengthToReadableSize(CacheManager().currentSize)}'
                         ' / '
                         '${bytesLengthToReadableSize(CacheManager().limitSize)}'),
          onTap: setCacheLimit,
          trailing: const Icon(Icons.arrow_right),
        ),
        // ListTile(
        //   leading: const Icon(Icons.sd_storage_outlined),
        //   title: Text("设置缓存限制".tl),
        //   onTap: setCacheLimit,
        //   trailing: const Icon(Icons.arrow_right),
        // ),
        ListTile(
          leading: const Icon(Icons.delete_outline),
          title: Text("清除缓存".tl),
          onTap: () {
            CacheManager().clear().then((value) {
              if(mounted) {
                setState(() {});
              }
            });
          },
        ),
        ListTile(
          leading: const Icon(Icons.delete_forever),
          title: Text("删除所有数据".tl),
          trailing: const Icon(Icons.arrow_right),
          onTap: () => clearUserData(context),
        ),
        ListTile(
          leading: const Icon(Icons.sim_card_download),
          title: Text("导出用户数据".tl),
          trailing: const Icon(Icons.arrow_right),
          onTap: () => exportDataSetting(context),
        ),
        ListTile(
          leading: const Icon(Icons.data_object),
          title: Text("导入用户数据".tl),
          trailing: const Icon(Icons.arrow_right),
          onTap: () => importDataSetting(context),
        ),
        ListTile(
          leading: const Icon(Icons.sync),
          title: Text("数据同步".tl),
          trailing: const Icon(Icons.arrow_right),
          onTap: () => syncDataSettings(context),
        ),
        ListTile(
          title: Text("隐私".tl),
        ),
        if (App.isAndroid)
          ListTile(
            leading: const Icon(Icons.screenshot),
            title: Text("阻止屏幕截图".tl),
            subtitle: Text("需要重启App以应用更改".tl),
            trailing: Switch(
              value: appdata.settings[12] == "1",
              onChanged: (b) {
                b ? appdata.settings[12] = "1" : appdata.settings[12] = "0";
                setState(() {});
                appdata.writeData();
              },
            ),
          ),
        SwitchSetting(
          title: "需要身份验证".tl,
          subTitle: "如果系统中未设置任何认证方法请勿开启".tl,
          settingsIndex: 13,
          icon: const Icon(Icons.security),
        ),
        ListTile(
          title: Text("其它".tl),
        ),
        ListTile(
          title: Text("语言".tl),
          leading: const Icon(Icons.language),
          trailing: Select(
            initialValue: ["", "cn", "tw", "en"].indexOf(appdata.settings[50]),
            values: const ["System", "中文(简体)", "中文(繁體)", "English"],
            onChange: (value) {
              appdata.settings[50] = ["", "cn", "tw", "en"][value];
              appdata.updateSettings();
              MyApp.updater?.call();
            },
          ),
        ),
        ListTile(
          title: Text("下载并行".tl),
          leading: const Icon(Icons.download),
          trailing: Select(
            initialValue: ["1", "2", "4", "6", "8", "16"].indexOf(appdata.settings[79]),
            values: const ["1", "2", "4", "6", "8", "16"],
            onChange: (value) {
              appdata.settings[79] = ["1", "2", "4", "6", "8", "16"][value];
              appdata.updateSettings();
            },
          ),
        ),
        if(App.isAndroid)
          ListTile(
            title: Text("应用链接".tl),
            subtitle: Text("在系统设置中管理APP支持的链接".tl),
            leading: const Icon(Icons.link),
            trailing: const Icon(Icons.arrow_right),
            onTap: (){
              const MethodChannel("pica_comic/settings").invokeMethod("link");
            },
          ),
        if(kDebugMode)
          const ListTile(
            title: Text("Debug"),
            onTap: debug,
          ),
        Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom))
      ],
    );
  }

  Widget buildServerSettings() {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.settings),
          title: Text("服务器配置".tl),
          subtitle: Text("配置服务器连接和账号".tl),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            context.to(() => const ServerSettingsPage());
          },
        ),
        ListTile(
          leading: const Icon(Icons.cloud),
          title: Text("浏览服务器漫画".tl),
          subtitle: Text("查看服务器上已下载的漫画".tl),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            context.to(() => const ServerComicsPage());
          },
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text("关于服务器".tl),
          subtitle: Text("服务器可以在其他设备上运行，实现多设备共享漫画".tl),
        ),
      ],
    );
  }

  Widget buildAbout() {
    return Column(
      children: [
        SizedBox(
          height: 130,
          width: double.infinity,
          child: Center(
            child: Container(
              width: 156,
              height: 156,
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20)),
              child: const Image(
                image: AssetImage("images/app_icon_no_bg.png"),
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
        ),
        const Text(
          "V$appVersion",
          style: TextStyle(fontSize: 16),
        ),
        Text("Pica Comic是一个完全免费的漫画阅读APP".tl),
        Text("仅用于学习交流".tl),
        const SizedBox(
          height: 16,
        ),
        ListTile(
          leading: const Icon(Icons.code),
          title: Text("项目地址".tl),
          onTap: () => launchUrlString("https://github.com/Pacalini/PicaComic",
              mode: LaunchMode.externalApplication),
          trailing: const Icon(Icons.open_in_new),
        ),
        ListTile(
          leading: const Icon(Icons.comment_outlined),
          title: Text("问题反馈 (Github)".tl),
          onTap: () => launchUrlString(
              "https://github.com/Pacalini/PicaComic/issues",
              mode: LaunchMode.externalApplication),
          trailing: const Icon(Icons.open_in_new),
        ),
        // ListTile(
        //   leading: const Icon(Icons.email),
        //   title: Text("EMAIL_ME_PLACEHOLDER".tl),
        //   onTap: () => launchUrlString("mailto://example@foo.bar",
        //       mode: LaunchMode.externalApplication),
        //   trailing: const Icon(Icons.arrow_right),
        // ),
        // ListTile(
        //   leading: const Icon(Icons.telegram),
        //   title: Text("JOIN_GROUP_PLACEHOLDER".tl),
        //   onTap: () => launchUrlString("https://t.me/example",
        //       mode: LaunchMode.externalApplication),
        //   trailing: const Icon(Icons.arrow_right),
        // ),
        Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom))
      ],
    );
  }

  Widget buildRight() {
    final Widget body = switch (currentPage) {
      -1 => const SizedBox(),
      0 => buildExploreSettings(context, false),
      1 => const ComicSourceSettings(),
      2 => const ReadingSettings(false),
      3 => buildAppearanceSettings(),
      4 => const LocalFavoritesSettings(),
      5 => buildServerSettings(),
      6 => buildAppSettings(),
      7 => const NetworkSettings(),
      8 => buildAbout(),
      _ => throw UnimplementedError()
    };

    if (currentPage != -1) {
      return Material(
        child: CustomScrollView(
          primary: false,
          slivers: [
            SliverAppBar(
                title: Text(categories[currentPage].tl),
                automaticallyImplyLeading: false,
                scrolledUnderElevation: enableTwoViews ? 0 : null,
                leading: enableTwoViews
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => setState(() => currentPage = -1),
                      )),
            SliverToBoxAdapter(
              child: body,
            )
          ],
        ),
      );
    }

    return body;
  }

  var canPop = ValueNotifier(true);

  @override
  ValueListenable<bool> get canPopNotifier => canPop;

  @override
  void onPopInvokedWithResult(bool didPop, result) {
    if (currentPage != -1) {
      setState(() {
        currentPage = -1;
      });
    }
  }

  @override
  void onPopInvoked(bool didPop) {
    if (currentPage != -1) {
      setState(() {
        currentPage = -1;
      });
    }
  }
}
