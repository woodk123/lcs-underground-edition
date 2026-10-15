import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lcs_new_age/engine/changelog.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/modern_app.dart';
import 'package:lcs_new_age/title_screen/launch_game.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Keep semantic controls available for keyboard and assistive technology.
  WidgetsBinding.instance.ensureSemantics();
  runApp(const MainApp());
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(launchGame());
  });
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Liberal Crime Squad · New Age',
      debugShowCheckedModeBanner: false,
      theme: buildModernTheme(),
      builder: (context, child) => ValueListenableBuilder<double>(
        valueListenable: journalReadingScale,
        builder: (context, scale, _) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
      home: Scaffold(
        body: Stack(
          children: [
            const ModernGameShell(),
            ChangelogWidget(key: ChangelogWidget.globalKey),
          ],
        ),
      ),
    );
  }
}
