import 'dart:async';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/services.dart';
import 'design/state_panel.dart';
import 'design/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _start();
}

Future<void> _start() async {
  try {
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
