import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'services/api_service.dart';
import 'services/background_update.dart';
import 'services/update_service.dart';
import 'theme/app_theme.dart';
import 'theme/app_colors.dart';
import 'utils/snackbar_service.dart';
import 'widgets/health_banner.dart';
import 'screens/team_detail_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/home_shell.dart';

/// Global navigator key -- used to show dialogs from notification taps.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadThemePreferences();
  await BackgroundUpdateManager.init();
  await BackgroundUpdateManager.syncWithPreference();
  await DownloadManager.instance.initNotifications();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, themeMode, _) {
        return DynamicColorBuilder(
          builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
            return ValueListenableBuilder<bool>(
              valueListenable: dynamicColorNotifier,
              builder: (context, useDynamic, _) {
                final effectiveLight = useDynamic ? lightDynamic : null;
                final effectiveDark = useDynamic ? darkDynamic : null;
                final lightScheme =
                    effectiveLight ??
                    ColorScheme.fromSeed(seedColor: AppColors.seedColor);
                final darkScheme =
                    effectiveDark ??
                    ColorScheme.fromSeed(
                      seedColor: AppColors.seedColor,
                      brightness: Brightness.dark,
                    );
                return MaterialApp(
                  navigatorKey: navigatorKey,
                  title: 'Synapse',
                  debugShowCheckedModeBanner: false,
                  themeMode: themeMode,
                  theme: buildAppTheme(lightScheme),
                  darkTheme: buildAppTheme(darkScheme),
                  builder: (context, child) {
                    final api = ApiService();
                    Widget content = Column(
                      children: [
                        HealthBanner(api: api),
                        Expanded(
                          // Inner ScaffoldMessenger isolates page Scaffolds
                          // so they don't register with the root one.
                          child: ScaffoldMessenger(
                            child: child ?? const SizedBox.shrink(),
                          ),
                        ),
                      ],
                    );
                    if (kDebugMode) {
                      content = Banner(
                        message: 'debug build',
                        location: BannerLocation.topStart,
                        child: content,
                      );
                    }
                    // Root ScaffoldMessenger + Scaffold sits above the
                    // Navigator so its snackbars paint on top of dialogs.
                    return ScaffoldMessenger(
                      key: rootScaffoldMessengerKey,
                      child: Scaffold(body: content),
                    );
                  },
                  home: const HomeShell(),
                  onGenerateRoute: (settings) {
                    if (settings.name == '/settings') {
                      return PageRouteBuilder(
                        pageBuilder: (_, __, ___) => const SettingsScreen(),
                        transitionsBuilder: (_, animation, __, child) {
                          return SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(1, 0),
                              end: Offset.zero,
                            ).animate(CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeInOut,
                            )),
                            child: child,
                          );
                        },
                        transitionDuration: const Duration(milliseconds: 300),
                        reverseTransitionDuration: const Duration(milliseconds: 300),
                      );
                    }
                    if (settings.name != null &&
                        settings.name!.startsWith('/team/')) {
                      final id = int.tryParse(
                        settings.name!.replaceFirst('/team/', ''),
                      );
                      if (id != null) {
                        return MaterialPageRoute(
                          builder: (_) => TeamDetailScreen(teamId: id),
                        );
                      }
                    }
                    return MaterialPageRoute(
                      builder: (_) => const HomeShell(),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}
