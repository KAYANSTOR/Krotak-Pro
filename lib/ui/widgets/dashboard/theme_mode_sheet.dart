import 'package:flutter/material.dart';

import '../../theme/kayan_palette.dart';
import '../../theme/net_semantic_colors.dart';
import '../../theme/net_theme_schedule.dart';
import '../../theme/net_tokens.dart';
import '../net/net_sheet.dart';

/// ورقة اختيار المظهر: نهار / ليل / تلقائي — بمعاينات مصغّرة لألوان الهوية.
///
/// لا تُطبّق أي تغيير بنفسها: تعيد الوضع المختار للشاشة التي حفظته.
class ThemeModeSheet extends StatelessWidget {
  const ThemeModeSheet({super.key, required this.current});

  final NetThemeMode current;

  static Future<NetThemeMode?> show(BuildContext context, NetThemeMode current) {
    return NetSheet.show<NetThemeMode>(
      context,
      builder: (_) => ThemeModeSheet(current: current),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final options = NetThemeMode.values;
    return NetSheet(
      title: 'اختيار المظهر',
      subtitle: 'النهار فاتح من 7 صباحًا إلى 7 مساءً — والليل داكن تلقائيًا',
      icon: Icons.dark_mode_rounded,
      showClose: false,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          NetSpacing.xl,
          NetSpacing.lg,
          NetSpacing.xl,
          NetSpacing.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < options.length; i++) ...[
              if (i > 0) const SizedBox(width: NetSpacing.md),
              Expanded(
                child: _ThemeOptionCard(
                  mode: options[i],
                  selected: current == options[i],
                ),
              ),
            ],
          ],
        ),
      ),
      footer: Text(
        'يُطبَّق الاختيار فورًا على كل شاشات التطبيق',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: NetTypography.family,
          fontSize: 12,
          color: palette.textTertiary,
        ),
      ),
    );
  }
}

class _ThemeOptionCard extends StatelessWidget {
  const _ThemeOptionCard({required this.mode, required this.selected});

  final NetThemeMode mode;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return InkWell(
      borderRadius: NetRadii.lgAll,
      onTap: () => Navigator.of(context).pop(mode),
      child: Container(
        padding: const EdgeInsets.all(NetSpacing.md),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: NetRadii.lgAll,
          border: Border.all(
            color: selected ? palette.primary : palette.border,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              NetThemeSchedule.label(mode),
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: selected ? palette.primary : palette.textPrimary,
              ),
            ),
            const SizedBox(height: NetSpacing.md),
            _ThemePreview(mode: mode),
            const SizedBox(height: NetSpacing.md),
            Icon(
              selected ? Icons.check_circle_rounded : Icons.radio_button_off_rounded,
              size: 22,
              color: selected ? palette.primary : palette.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

/// معاينة مصغّرة مبنيّة على ألوان الهوية للوضعَين — والتلقائي يقسّم الوجه.
class _ThemePreview extends StatelessWidget {
  const _ThemePreview({required this.mode});

  final NetThemeMode mode;

  @override
  Widget build(BuildContext context) {
    final dark = KayanPalette.dark;
    final light = KayanPalette.light;
    final net = context.netColors;

    Widget face(KayanPalette p) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 5,
              width: 26,
              margin: const EdgeInsets.only(bottom: 5),
              decoration: BoxDecoration(
                color: p.border,
                borderRadius: NetRadii.pillAll,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: p.border,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 3),
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: p.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Container(
              width: 34,
              height: 24,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: AlignmentDirectional.topStart,
                  end: AlignmentDirectional.bottomEnd,
                  colors: [p.primary, net.balanceGradientEnd],
                ),
                borderRadius: NetRadii.xsAll,
              ),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 14,
                      height: 3,
                      decoration: BoxDecoration(
                        color: p.onPrimary.withValues(alpha: 0.9),
                        borderRadius: NetRadii.pillAll,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      width: 9,
                      height: 3,
                      decoration: BoxDecoration(
                        color: p.onPrimary.withValues(alpha: 0.6),
                        borderRadius: NetRadii.pillAll,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 3),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: p.surfaceVariant,
                      borderRadius: NetRadii.xsAll,
                    ),
                  ),
                ],
              ],
            ),
          ],
        );

    final body = switch (mode) {
      NetThemeMode.light => face(light),
      NetThemeMode.dark => face(dark),
      NetThemeMode.auto => Row(
          children: [
            Expanded(child: face(light)),
            Expanded(child: face(dark)),
          ],
        ),
    };

    return Container(
      height: 108,
      decoration: BoxDecoration(
        color: mode == NetThemeMode.dark
            ? dark.appBackground
            : light.appBackground,
        borderRadius: NetRadii.mdAll,
        border: Border.all(
          color: mode == NetThemeMode.dark ? dark.border : light.border,
        ),
      ),
      padding: const EdgeInsets.all(NetSpacing.sm),
      alignment: Alignment.center,
      child: body,
    );
  }
}
