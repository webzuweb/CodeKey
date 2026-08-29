import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_controller.dart';
import 'controller_scope.dart';
import 'home_page.dart';
import 'localization.dart';
import 'theme.dart';

class CodeKeyApp extends StatefulWidget {
  const CodeKeyApp({super.key});

  @override
  State<CodeKeyApp> createState() => _CodeKeyAppState();
}

class _CodeKeyAppState extends State<CodeKeyApp> {
  late final CodeKeyController controller;

  @override
  void initState() {
    super.initState();
    controller = CodeKeyController();
    controller.initialize();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => CodeKeyScope(
        controller: controller,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'CodeKey AI',
          theme: CodeKeyTheme.dark(),
          locale: Locale(controller.settings.language.name),
          supportedLocales: CodeKeyLocalizations.supportedLocales,
          localizationsDelegates: const [
            CodeKeyLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const HomePage(),
        ),
      ),
    );
  }
}
