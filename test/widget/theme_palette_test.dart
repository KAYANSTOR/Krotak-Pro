import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/ui/theme/kayan_palette.dart';
import 'package:net_app/ui/theme/kayan_theme.dart';
import 'package:net_app/ui/widgets/kayan_bottom_nav.dart';
import 'package:net_app/ui/widgets/settings/settings_cards.dart';

Widget _app({required ThemeMode mode, required Widget child}) {
  return MaterialApp(
    theme: buildKayanLightTheme(),
    darkTheme: buildKayanDarkTheme(),
    themeMode: mode,
    home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: child)),
  );
}

void main() {
  test('ThemeModeCodec parses light dark system', () {
    expect(ThemeModeCodec.parse('light'), ThemeMode.light);
    expect(ThemeModeCodec.parse('dark'), ThemeMode.dark);
    expect(ThemeModeCodec.parse('system'), ThemeMode.system);
    expect(ThemeModeCodec.parse(null), ThemeMode.light);
    expect(ThemeModeCodec.encode(ThemeMode.dark), SettingThemeValues.dark);
  });

  testWidgets('palette follows light brightness', (tester) async {
    late KayanPalette captured;
    await tester.pumpWidget(_app(
      mode: ThemeMode.light,
      child: Builder(builder: (context) {
        captured = KayanPalette.of(context);
        return const SizedBox();
      }),
    ));
    expect(captured.isDark, isFalse);
    expect(captured.textPrimary.computeLuminance(), lessThan(0.5));
    expect(captured.appBackground.computeLuminance(), greaterThan(0.7));
  });

  testWidgets('palette follows dark brightness', (tester) async {
    late KayanPalette captured;
    await tester.pumpWidget(_app(
      mode: ThemeMode.dark,
      child: Builder(builder: (context) {
        captured = KayanPalette.of(context);
        return const SizedBox();
      }),
    ));
    expect(captured.isDark, isTrue);
    expect(captured.textPrimary.computeLuminance(), greaterThan(0.7));
    expect(captured.appBackground.computeLuminance(), lessThan(0.2));
  });

  testWidgets('settings card and bottom nav render in dark mode', (tester) async {
    await tester.pumpWidget(_app(
      mode: ThemeMode.dark,
      child: Column(
        children: [
          const SettingsNavCard(icon: Icons.settings, title: 'اختبار', subtitle: 'وصف'),
          KayanBottomNav(currentId: 'dashboard', onSelect: (_) {}),
        ],
      ),
    ));
    expect(find.text('اختبار'), findsOneWidget);
    expect(find.text('الرئيسية'), findsOneWidget);
  });
}
