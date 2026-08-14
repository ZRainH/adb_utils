import 'package:adb_utils/main.dart';
import 'package:adb_utils/services/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App boots with shell', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = AppState();
    await tester.pumpWidget(AdbUtilsApp(state: state));
    await tester.pump();
    expect(find.text('ADB Desktop Utility'), findsOneWidget);
    expect(find.text('Overview'), findsOneWidget);
  });
}
