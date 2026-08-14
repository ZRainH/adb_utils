import 'package:flutter/material.dart';

import 'services/app_state.dart';
import 'theme/app_theme.dart';
import 'widgets/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  await state.init();
  runApp(AdbUtilsApp(state: state));
}

class AdbUtilsApp extends StatelessWidget {
  const AdbUtilsApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ADB 桌面工具',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: HomeShell(state: state),
    );
  }
}
