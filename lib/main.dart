import 'package:flutter/material.dart';
import 'package:random_movie/app.dart';
import 'package:random_movie/services/app_error_log.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 先装错误边界，再跑应用：这样启动期间的异常也能被记下来。
  AppErrorLog.install();
  runApp(const MyApp());
}
