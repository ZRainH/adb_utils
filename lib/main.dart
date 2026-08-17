import 'package:flutter/material.dart';

import 'services/app_state.dart';
import 'theme/app_colors.dart';
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
    return ListenableBuilder(
      listenable: state,
      builder: (context, child) {
        return MaterialApp(
          title: 'ADB 桌面工具',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(brightness: Brightness.light),
          darkTheme: buildAppTheme(brightness: Brightness.dark),
          themeMode: state.themeMode,
          builder: (context, child) {
            AppColors.apply(Theme.of(context).brightness);
            return child ?? const SizedBox.shrink();
          },
          home: child,
        );
      },
      child: HomeShell(state: state),
    );
  }
}
