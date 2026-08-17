import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'services/app_state.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'updater/updater_args.dart';
import 'updater/updater_app.dart';
import 'widgets/home_shell.dart';

Future<void> main(List<String> args) async {
  if (UpdaterArgs.isUpdaterMode(args)) {
    await runUpdaterApp(args);
    return;
  }

  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('[FlutterError] ${details.exceptionAsString()}');
      debugPrint('${details.stack}');
    };

    if (Platform.isWindows) {
      await windowManager.ensureInitialized();
      const options = WindowOptions(
        size: Size(1280, 720),
        minimumSize: Size(960, 640),
        center: true,
        // Transparent backgrounds have caused silent native exits on Windows.
        backgroundColor: Color(0xFF121415),
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.hidden,
        title: 'ADB 桌面工具',
      );
      await windowManager.waitUntilReadyToShow(options, () async {
        await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
        await windowManager.show();
        await windowManager.focus();
      });
    }

    final state = AppState();
    await state.init();
    runApp(AdbUtilsApp(state: state));
  }, (error, stack) {
    debugPrint('[ZoneError] $error');
    debugPrint('$stack');
  });
}

class AdbUtilsApp extends StatefulWidget {
  const AdbUtilsApp({super.key, required this.state});

  final AppState state;

  @override
  State<AdbUtilsApp> createState() => _AdbUtilsAppState();
}

class _AdbUtilsAppState extends State<AdbUtilsApp> {
  late ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.state.themeMode;
    widget.state.addListener(_onState);
  }

  @override
  void dispose() {
    widget.state.removeListener(_onState);
    super.dispose();
  }

  void _onState() {
    final next = widget.state.themeMode;
    if (next != _themeMode) {
      setState(() => _themeMode = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ADB 桌面工具',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(brightness: Brightness.light),
      darkTheme: buildAppTheme(brightness: Brightness.dark),
      themeMode: _themeMode,
      builder: (context, child) {
        AppColors.apply(Theme.of(context).brightness);
        return child ?? const SizedBox.shrink();
      },
      home: HomeShell(state: widget.state),
    );
  }
}
