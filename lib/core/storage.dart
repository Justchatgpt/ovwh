import 'package:hive_flutter/hive_flutter.dart';

/// Thin wrapper over Hive boxes.
///
/// - favorites / history / downloads / directLinks store JSON strings.
/// - settings stores native primitives (String, double, int, bool), so the
///   box MUST be untyped `Box<dynamic>`: a `Box<String>` would reject
///   `put(key, 1.0)` at compile time. This is intentional.
class LocalStore {
  LocalStore._();

  static const String favoritesBox = 'favorites';
  static const String historyBox = 'history';
  static const String downloadsBox = 'downloads';
  static const String directLinksBox = 'directLinks';
  static const String settingsBox = 'settings';

  static late Box<dynamic> favorites;
  static late Box<dynamic> history;
  static late Box<dynamic> downloads;
  static late Box<dynamic> directLinks;
  static late Box<dynamic> settings;

  static Future<void> init() async {
    await Hive.initFlutter();
    favorites = await Hive.openBox<dynamic>(favoritesBox);
    history = await Hive.openBox<dynamic>(historyBox);
    downloads = await Hive.openBox<dynamic>(downloadsBox);
    directLinks = await Hive.openBox<dynamic>(directLinksBox);
    settings = await Hive.openBox<dynamic>(settingsBox);
  }

  static Future<void> close() => Hive.close();
}
