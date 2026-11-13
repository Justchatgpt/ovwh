import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/storage.dart';

/// App-wide settings backed by the Hive `settings` box.
class SettingsController extends ChangeNotifier {
  static const _kHost = 'host';
  static const _kSpeed = 'defaultSpeed';
  static const _kTheme = 'themeMode';
  static const _kAutoPlay = 'autoPlay';
  static const _kLandscape = 'autoLandscape';
  static const _kBypass = 'bypassEnabled';
  static const _kProxyPool = 'proxyPool';
  static const _kMaxAttempts = 'maxAttempts';
  static const _kWebviewFallback = 'webviewFallback';

  SettingsController() {
    _host = (LocalStore.settings.get(_kHost, defaultValue: ApiConstants.defaultHost) ??
        ApiConstants.defaultHost) as String;
    _speed = ((LocalStore.settings.get(_kSpeed, defaultValue: 1.0) ?? 1.0) as num).toDouble();
    _themeMode = ThemeMode.values[
        ((LocalStore.settings.get(_kTheme, defaultValue: 2) ?? 2) as num).toInt()];
    _autoPlay = (LocalStore.settings.get(_kAutoPlay, defaultValue: true) ?? true) as bool;
    _autoLandscape =
        (LocalStore.settings.get(_kLandscape, defaultValue: true) ?? true) as bool;
    _bypassEnabled =
        (LocalStore.settings.get(_kBypass, defaultValue: true) ?? true) as bool;
    _proxyPoolText = (LocalStore.settings.get(_kProxyPool, defaultValue: '') ?? '') as String;
    _maxAttempts = ((LocalStore.settings.get(_kMaxAttempts, defaultValue: 8) ?? 8) as num).toInt();
    _webviewFallback =
        (LocalStore.settings.get(_kWebviewFallback, defaultValue: true) ?? true) as bool;
  }

  late String _host;
  late double _speed;
  late ThemeMode _themeMode;
  late bool _autoPlay;
  late bool _autoLandscape;
  late bool _bypassEnabled;
  late String _proxyPoolText;
  late int _maxAttempts;
  late bool _webviewFallback;

  String get host => _host;
  double get defaultSpeed => _speed;
  ThemeMode get themeMode => _themeMode;
  bool get autoPlay => _autoPlay;
  bool get autoLandscape => _autoLandscape;

  /// Daily-10 bypass toggle.
  bool get bypassEnabled => _bypassEnabled;

  /// Raw multi-line proxy list (host:port per line) used for real-IP rotation.
  String get proxyPoolText => _proxyPoolText;

  /// How many fingerprint/proxy attempts the resolver makes per play.
  int get maxAttempts => _maxAttempts;

  /// Use a hidden WKWebView to pass mirror anti-bot JS challenges.
  bool get webviewFallback => _webviewFallback;

  Future<void> setHost(String value) async {
    _host = value.trim();
    await LocalStore.settings.put(_kHost, _host);
    notifyListeners();
  }

  Future<void> setDefaultSpeed(double value) async {
    _speed = value;
    await LocalStore.settings.put(_kSpeed, value);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await LocalStore.settings.put(_kTheme, mode.index);
    notifyListeners();
  }

  Future<void> setAutoPlay(bool value) async {
    _autoPlay = value;
    await LocalStore.settings.put(_kAutoPlay, value);
    notifyListeners();
  }

  Future<void> setAutoLandscape(bool value) async {
    _autoLandscape = value;
    await LocalStore.settings.put(_kLandscape, value);
    notifyListeners();
  }

  Future<void> setBypassEnabled(bool value) async {
    _bypassEnabled = value;
    await LocalStore.settings.put(_kBypass, value);
    notifyListeners();
  }

  Future<void> setProxyPoolText(String value) async {
    _proxyPoolText = value;
    await LocalStore.settings.put(_kProxyPool, value);
    notifyListeners();
  }

  Future<void> setMaxAttempts(int value) async {
    _maxAttempts = (value.clamp(1, 20) as num).toInt();
    await LocalStore.settings.put(_kMaxAttempts, _maxAttempts);
    notifyListeners();
  }

  Future<void> setWebviewFallback(bool value) async {
    _webviewFallback = value;
    await LocalStore.settings.put(_kWebviewFallback, value);
    notifyListeners();
  }
}
