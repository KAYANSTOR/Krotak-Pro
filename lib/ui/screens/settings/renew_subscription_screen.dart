import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/license.dart';
import '../../app_scope.dart';
import '../../theme/kayan_palette.dart';
import '../../theme/net_semantic_colors.dart';
import '../../theme/net_tokens.dart';
import '../../widgets/async_views.dart';
import '../../widgets/net/net_surface_card.dart';

class RenewSubscriptionScreen extends StatefulWidget {
  const RenewSubscriptionScreen({super.key});

  @override
  State<RenewSubscriptionScreen> createState() => _RenewSubscriptionScreenState();
}

class _RenewSubscriptionScreenState extends State<RenewSubscriptionScreen> {
  bool _loading = true;
  String? _current;
  String? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final r = await AppScope.of(context).licenseService.current();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r is Success<License>) {
        _current = '${r.value.status.name} · ينتهي ${r.value.expiresAt}';
      } else {
        _current = (r as Failure).error.message;
      }
    });
  }

  Future<void> _extend(int days) async {
    setState(() {
      _busy = true;
      _status = null;
    });
    final c = AppScope.of(context);
    final r = await c.licenseService.activateOffline(
      licenseId: c.ids.next('lic'),
      expiresAt: c.clock.now().add(Duration(days: days)),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = r is Success<License>
          ? 'تم التجديد حتى ${r.value.expiresAt}'
          : (r as Failure).error.message;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تجديد الاشتراك')),
      body: _loading
          ? const AsyncLoadingView(skeleton: true, skeletonCount: 3)
          : ListView(
              padding: NetSpacing.screen,
              children: [
                NetSurfaceCard(
                  borderColor: context.netColors.premium.withValues(alpha: 0.45),
                  child: Row(
                    children: [
                      Icon(
                        Icons.workspace_premium_rounded,
                        size: 20,
                        color: context.netColors.premium,
                      ),
                      const SizedBox(width: NetSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'حالة الترخيص',
                              style: TextStyle(
                                fontFamily: NetTypography.family,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: KayanPalette.of(context).textPrimary,
                              ),
                            ),
                            const SizedBox(height: NetSpacing.xxs),
                            Text(
                              _current ?? '—',
                              style: TextStyle(
                                fontFamily: NetTypography.family,
                                fontSize: 12.5,
                                height: 1.4,
                                color: KayanPalette.of(context).textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: NetSpacing.lg),
                FilledButton(
                  onPressed: _busy ? null : () => _extend(30),
                  child: const Text('تجديد 30 يومًا (محلي)'),
                ),
                const SizedBox(height: NetSpacing.sm),
                OutlinedButton(
                  onPressed: _busy ? null : () => _extend(365),
                  child: const Text('تجديد سنة (محلي)'),
                ),
                if (_status != null) ...[
                  const SizedBox(height: NetSpacing.md),
                  NetSurfaceCard(
                    child: Text(
                      _status!,
                      style: TextStyle(
                        fontFamily: NetTypography.family,
                        fontSize: 13,
                        height: 1.4,
                        color: KayanPalette.of(context).textPrimary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
