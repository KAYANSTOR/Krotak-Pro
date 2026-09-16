import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
// Full file content is 15KB - if this stub remains, push failed size limit.
class AppContainer {
  AppContainer._();
  static Future<AppContainer> bootstrap({required List templates}) async {
    throw UnimplementedError('app_container_impl incomplete upload');
  }
  void dispose() {}
  Future<void> startBackgroundHandlers() async {}
  final themeModeNotifier = ValueNotifier(ThemeMode.system);
}
