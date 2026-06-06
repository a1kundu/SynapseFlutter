import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/background_update.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import '../widgets/section_header.dart';
import '../widgets/icon_box.dart';
import '../utils/snackbar_service.dart';
import '../version.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _autoUpdate = true;

  @override
  void initState() {
    super.initState();
    _loadAutoUpdatePref();
  }

  Future<void> _loadAutoUpdatePref() async {
    final enabled = await UpdateService.isAutoUpdateEnabled();
    if (mounted) setState(() => _autoUpdate = enabled);
  }

  Future<void> _toggleAutoUpdate(bool value) async {
    setState(() => _autoUpdate = value);
    await UpdateService.setAutoUpdateEnabled(value);
    await BackgroundUpdateManager.syncWithPreference();
  }

  static Future<void> _checkForUpdate(BuildContext context) async {
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
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ValueListenableBuilder<ThemeMode>(
        valueListenable: themeNotifier,
        builder: (context, mode, _) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
                children: [
                  // App logo, name, and info
                  Padding(
                    padding: const EdgeInsets.only(bottom: 32),
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Image.asset(
                            'assets/icons/icon-128x128.png',
                            width: 80,
                            height: 80,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Synapse',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          appVersion == 'APP_VERSION_PLACEHOLDER'
                              ? 'dev (${UpdateService.channel})'
                              : 'v$appVersion (${UpdateService.channel})',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 2),
                      ],
                    ),
                  ),
                  // Appearance section
                  const SectionHeader(title: 'Appearance'),
                  Card(
                    child: Column(
                      children: [
                        _ThemeTile(
                          icon: Icons.brightness_auto,
                          title: 'System',
                          subtitle: 'Follow device theme',
                          selected: mode == ThemeMode.system,
                          onTap: () => setThemeMode(ThemeMode.system),
                        ),
                        _ThemeTile(
                          icon: Icons.light_mode,
                          title: 'Light',
                          subtitle: 'Always use light theme',
                          selected: mode == ThemeMode.light,
                          onTap: () => setThemeMode(ThemeMode.light),
                        ),
                        _ThemeTile(
                          icon: Icons.dark_mode,
                          title: 'Dark',
                          subtitle: 'Always use dark theme',
                          selected: mode == ThemeMode.dark,
                          onTap: () => setThemeMode(ThemeMode.dark),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: ValueListenableBuilder<bool>(
                      valueListenable: dynamicColorNotifier,
                      builder: (context, useDynamic, _) {
                        return SwitchListTile(
                          secondary: IconBox(
                            icon: Icons.palette,
                            colorScheme: cs,
                          ),
                          title: const Text('Dynamic color'),
                          subtitle: const Text(
                            'Use wallpaper colors (Android 12+)',
                          ),
                          value: useDynamic,
                          onChanged: (v) => setDynamicColor(v),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Updates section (Android only)
                  if (!kIsWeb) ...[
                    const SectionHeader(title: 'Updates'),
                    Card(
                      child: Column(
                        children: [
                          SwitchListTile(
                            secondary: IconBox(
                              icon: Icons.update,
                              colorScheme: cs,
                            ),
                            title: const Text('Automatic update check'),
                            subtitle: const Text(
                              'Check for updates when the app opens or using background updates.',
                            ),
                            value: _autoUpdate,
                            onChanged: _toggleAutoUpdate,
                          ),
                          ListTile(
                            leading: IconBox(
                              icon: Icons.system_update,
                              colorScheme: cs,
                            ),
                            title: const Text('Check for updates'),
                            subtitle: Text('Channel: ${UpdateService.channel}'),
                            trailing: Icon(
                              Icons.chevron_right,
                              color: cs.onSurfaceVariant,
                            ),
                            onTap: () => _checkForUpdate(context),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  // GitHub section
                  const SectionHeader(title: 'GitHub'),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: IconBox(icon: Icons.source, colorScheme: cs),
                          title: const Text('Source Code'),
                          subtitle: const Text('arklnd/synapse'),
                          trailing: Icon(
                            Icons.open_in_new,
                            color: cs.onSurfaceVariant,
                          ),
                          onTap: () => launchUrl(
                            Uri.parse(
                              'https://github.com/arklnd/synapse',
                            ),
                            mode: LaunchMode.externalApplication,
                          ),
                        ),
                        ListTile(
                          leading: IconBox(
                            icon: Icons.bug_report,
                            colorScheme: cs,
                          ),
                          title: const Text('Report an Issue'),
                          subtitle: const Text('Bugs & feature requests'),
                          trailing: Icon(
                            Icons.open_in_new,
                            color: cs.onSurfaceVariant,
                          ),
                          onTap: () => launchUrl(
                            Uri.parse(
                              'https://github.com/arklnd/synapse/issues',
                            ),
                            mode: LaunchMode.externalApplication,
                          ),
                        ),
                        ListTile(
                          leading: IconBox(
                            icon: Icons.new_releases_outlined,
                            colorScheme: cs,
                          ),
                          title: const Text('Releases'),
                          subtitle: const Text('Download latest versions'),
                          trailing: Icon(
                            Icons.open_in_new,
                            color: cs.onSurfaceVariant,
                          ),
                          onTap: () => launchUrl(
                            Uri.parse(
                              'https://github.com/arklnd/synapse/releases',
                            ),
                            mode: LaunchMode.externalApplication,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
          size: 22,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          color: selected ? cs.primary : null,
        ),
      ),
      subtitle: Text(subtitle),
      trailing: selected
          ? Icon(Icons.check_circle, color: cs.primary)
          : const SizedBox.shrink(),
      onTap: onTap,
    );
  }
}
