import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lcs_new_age/engine/console_widget.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:markdown_widget/markdown_widget.dart';

class ChangelogWidget extends StatefulWidget {
  const ChangelogWidget({super.key});

  static final GlobalKey<ChangelogWidgetState> globalKey =
      GlobalKey<ChangelogWidgetState>();

  @override
  State<ChangelogWidget> createState() => ChangelogWidgetState();
}

class ChangelogWidgetState extends State<ChangelogWidget> {
  String? _content;
  bool showing = false;
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  FocusNode? _previousFocus;

  void show(String content) {
    _previousFocus = FocusManager.instance.primaryFocus;
    setState(() {
      _content = content;
      showing = true;
    });
    _focusNode.requestFocus();
  }

  void hide() {
    setState(() {
      showing = false;
      _content = null;
    });
    _focusNode.unfocus();
    // Return focus to console
    if (_previousFocus?.context != null) {
      _previousFocus!.requestFocus();
    } else {
      (ConsoleWidget.globalKey.currentWidget as ConsoleWidget?)?.requestFocus();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!showing || _content == null) return const SizedBox();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: KeyboardListener(
          focusNode: _focusNode,
          onKeyEvent: (event) {
            if (event is KeyDownEvent || event is KeyRepeatEvent) {
              if (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.escape) {
                hide();
              } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                unawaited(
                  _scrollController.animateTo(
                    _scrollController.offset - 50,
                    duration: const Duration(milliseconds: 100),
                    curve: Curves.easeOut,
                  ),
                );
              } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                unawaited(
                  _scrollController.animateTo(
                    _scrollController.offset + 50,
                    duration: const Duration(milliseconds: 100),
                    curve: Curves.easeOut,
                  ),
                );
              }
            }
          },
          child: Container(
            width: 960,
            height: 720,
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width - 32,
              maxHeight: MediaQuery.sizeOf(context).height - 32,
            ),
            decoration: BoxDecoration(
              color: JournalPalette.page,
              border: Border.all(color: JournalPalette.brass, width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: JournalPalette.inset,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(6),
                      topRight: Radius.circular(6),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          'Campaign changelog',
                          style: TextStyle(
                            color: JournalPalette.ink,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            fontFamily: JournalPalette.serif,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close changelog',
                        icon: const Icon(
                          Icons.close,
                          color: JournalPalette.ink,
                        ),
                        onPressed: hide,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: RawScrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    trackVisibility: true,
                    thickness: 16,
                    radius: const Radius.circular(8),
                    thumbColor: JournalPalette.brassDark,
                    child: GestureDetector(
                      onVerticalDragUpdate: (details) {
                        _scrollController.jumpTo(
                          _scrollController.offset - details.delta.dy,
                        );
                      },
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        child: MarkdownBlock(
                          selectable: true,
                          data: _content!,
                          config: MarkdownConfig.defaultConfig.copy(
                            configs: [
                              const H1Config(),
                              const H2Config(),
                              const H3Config(),
                              MyPConfig(),
                              const MyListConfig(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class H1Config extends HeadingConfig {
  const H1Config({
    this.style = const TextStyle(
      fontFamily: JournalPalette.serif,
      fontSize: 30,
      fontWeight: FontWeight.bold,
      color: JournalPalette.ink,
    ),
  });

  @override
  final TextStyle style;

  @nonVirtual
  @override
  String get tag => MarkdownTag.h1.name;
}

class H2Config extends HeadingConfig {
  const H2Config({
    this.style = const TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.bold,
      color: JournalPalette.ink,
      fontFamily: JournalPalette.serif,
    ),
  });

  @override
  final TextStyle style;

  @nonVirtual
  @override
  String get tag => MarkdownTag.h2.name;
}

class H3Config extends HeadingConfig {
  const H3Config({
    this.style = const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.bold,
      color: JournalPalette.ink,
      fontFamily: JournalPalette.serif,
    ),
  });

  @override
  final TextStyle style;

  @nonVirtual
  @override
  String get tag => MarkdownTag.h3.name;
}

class MyPConfig extends PConfig {
  MyPConfig({
    super.textStyle = const TextStyle(
      fontSize: 16,
      color: JournalPalette.ink,
      fontFamily: JournalPalette.serif,
    ),
  });
}

class MyListConfig extends ListConfig {
  const MyListConfig({super.marker = _defaultMarker});

  static Widget? _defaultMarker(bool isOrdered, int depth, int index) =>
      const Text(
        ' •',
        style: TextStyle(
          color: JournalPalette.ink,
          fontFamily: JournalPalette.serif,
        ),
      );
}
