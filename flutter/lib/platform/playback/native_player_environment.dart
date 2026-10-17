import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/playback/player_environment.dart';

class NativePlayerEnvironment implements PlayerEnvironment {
  static const _channel = MethodChannel(
    'dev.sctvdl.flutter/player_environment',
  );
  @override
  bool get supportsVolumeDrag => Platform.isAndroid;
  @override
  Future<double> brightness() async =>
      (await _channel.invokeMethod<num>('brightness'))!.toDouble();
  @override
  Future<double> beginBrightness() async =>
      (await _channel.invokeMethod<num>('beginBrightness'))!.toDouble();
  @override
  Future<void> setBrightness(double value) =>
      _channel.invokeMethod('setBrightness', value);
  @override
  Future<void> restoreBrightness() =>
      _channel.invokeMethod('restoreBrightness');
  @override
  Future<double> volume() async =>
      (await _channel.invokeMethod<num>('volume'))!.toDouble();
  @override
  Future<void> setVolume(double value) =>
      _channel.invokeMethod('setVolume', value);
  @override
  Future<bool> needsGestureHint() async =>
      await _channel.invokeMethod<bool>('needsGestureHint') ?? false;
  @override
  Future<void> acknowledgeGestureHint() =>
      _channel.invokeMethod('acknowledgeGestureHint');
}

/// iOS requires the public, user-operated system volume control.
class NativeSystemVolume extends StatelessWidget {
  const NativeSystemVolume({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 144,
    height: 48,
    child: UiKitView(viewType: 'dev.sctvdl.flutter/system_volume'),
  );
}
