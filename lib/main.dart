import 'dart:async';

import 'package:flutter/material.dart';

import 'application/app_container.dart';
import 'core/result.dart';
import 'domain/entities/message.dart';
import 'domain/entities/setting.dart';
import 'ui/app_scope.dart';
import 'ui/home_shell.dart';
import 'ui/theme/kayan_palette.dart';
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

  // Background integrations must never block the first Flutter frame.
  // A native/platform-service failure should not leave the app on the
  // launcher splash screen. The service can recover/retry independently.
  runApp(NetApp(container: container));
  unawaited(_startBackgroundHandlersSafely(container));
}

Future<void> _startBackgroundHandlersSafely(AppContainer container) async {
  try {
    await container.startBackgroundHandlers();
  } catch (error, stackTrace) {
    debugPrint('Background handler startup failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}

Future<void> _loadThemeMode(AppContainer container) async {
  final result = await container.settings.find(SettingKeys.themeMode);
  final raw = result is Success<AppSetting?> ? result.value?.value : null;
  container.themeModeNotifier.value = ThemeModeCodec.parse(raw);
}

class NetApp extends StatefulWidget {
  const NetApp({super.key, required this.container});
  final AppContainer container;
  @override
  State<NetApp> createState() => _NetAppState();
}

class _NetAppState extends State<NetApp> {
  @override
  void dispose() { widget.container.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AppScope(
    container: widget.container,
    child: ValueListenableBuilder<ThemeMode>(
      valueListenable: widget.container.themeModeNotifier,
      builder: (context, mode, _) => MaterialApp(
        title: 'NET',
        debugShowCheckedModeBanner: false,
        theme: buildKayanLightTheme(),
        darkTheme: buildKayanDarkTheme(),
        themeMode: mode,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        builder: (context, child) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const HomeShell(),
      ),
    ),
  );
}
