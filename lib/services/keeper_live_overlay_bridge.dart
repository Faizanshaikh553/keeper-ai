import 'package:flutter/services.dart';

typedef KeeperLiveCaptureHandler = Future<void> Function(
  String imagePath,
  String question,
);

/// Small, isolated bridge to the Android MediaProjection/overlay service.
///
/// Keeper's existing AI, authentication and document flows do not depend on
/// this class. Android owns the screen-capture permission and floating bubble;
/// Dart only receives a user-requested screenshot and returns the AI answer.
class KeeperLiveOverlayBridge {
  KeeperLiveOverlayBridge._();

  static const MethodChannel _channel = MethodChannel(
    'com.faizan.keeperai/keeper_live',
  );

  static KeeperLiveCaptureHandler? _captureHandler;
  static bool _handlerInstalled = false;

  static void setCaptureHandler(KeeperLiveCaptureHandler? handler) {
    _captureHandler = handler;
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method != 'screenCaptured') return;
      final Map<dynamic, dynamic> arguments =
          call.arguments as Map<dynamic, dynamic>? ?? const {};
      final String path = arguments['path']?.toString().trim() ?? '';
      final String question =
          arguments['question']?.toString().trim() ?? '';
      final KeeperLiveCaptureHandler? callback = _captureHandler;
      if (path.isNotEmpty && callback != null) {
        await callback(path, question);
      }
    });
  }

  static Future<bool> start() async {
    try {
      return await _channel.invokeMethod<bool>('startLive') ?? false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stopLive');
    } on PlatformException {
      // The UI can still reset even if Android already stopped the service.
    }
  }

  static Future<bool> isRunning() async {
    try {
      return await _channel.invokeMethod<bool>('isLiveRunning') ?? false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> showStatus(String message) async {
    try {
      await _channel.invokeMethod<void>('showLiveStatus', message);
    } on PlatformException {
      // A capture may finish just after the user stops Live.
    }
  }

  static Future<void> showAnswer(String answer) async {
    try {
      await _channel.invokeMethod<void>('showLiveAnswer', answer);
    } on PlatformException {
      // Keep the answer in the Flutter screen when the overlay was dismissed.
    }
  }

  static Future<bool> openGoogleLens() async {
    try {
      return await _channel.invokeMethod<bool>('openGoogleLens') ?? false;
    } on PlatformException {
      return false;
    }
  }
}
