import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'design/state_panel.dart';
import 'design/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _start();
}

Future<void> _start() async {
  try {
    if (Platform.isIOS) {
      await LiquidGlassWidgets.initialize(enablePerformanceMonitor: false);
    }

    final services = await bootstrapServices();

    runApp(SctvApp(services: services));
  } catch (error) {
    runApp(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: SafeArea(
            child: StatePanel(
              title: '暂时无法启动',
              message: '本机数据初始化失败：$error',
              onAction: () => unawaited(_start()),
            ),
          ),
        ),
      ),
    );
  }
}
