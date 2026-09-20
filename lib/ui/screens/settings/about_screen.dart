import 'package:flutter/material.dart';

import '../../../core/app_brand.dart';
import '../../theme/kayan_palette.dart';
import '../../theme/net_semantic_colors.dart';
import '../../theme/net_tokens.dart';
import '../../widgets/net/net_surface_card.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final net = context.netColors;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('عن التطبيق')),
        body: ListView(
          padding: NetSpacing.screen,
          children: [
            NetSurfaceCard(
              padding: const EdgeInsets.symmetric(
                horizontal: NetSpacing.lg,
                vertical: NetSpacing.xl,
              ),
              child: Column(
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(NetRadii.xl),
                      border: Border.all(
                        color: palette.primary.withValues(alpha: 0.28),
                      ),
                      boxShadow: NetElevation.glow(palette.primary, opacity: 0.18),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.asset(
                      'assets/icon/app_icon.png',
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: palette.surfaceVariant,
                        alignment: Alignment.center,
                        child: Icon(Icons.style_rounded, color: palette.primary, size: 40),
                      ),
                    ),
                  ),
                  const SizedBox(height: NetSpacing.md),
                  Text(
                    AppBrand.name,
                    style: TextStyle(
                      fontFamily: NetTypography.family,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: NetSpacing.xxs),
                  Text(
                    'الإصدار ${AppBrand.version} (${AppBrand.buildNumber})',
                    style: TextStyle(
                      fontFamily: NetTypography.family,
                      fontSize: 12.5,
                      color: palette.textTertiary,
                    ),
                  ),
                  const SizedBox(height: NetSpacing.md),
                  Container(
                    width: 42,
                    height: 3,
                    decoration: BoxDecoration(
                      color: net.premium,
                      borderRadius: NetRadii.pillAll,
                    ),
                  ),
                  const SizedBox(height: NetSpacing.md),
                  Text(
                    AppBrand.description,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: NetTypography.family,
                      fontSize: 13,
                      height: 1.6,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: NetSpacing.lg),
            NetSurfaceCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _AboutRow(
                    icon: Icons.code_rounded,
                    label: 'المبرمج',
                    value: AppBrand.developer,
                  ),
                  const _AboutDivider(),
                  _AboutRow(
                    icon: Icons.business_rounded,
                    label: 'الجهة',
                    value: AppBrand.company,
                  ),
                  const _AboutDivider(),
                  _AboutRow(
                    icon: Icons.language_rounded,
                    label: 'الموقع',
                    value: AppBrand.website,
                    ltr: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: NetSpacing.lg),
            NetSurfaceCard(
              padding: const EdgeInsets.all(NetSpacing.lg),
              child: Column(
                children: [
                  Icon(Icons.copyright_rounded, size: 20, color: palette.textTertiary),
                  const SizedBox(height: NetSpacing.sm),
                  Text(
                    'جميع الحقوق محفوظة © ${AppBrand.company}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: NetTypography.family,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: NetSpacing.xxs),
                  Text(
                    AppBrand.website,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      fontFamily: NetTypography.family,
                      fontSize: 12.5,
                      color: palette.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({
    required this.icon,
    required this.label,
    required this.value,
    this.ltr = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return ListTile(
      contentPadding: NetSpacing.row,
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: palette.iconBadgeBackground,
          borderRadius: NetRadii.smAll,
        ),
        child: Icon(icon, size: 19, color: palette.primary),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontFamily: NetTypography.family,
          fontSize: 12.5,
          color: palette.textTertiary,
        ),
      ),
      subtitle: Text(
        value,
        textDirection: ltr ? TextDirection.ltr : TextDirection.rtl,
        textAlign: TextAlign.right,
        style: TextStyle(
          fontFamily: NetTypography.family,
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
          color: palette.textPrimary,
        ),
      ),
    );
  }
}

class _AboutDivider extends StatelessWidget {
  const _AboutDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: NetSpacing.lg,
      endIndent: NetSpacing.lg,
      color: KayanPalette.of(context).border,
    );
  }
}
