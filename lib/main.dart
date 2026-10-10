import 'package:fitgirl_mobile_flutter/core/layout/responsive.dart';
import 'package:fitgirl_mobile_flutter/core/theme/app_theme.dart';
import 'package:fitgirl_mobile_flutter/router.dart';
import 'package:fitgirl_mobile_flutter/services/download_service.dart';
import 'package:fitgirl_mobile_flutter/services/notification_service.dart';
import 'package:fitgirl_mobile_flutter/widgets/update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  void openDownloads() => router.go('/downloads');
  DownloadService().onOpenDownloads = openDownloads;
  NotificationService().onTap = openDownloads;
  await DownloadService().initialize();

  runApp(const ProviderScope(child: MyApp()));

  // Look for an app update once the UI is up.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Future.delayed(
      const Duration(seconds: 3),
      () => promptForUpdateOnStartup(rootNavigatorKey),
    );
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'FitGirl Downloader',
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      routerConfig: router,
      scrollBehavior: const AppScrollBehavior(),
      debugShowCheckedModeBanner: false,
    );
  }
}
