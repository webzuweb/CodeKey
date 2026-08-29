import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'app.dart';
import 'app_logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLogger.instance.initialize();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AppLogger.instance.error(
      'flutter.framework_error',
      details.exception,
      stackTrace: details.stack,
      data: {'library': details.library ?? '', 'context': details.context?.toString() ?? ''},
    );
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.instance.error(
      'flutter.platform_error',
      error,
      stackTrace: stack,
    );
    return true;
  };

  runZonedGuarded(
    () => runApp(const CodeKeyApp()),
    (error, stack) => AppLogger.instance.error(
      'flutter.zone_error',
      error,
      stackTrace: stack,
    ),
  );
}
