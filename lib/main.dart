import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/storage.dart';
import 'core/settings_controller.dart';
import 'data/repositories/library_repository.dart';
import 'data/repositories/video_repository.dart';
import 'features/download/download_service.dart';
import 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalStore.init();

  final library = LibraryRepository();
  final video = VideoRepository(library: library);
  final settings = SettingsController();
  final downloads = DownloadService(library: library)..load();
  video.host = settings.host;
  video.configureBypass(
    enabled: settings.bypassEnabled,
    proxyPoolText: settings.proxyPoolText,
    maxAttempts: settings.maxAttempts,
    webviewFallback: settings.webviewFallback,
  );

  // Drop direct-link cache entries whose signed URL already expired (e=).
  // Fire-and-forget: never block startup.
  // ignore: discarded_futures
  video.directLinks.purgeExpired();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsController>.value(value: settings),
        ChangeNotifierProvider<DownloadService>.value(value: downloads),
        Provider<LibraryRepository>.value(value: library),
        Provider<VideoRepository>.value(value: video),
      ],
      child: const P91App(),
    ),
  );
}
