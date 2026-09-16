import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/setting.dart';
import '../../platform/sms_bridge.dart';
import '../../platform/system_diagnostics_bridge.dart';
import '../app_scope.dart';
import '../theme/kayan_colors.dart';

/// يطلب الصلاحيات الحرجة عند أول تشغيل عبر نوافذ منبثقة متسلسلة.
abstract final class PermissionsOnboarding {
  static const doneKey = 'permissions_onboarding_done_v1';

  static Future<void> maybeRun(BuildContext context) async {
    final c = AppScope.of(context);
    final existing = await c.settings.find(doneKey);
    if (existing is Success<AppSetting?> && existing.value?.value == 'true') {
      return;
    }
    if (!context.mounted) return;
    await _showSequence(context);
    if (!context.mounted) return;
    await c.settings.save(
      AppSetting(key: doneKey, value: 'true', updatedAt: c.clock.now()),
    );
  }

  static Future<void> _showSequence(BuildContext context) async {
    final sms = SmsBridge();
    final diag = SystemDiagnosticsBridge();

    final steps = <_PermStep>[
      _PermStep(
        title: 'صلاحيات الرسائل (SMS)',
        body:
            'يحتاج التطبيق إلى قراءة واستقبال وإرسال رسائل SMS لمعالجة التحويلات تلقائياً وإرسال كروت العملاء.',
        actionLabel: 'موافق — منح الصلاحية',
        onAllow: () async {
          await sms.requestPermissions();
          await diag.requestSmsPermissions();
        },
      ),
      _PermStep(
        title: 'الوصول لإشعارات المحافظ',
        body:
            'لتقاط إشعارات تطبيقات المحافظ (جيب، جوالي، ون كاش…) تلقائياً يُفضّل تفعيل خدمة قراءة الإشعارات.',
        actionLabel: 'موافق — فتح الإعداد',
        onAllow: () => diag.openNotificationAccess(),
      ),
      _PermStep(
        title: 'استثناء تحسين البطارية',
        body:
            'لضمان استمرار الخدمة في الخلفية دون توقف عند قفل الشاشة، امنح استثناء تحسين البطارية للتطبيق.',
        actionLabel: 'موافق — فتح الإعداد',
        onAllow: () => diag.openBatteryOptimization(),
      ),
    ];

    for (final step in steps) {
      if (!context.mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              step.title,
              style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800),
            ),
            content: Text(
              step.body,
              style: const TextStyle(fontFamily: 'Tajawal', height: 1.5),
            ),
            actionsAlignment: MainAxisAlignment.spaceBetween,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('لاحقاً', style: TextStyle(fontFamily: 'Tajawal')),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: KayanColors.primary),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(step.actionLabel, style: const TextStyle(fontFamily: 'Tajawal')),
              ),
            ],
          ),
        ),
      );
      if (ok == true) {
        try {
          await step.onAllow();
        } catch (_) {}
      }
    }
  }
}

class _PermStep {
  const _PermStep({
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAllow,
  });
  final String title;
  final String body;
  final String actionLabel;
  final Future<void> Function() onAllow;
}
