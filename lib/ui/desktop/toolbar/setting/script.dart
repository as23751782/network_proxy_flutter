/*
 * Copyright 2023 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:network_proxy/network/components/script_manager.dart';
import 'package:network_proxy/network/util/logger.dart';
import 'package:network_proxy/ui/component/utils.dart';
import 'package:network_proxy/ui/component/widgets.dart';

bool _refresh = false;

/// 刷新脚本
void _refreshScript() {
  if (_refresh) {
    return;
  }
  _refresh = true;
  Future.delayed(const Duration(milliseconds: 1000), () async {
    _refresh = false;
    (await ScriptManager.instance).flushConfig();
    await DesktopMultiWindow.invokeMethod(0, "refreshScript");
  });
}

/// @author wanghongen
/// 2023/10/8
class ScriptWidget extends StatefulWidget {
  final int windowId;

  const ScriptWidget({super.key, required this.windowId});

  @override
  State<ScriptWidget> createState() => _ScriptWidgetState();
}

class _ScriptWidgetState extends State<ScriptWidget> {
  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(onKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(onKeyEvent);
    super.dispose();
  }

  bool onKeyEvent(KeyEvent event) {
    if ((HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyW) {
      HardwareKeyboard.instance.removeHandler(onKeyEvent);
      WindowController.fromWindowId(widget.windowId).close();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: Theme.of(context).dialogBackgroundColor,
        appBar: AppBar(
            title: Text(localizations.script, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            toolbarHeight: 36,
            centerTitle: true),
        body: Padding(
            padding: const EdgeInsets.only(left: 15, right: 10),
            child: futureWidget(
                ScriptManager.instance,
                loading: true,
                (data) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          Row(children: [
                            SizedBox(
                                width: 300,
                                child: SwitchWidget(
                                  title: localizations.enableScript,
                                  subtitle: localizations.scriptUseDescribe,
                                  value: data.enabled,
                                  onChanged: (value) {
                                    data.enabled = value;
                                    _refreshScript();
                                  },
                                )),
                            Expanded(
                                child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                const SizedBox(width: 10),
                                FilledButton(
                                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.only(left: 20, right: 20)),
                                  onPressed: scriptEdit,
                                  child: Text(localizations.add),
                                ),
                                const SizedBox(width: 10),
                                OutlinedButton(
                                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.only(left: 20, right: 20)),
                                  onPressed: import,
                                  child: Text(localizations.import),
                                )
                              ],
                            )),
                            const SizedBox(width: 15)
                          ]),
                          const SizedBox(height: 5),
                          Container(
                              padding: const EdgeInsets.only(top: 10),
                              constraints: const BoxConstraints(maxHeight: 500, minHeight: 300),
                              decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey.withOpacity(0.2))),
                              child: SingleChildScrollView(
                                  child: Column(children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  children: [
                                    Container(
                                        width: 200,
                                        padding: const EdgeInsets.only(left: 10),
                                        child: Text(localizations.name)),
                                    SizedBox(width: 50, child: Text(localizations.enable, textAlign: TextAlign.center)),
                                    const VerticalDivider(),
                                    const Expanded(child: Text("URL")),
                                  ],
                                ),
                                const Divider(thickness: 0.5),
                                ScriptList(scripts: data.list, windowId: widget.windowId),
                              ]))),
                        ]))));
  }

  //导入js
  import() async {
    String? file = await DesktopMultiWindow.invokeMethod(0, 'openFile', 'json');
    WindowController.fromWindowId(widget.windowId).show();
    if (file == null) {
      return;
    }

    try {
      var json = jsonDecode(await File(file).readAsString());
      var scriptItem = ScriptItem.fromJson(json);
      (await ScriptManager.instance).addScript(scriptItem, json['script']);
      _refreshScript();
      if (mounted) {
        FlutterToastr.show(localizations.importSuccess, context);
      }
      setState(() {});
    } catch (e, t) {
      logger.e('导入失败 $file', error: e, stackTrace: t);
      if (mounted) {
        FlutterToastr.show("${localizations.importFailed} $e", context);
      }
    }
  }

  /// 添加脚本
  scriptEdit() async {
    showDialog(barrierDismissible: false, context: context, builder: (_) => const ScriptEdit()).then((value) {
      if (value != null) {
        setState(() {});
      }
    });
  }
}

/// 编辑脚本
class ScriptEdit extends StatefulWidget {
  final ScriptItem? scriptItem;
  final String? script;

  const ScriptEdit({super.key, this.scriptItem, this.script});

  @override
  State<StatefulWidget> createState() => _ScriptEditState();
}

class _ScriptEditState extends State<ScriptEdit> {
  late CodeController script;
  late TextEditingController nameController;
  late TextEditingController urlController;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    script = CodeController(language: javascript, text: widget.script ?? ScriptManager.template);
    nameController = TextEditingController(text: widget.scriptItem?.name);
    urlController = TextEditingController(text: widget.scriptItem?.url);
  }

  @override
  void dispose() {
    script.dispose();
    nameController.dispose();
    urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    GlobalKey formKey = GlobalKey<FormState>();
    return AlertDialog(
        scrollable: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
        titlePadding: const EdgeInsets.only(left: 15, top: 5, right: 15),
        title: Row(children: [
          Text(localizations.scriptEdit, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          const SizedBox(width: 10),
          Text.rich(TextSpan(
              text: localizations.useGuide,
              style: const TextStyle(color: Colors.blue, fontSize: 14),
              recognizer: TapGestureRecognizer()
                ..onTap = () => DesktopMultiWindow.invokeMethod(
                    0, "launchUrl", 'https://gitee.com/wanghongenpin/network-proxy-flutter/wikis/%E8%84%9A%E6%9C%AC'))),
          const Expanded(child: Align(alignment: Alignment.topRight, child: CloseButton()))
        ]),
        actionsPadding: const EdgeInsets.only(right: 10, bottom: 10),
        actions: [
          ElevatedButton(onPressed: () => Navigator.of(context).pop(), child: Text(localizations.cancel)),
          FilledButton(
              onPressed: () async {
                if (!(formKey.currentState as FormState).validate()) {
                  FlutterToastr.show("${localizations.name} URL ${localizations.cannotBeEmpty}", context,
                      position: FlutterToastr.top);
                  return;
                }
                //新增
                if (widget.scriptItem == null) {
                  var scriptItem = ScriptItem(true, nameController.text, urlController.text);
                  (await ScriptManager.instance).addScript(scriptItem, script.text);
                } else {
                  widget.scriptItem?.name = nameController.text;
                  widget.scriptItem?.url = urlController.text;
                  widget.scriptItem?.urlReg = null;
                  (await ScriptManager.instance).updateScript(widget.scriptItem!, script.text);
                }

                _refreshScript();
                if (context.mounted) {
                  Navigator.of(context).maybePop(true);
                }
              },
              child: Text(localizations.save)),
        ],
        content: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                textField("${localizations.name}:", nameController, localizations.pleaseEnter),
                const SizedBox(height: 10),
                textField("URL:", urlController, "github.com/api/*", keyboardType: TextInputType.url),
                const SizedBox(height: 10),
                Text("${localizations.script}:"),
                const SizedBox(height: 5),
                SizedBox(
                    width: 850,
                    height: 360,
                    child: CodeTheme(
                        data: CodeThemeData(styles: monokaiSublimeTheme),
                        child: SingleChildScrollView(
                            child: CodeField(textStyle: const TextStyle(fontSize: 13), controller: script))))
              ],
            )));
  }

  Widget textField(String label, TextEditingController controller, String hint, {TextInputType? keyboardType}) {
    return Row(children: [
      SizedBox(width: 50, child: Text(label)),
      Expanded(
          child: TextFormField(
        controller: controller,
        validator: (val) => val?.isNotEmpty == true ? null : "",
        keyboardType: keyboardType,
        decoration: InputDecoration(
            hintText: hint,
            contentPadding: const EdgeInsets.all(10),
            errorStyle: const TextStyle(height: 0, fontSize: 0),
            focusedBorder: focusedBorder(),
            isDense: true,
            border: const OutlineInputBorder()),
      ))
    ]);
  }

  InputBorder focusedBorder() {
    return OutlineInputBorder(borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2));
  }
}

/// 脚本列表
class ScriptList extends StatefulWidget {
  final int windowId;
  final List<ScriptItem> scripts;

  const ScriptList({super.key, required this.scripts, required this.windowId});

  @override
  State<ScriptList> createState() => _ScriptListState();
}

class _ScriptListState extends State<ScriptList> {
  int selected = -1;

  AppLocalizations get localizations => AppLocalizations.of(context)!;

  @override
  Widget build(BuildContext context) {
    return Column(children: rows(widget.scripts));
  }

  List<Widget> rows(List<ScriptItem> list) {
    var primaryColor = Theme.of(context).colorScheme.primary;

    return List.generate(list.length, (index) {
      return InkWell(
          // onTap: () {
          //   selected[index] = !(selected[index] ?? false);
          //   setState(() {});
          // },
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
          hoverColor: primaryColor.withOpacity(0.3),
          onDoubleTap: () async {
            String script = await (await ScriptManager.instance).getScript(list[index]);
            if (!mounted) {
              return;
            }
            showDialog(
                barrierDismissible: false,
                context: context,
                builder: (_) => ScriptEdit(scriptItem: list[index], script: script)).then((value) {
              if (value != null) {
                setState(() {});
              }
            });
          },
          onSecondaryTapDown: (details) => showMenus(details, index),
          child: Container(
              color: selected == index
                  ? primaryColor.withOpacity(0.8)
                  : index.isEven
                      ? Colors.grey.withOpacity(0.1)
                      : null,
              height: 30,
              padding: const EdgeInsets.all(5),
              child: Row(
                children: [
                  SizedBox(width: 200, child: Text(list[index].name!, style: const TextStyle(fontSize: 13))),
                  SizedBox(
                      width: 40,
                      child: Transform.scale(
                          scale: 0.6,
                          child: SwitchWidget(
                              value: list[index].enabled,
                              onChanged: (val) {
                                list[index].enabled = val;
                                _refreshScript();
                              }))),
                  const SizedBox(width: 20),
                  Expanded(child: Text(list[index].url, style: const TextStyle(fontSize: 13))),
                ],
              )));
    });
  }

  //点击菜单
  showMenus(TapDownDetails details, int index) {
    setState(() {
      selected = index;
    });
    showContextMenu(context, details.globalPosition, items: [
      PopupMenuItem(
          height: 35,
          child: Text(localizations.edit),
          onTap: () async {
            String script = await (await ScriptManager.instance).getScript(widget.scripts[index]);
            if (!mounted) {
              return;
            }
            showDialog(
                barrierDismissible: false,
                context: context,
                builder: (_) => ScriptEdit(scriptItem: widget.scripts[index], script: script)).then((value) {
              if (value != null) {
                setState(() {});
              }
            });
          }),
      PopupMenuItem(height: 35, child: Text(localizations.export), onTap: () => export(widget.scripts[index])),
      PopupMenuItem(
          height: 35,
          child: widget.scripts[index].enabled ? Text(localizations.disabled) : Text(localizations.enable),
          onTap: () {
            widget.scripts[index].enabled = !widget.scripts[index].enabled;
          }),
      const PopupMenuDivider(),
      PopupMenuItem(
          height: 35,
          child: Text(localizations.delete),
          onTap: () async {
            (await ScriptManager.instance).removeScript(index);
            _refreshScript();
            if (mounted) FlutterToastr.show(localizations.deleteSuccess, context);
          }),
    ]).then((value) {
      setState(() {
        selected = -1;
      });
    });
  }

  //导出js
  export(ScriptItem item) async {
    //文件名称
    String fileName = '${item.name}.json';
    String? saveLocation = await DesktopMultiWindow.invokeMethod(0, 'getSaveLocation', fileName);
    WindowController.fromWindowId(widget.windowId).show();
    if (saveLocation == null) {
      return;
    }
    var json = item.toJson();
    json.remove("scriptPath");
    json['script'] = await (await ScriptManager.instance).getScript(item);
    final XFile xFile = XFile.fromData(utf8.encode(jsonEncode(json)), mimeType: 'json');
    await xFile.saveTo(saveLocation);
    if (mounted) FlutterToastr.show(localizations.exportSuccess, context);
  }
}
