import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

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

  // Load the bundled native sqlite3 library before Drift/NativeDatabase is used.
  await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();

  ErrorWidget.builder = (details) => NetRuntimeErrorScreen(details: details);
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint(details.exceptionAsString());
    if (details.stack != null) debugPrintStack(stackTrace: details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught platform error: $error');
    debugPrintStack(stackTrace: stack);
    return true;
  };

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
  AppScope.register(container);
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
  void dispose() {
    AppScope.unregister(widget.container);
    widget.container.dispose();
    super.dispose();
  }

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
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (context, child) => Directionality(
              textDirection: TextDirection.rtl,
              child: child ?? const SizedBox.shrink(),
            ),
            home: const HomeShell(),
          ),
        ),
      );
}

class NetRuntimeErrorScreen extends StatelessWidget {
  const NetRuntimeErrorScreen({super.key, required this.details});
  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        color: const Color(0xFFF8FAFC),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded, size: 56, color: Color(0xFFDC2626)),
                  const SizedBox(height: 16),
                  const Text(
                    'تعذر عرض هذه الشاشة',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Tajawal', fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    details.exceptionAsString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: 'Tajawal', fontSize: 13, height: 1.5),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('العودة', style: TextStyle(fontFamily: 'Tajawal')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
