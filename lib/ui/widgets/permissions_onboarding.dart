import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/result.dart';
import '../../domain/entities/setting.dart';
import '../../platform/system_diagnostics_bridge.dart';
import '../app_scope.dart';
import '../theme/kayan_colors.dart';

/// يطلب كل الصلاحيات الحرجة عند أول دخول — منطق كامل بـ Dart عبر permission_handler.
/// فتح إعدادات النظام (إشعارات المحافظ / البطارية) يستخدم الجسر الموجود فقط.
abstract final class PermissionsOnboarding {
  /// ارفع الإصدار عند تغيير الخطوات لإعادة العرض للمستخدمين الحاليين.
  static const doneKey = 'permissions_onboarding_done_v4';

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
    final diag = SystemDiagnosticsBridge();

    final steps = <_PermStep>[
      _PermStep(
        title: 'صلاحيات الرسائل (SMS)',
        body:
            'يحتاج التطبيق إلى قراءة واستقبال وإرسال رسائل SMS لمعالجة التحويلات تلقائياً وإرسال كروت العملاء.',
        actionLabel: 'موافق — منح الصلاحية',
        onAllow: () async {
          // طلب صلاحيات SMS بالكامل عبر permission_handler (Dart)
          await [
            Permission.sms,
            Permission.phone, // يساعد بعض الأجهزة على وصول SMS
          ].request();
        },
      ),
      _PermStep(
        title: 'إشعارات التطبيق',
        body:
            'للتنبيه عند الرسائل المعلّقة والتنبيهات التشغيلية يحتاج التطبيق إذن عرض الإشعارات.',
        actionLabel: 'موافق — منح الصلاحية',
        onAllow: () async {
          // POST_NOTIFICATIONS على Android 13+ عبر permission_handler
          await Permission.notification.request();
        },
      ),
      _PermStep(
        title: 'الوصول لإشعارات المحافظ',
        body:
            'لتقاط إشعارات تطبيقات المحافظ (جيب، جوالي، ون كاش، فلوسك) تلقائياً يجب تفعيل خدمة قراءة الإشعارات من إعدادات النظام.',
        actionLabel: 'موافق — فتح الإعداد',
        onAllow: () => diag.openNotificationAccess(),
      ),
      _PermStep(
        title: 'استثناء تحسين البطارية',
        body:
            'لضمان استمرار الخدمة في الخلفية دون توقف عند قفل الشاشة، امنح استثناء تحسين البطارية لهذا التطبيق.',
        actionLabel: 'موافق — فتح الإعداد',
        onAllow: () => diag.openBatteryOptimization(),
      ),
      _PermStep(
        title: 'حالة الهاتف (اختياري)',
        body:
            'يُستخدم لمعرفة حالة الشبكة والشرائح عند تشخيص النظام. يمكنك التخطي إن رغبت.',
        actionLabel: 'موافق',
        onAllow: () async {
          await Permission.phone.request();
        },
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
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              step.title,
              style: const TextStyle(
                fontFamily: 'Tajawal',
                fontWeight: FontWeight.w800,
                color: KayanColors.textPrimary,
              ),
            ),
            content: Text(
              step.body,
              style: const TextStyle(
                fontFamily: 'Tajawal',
                height: 1.5,
                color: KayanColors.textSecondary,
              ),
            ),
            actionsAlignment: MainAxisAlignment.spaceBetween,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  'لاحقاً',
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    color: KayanColors.textSecondary,
                  ),
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: KayanColors.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  step.actionLabel,
                  style: const TextStyle(
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.w700,
                  ),
                ),
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
