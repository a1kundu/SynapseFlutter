import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/background_update.dart';
import 'services/chat_controller.dart';
import 'services/chat_storage.dart';
import 'services/memory_service.dart';
import 'services/update_service.dart';
import 'settings/settings_repository.dart';
import 'theme/app_theme.dart';
import 'theme/app_colors.dart';
import 'utils/snackbar_service.dart';
import 'screens/settings_screen.dart';
import 'screens/home_shell.dart';

/// PR number injected at build time via --dart-define=PR_NUMBER=...
const _prNumber = String.fromEnvironment('PR_NUMBER', defaultValue: '');

/// Global navigator key -- used to show dialogs from notification taps.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
  ));
  await SettingsRepository.instance.init();
  await ChatStorage.instance.init();
  await MemoryService.instance.init();
  await loadThemePreferences();
  try {
    await BackgroundUpdateManager.init();
    await BackgroundUpdateManager.syncWithPreference();
    await DownloadManager.instance.initNotifications();
  } catch (e, s) {
    debugPrint('Non-critical init failed: $e\n$s');
  }
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static const _shortcutChannel =
      MethodChannel('in.arijitk.synapse_flutter/shortcuts');

  @override
  void initState() {
    super.initState();
    _shortcutChannel.setMethodCallHandler(_handleShortcut);
  }

  Future<dynamic> _handleShortcut(MethodCall call) async {
    if (call.method != 'shortcutAction') return;
    final action = call.arguments as String?;
    // Wait briefly so the navigator is ready after a cold start.
    await Future.delayed(const Duration(milliseconds: 400));
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;

    switch (action) {
      case 'check_update':
        _triggerUpdateCheck(ctx);
        break;
      case 'open_settings':
        navigatorKey.currentState?.pushNamed('/settings');
        break;
    }
  }

  void _triggerUpdateCheck(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator()),
      ),
    );

    final update = await UpdateService.checkForUpdate();

    if (!context.mounted) return;
    Navigator.of(context).pop();

    if (update != null) {
      showUpdateDialog(context, update);
    } else {
      showRootSnackBar(
        const SnackBar(content: Text('You\'re already on the latest version.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ChatController(),
      child: ValueListenableBuilder<ThemeMode>(
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
                      Widget content = ScaffoldMessenger(
                        child: child ?? const SizedBox.shrink(),
                      );
                      if (kDebugMode) {
                        content = Banner(
                          message: 'debug build',
                          location: BannerLocation.topStart,
                          child: content,
                        );
                      } else if (_prNumber.isNotEmpty) {
                        content = Banner(
                          message: 'PR #$_prNumber',
                          location: BannerLocation.topStart,
                          color: Colors.blue,
                          child: content,
                        );
                      }
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
                              position:
                                  Tween<Offset>(
                                    begin: const Offset(1, 0),
                                    end: Offset.zero,
                                  ).animate(
                                    CurvedAnimation(
                                      parent: animation,
                                      curve: Curves.easeInOut,
                                    ),
                                  ),
                              child: child,
                            );
                          },
                          transitionDuration: const Duration(milliseconds: 300),
                          reverseTransitionDuration: const Duration(
                            milliseconds: 300,
                          ),
                        );
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
      ),
    );
  }
}
