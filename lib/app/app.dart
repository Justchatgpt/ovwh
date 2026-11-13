import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/settings_controller.dart';
import 'theme.dart';
import '../features/shell/root_shell.dart';

class P91App extends StatelessWidget {
  const P91App({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    return MaterialApp(
      title: 'P91 Player',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.themeMode,
      home: const RootShell(),
    );
  }
}
