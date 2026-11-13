import 'package:flutter/services.dart';

/// Minimal iOS-native bridge implemented in `ios/Runner/AppDelegate.swift`.
///
/// Avoids third-party brightness / share plugins entirely: fewer pods, fewer
/// version conflicts, deterministic GitHub Actions builds.
class NativeBridge {
  NativeBridge._();

  static const MethodChannel _channel = MethodChannel('p91/device');

  static double _lastAppBrightness = 1.0;

  /// Set screen brightness in [0.0, 1.0]. No-op on non-iOS / simulator.
  static Future<void> setBrightness(double value) async {
    _lastAppBrightness = (value.clamp(0.0, 1.0) as num).toDouble();
    try {
      await _channel.invokeMethod<void>('setBrightness', {'value': _lastAppBrightness});
    } on MissingPluginException {
      // ignore
    } on PlatformException {
      // ignore
    }
  }

  /// Restore the brightness captured at app launch.
  static Future<void> resetBrightness() async {
    try {
      await _channel.invokeMethod<void>('resetBrightness');
    } on MissingPluginException {
      // ignore
    } on PlatformException {
      // ignore
    }
  }

  /// Show the native iOS share sheet. Falls back to clipboard internally on
  /// the Swift side when no view controller is available.
  static Future<void> share(String text) async {
    try {
      await _channel.invokeMethod<void>('share', {'text': text});
    } on MissingPluginException {
      await Clipboard.setData(ClipboardData(text: text));
    } on PlatformException {
      await Clipboard.setData(ClipboardData(text: text));
    }
  }

  /// Copy text to the system clipboard (pure Flutter, always works).
  static Future<void> copy(String text) =>
      Clipboard.setData(ClipboardData(text: text));
}
