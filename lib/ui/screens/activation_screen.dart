import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/license.dart';
import '../app_scope.dart';
import '../theme/kayan_palette.dart';
import '../theme/net_tokens.dart';
import '../widgets/async_views.dart';
import '../widgets/net/net_app_bar_title.dart';
import '../widgets/net/net_surface_card.dart';

class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final _idCtrl = TextEditingController();
  bool _busy = false;
  String? _status;

  @override
  void dispose() {
    _idCtrl.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    final c = AppScope.of(context);
    final id = _idCtrl.text.trim().isEmpty ? c.ids.next('lic') : _idCtrl.text.trim();
    final r = await c.licenseService.activateOffline(
      licenseId: id,
      expiresAt: c.clock.now().add(const Duration(days: 30)),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = r is Success<License>
          ? 'مفعّل: ${r.value.id} حتى ${r.value.expiresAt}'
          : (r as Failure).error.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const NetAppBarTitle(
          icon: Icons.verified_user_outlined,
          title: 'تفعيل الترخيص',
        ),
      ),
      body: ListView(
        padding: NetSpacing.screen,
        children: [
          NetInlineNotice(
            message:
                'التفعيل محلي (offline-first). التحقق عبر الإنترنت اختياري وغير مربوط بخادم حاليًا.',
            icon: Icons.wifi_off_rounded,
          ),
          const SizedBox(height: NetSpacing.lg),
          NetSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _idCtrl,
                  decoration: const InputDecoration(
                    labelText: 'معرّف الترخيص (اختياري)',
                  ),
                ),
                const SizedBox(height: NetSpacing.lg),
                FilledButton(
                  onPressed: _busy ? null : _activate,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('تفعيل 30 يومًا'),
                ),
              ],
            ),
          ),
          if (_status != null) ...[
            const SizedBox(height: NetSpacing.md),
            NetSurfaceCard(
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: palette.textSecondary,
                  ),
                  const SizedBox(width: NetSpacing.sm),
                  Expanded(
                    child: Text(
                      _status!,
                      style: TextStyle(
                        fontFamily: NetTypography.family,
                        fontSize: 13,
                        height: 1.4,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
