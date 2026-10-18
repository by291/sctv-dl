import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../design/state_panel.dart';

Widget routeError(
  BuildContext context,
  String message,
  VoidCallback retry, {
  String returnLocation = '/',
}) => Scaffold(
  appBar: AppBar(
    title: const Text('内容不可用'),
    leading: BackButton(onPressed: () => context.go(returnLocation)),
  ),
  body: StatePanel(title: '暂时无法打开内容', message: message, onAction: retry),
);
