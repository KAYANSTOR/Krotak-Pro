import 'package:flutter/material.dart';

import 'application/app_container.dart';
import 'core/result.dart';
import 'domain/entities/message.dart';
import 'domain/entities/setting.dart';
import 'ui/app_scope.dart';
import 'ui/home_shell.dart';
import 'ui/theme/kayan_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const defaultTemplates = [
    TransferTemplate(
      id: 'tpl-default',
      name: 'تحويل افتراضي',
      pattern: 'تم تحويل {amount} ريال الى {phone} برقم العملية {ref}',
      isActive: true,
    ),
  ];

  final container = await AppContainer.bootstrap(templates: defaultTemplates);
  await _loadThemeMode(container);
  container.startBackgroundHandlers();

  runApp(NetApp(container: container));
}

Future<void> _loadThemeMode(AppContainer container) async {
  final result = await container.settings.find(SettingKeys.themeMode);
  if (result is Success<AppSetting?>) {
    final value = result.value?.value.trim().toLowerCase();
    if (value == 'dark') {
      container.themeModeNotifier.value = ThemeMode.dark;
    } else {
      // PD-07: light is default (not system).
      container.themeModeNotifier.value = ThemeMode.light;
    }
  }
}

class NetApp extends StatefulWidget {
  const NetApp({super.key, required this.container});

  final AppContainer container;

  @override
  State<NetApp> createState() => _NetAppState();
}

class _NetAppState extends State<NetApp> {
  @override
  void dispose() {
    widget.container.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      container: widget.container,
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: widget.container.themeModeNotifier,
        builder: (context, mode, _) {
          return MaterialApp(
            title: 'NET',
            debugShowCheckedModeBanner: false,
            theme: buildKayanLightTheme(),
            darkTheme: buildKayanDarkTheme(),
            themeMode: mode,
            home: const HomeShell(),
          );
        },
      ),
    );
  }
}
