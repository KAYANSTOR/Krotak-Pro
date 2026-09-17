import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/result.dart';
import '../../domain/entities/setting.dart';
import '../../platform/system_diagnostics_bridge.dart';
import '../app_scope.dart';
import '../theme/kayan_colors.dart';

/// بوابة تهيئة إلزامية: لا تُسجّل كمكتملة إلا بعد تحقق أندرويد من جميع المتطلبات.
abstract final class PermissionsOnboarding {
  /// تغيير الإصدار يعيد التحقق بعد تحديث متطلبات الصلاحيات.
  static const doneKey = 'permissions_onboarding_done_v5';

  static Future<void> maybeRun(BuildContext context) async {
    final c = AppScope.of(context);
    final diag = SystemDiagnosticsBridge();
    final existing = await c.settings.find(doneKey);
    final alreadyDone = existing is Success<AppSetting?> &&
        existing.value?.value == 'true';

    // لا نعتمد على العلم وحده: إذا تغيّرت صلاحية نظامية بعد ذلك يجب إعادة الطلب/التحقق.
    if (alreadyDone && await _allRequirementsMet(diag)) return;
    if (!context.mounted) return;

    final complete = await _showSequence(context, diag);
    if (!complete || !context.mounted) return;

    await c.settings.save(
      AppSetting(key: doneKey, value: 'true', updatedAt: c.clock.now()),
    );
  }

  static Future<bool> _allRequirementsMet(SystemDiagnosticsBridge diag) async {
    final sms = await Permission.sms.status;
    final phone = await Permission.phone.status;
    final notifications = await Permission.notification.status;
    final probe = await diag.probe();

    final smsOk = sms.isGranted && phone.isGranted;
    final notificationOk = notifications.isGranted;
    final listenerOk = probe['notificationAccess'] == true;
    final batteryOk = probe['batteryOptimizationIgnored'] == true;
    final phoneStateOk = phone.isGranted;

    return smsOk && notificationOk && listenerOk && batteryOk && phoneStateOk;
  }

  static Future<bool> _showSequence(
    BuildContext context,
    SystemDiagnosticsBridge diag,
  ) async {
    final steps = <_PermStep>[
      _PermStep(
        title: 'صلاحيات الرسائل (SMS)',
        body:
            'يحتاج NET إلى قراءة واستقبال وإرسال SMS لمعالجة التحويلات تلقائياً وإرسال كروت العملاء.',
        actionLabel: 'منح صلاحيات SMS',
        verify: () async => (await Permission.sms.status).isGranted &&
            (await Permission.phone.status).isGranted,
        onAllow: () async {
          await [Permission.sms, Permission.phone].request();
        },
      ),
      _PermStep(
        title: 'إشعارات التطبيق',
        body: 'يحتاج NET إلى إذن الإشعارات للتنبيهات التشغيلية.',
        actionLabel: 'منح إذن الإشعارات',
        verify: () async => (await Permission.notification.status).isGranted,
        onAllow: () async {
          await Permission.notification.request();
        },
      ),
      _PermStep(
        title: 'الوصول لإشعارات المحافظ',
        body:
            'يجب تفعيل خدمة قراءة الإشعارات من إعدادات أندرويد حتى يستطيع NET التقاط إشعارات المحافظ فعلياً.',
        actionLabel: 'فتح إعدادات إشعارات المحافظ',
        verify: () async => (await diag.probe())['notificationAccess'] == true,
        onAllow: () => diag.openNotificationAccess(),
        specialAccess: true,
      ),
      _PermStep(
        title: 'استثناء تحسين البطارية',
        body:
            'يجب السماح للتطبيق بالعمل دون تقييد البطارية حتى تستمر معالجة الرسائل والإشعارات في الخلفية.',
        actionLabel: 'فتح إعدادات البطارية',
        verify: () async =>
            (await diag.probe())['batteryOptimizationIgnored'] == true,
        onAllow: () => diag.openBatteryOptimization(),
        specialAccess: true,
      ),
      _PermStep(
        title: 'حالة الهاتف والشرائح',
        body:
            'يستخدم NET حالة الهاتف اللازمة للتشخيص والتوافق مع الأجهزة متعددة الشرائح.',
        actionLabel: 'منح إذن حالة الهاتف',
        verify: () async => (await Permission.phone.status).isGranted,
        onAllow: () async {
          await Permission.phone.request();
        },
      ),
    ];

    for (final step in steps) {
      while (context.mounted) {
        if (await step.verify()) break;

        final action = await showDialog<_PermissionAction>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(
                step.title,
                style: const TextStyle(
                  fontFamily: 'Tajawal',
                  fontWeight: FontWeight.w800,
                  color: KayanColors.textPrimary,
                ),
              ),
              content: Text(
                '${step.body}\n\nلن يعتبر الإعداد مكتملًا حتى يتأكد التطبيق من تفعيله فعليًا.',
                style: const TextStyle(
                  fontFamily: 'Tajawal',
                  height: 1.5,
                  color: KayanColors.textSecondary,
                ),
              ),
              actionsAlignment: MainAxisAlignment.spaceBetween,
              actions: [
                if (!step.specialAccess)
                  TextButton(
                    onPressed: () => Navigator.pop(
                      ctx,
                      _PermissionAction.openSettings,
                    ),
                    child: const Text('فتح إعدادات التطبيق'),
                  ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: KayanColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () =>
                      Navigator.pop(ctx, _PermissionAction.allow),
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

        if (!context.mounted) return false;
        if (action == _PermissionAction.openSettings) {
          await _openAndAwaitResume(diag.openAppSettings);
        } else if (action == _PermissionAction.allow) {
          if (step.specialAccess) {
            await _openAndAwaitResume(step.onAllow);
          } else {
            try {
              await step.onAllow();
            } catch (_) {}
          }
        } else {
          return false;
        }
      }
      if (!context.mounted) return false;
    }

    return _allRequirementsMet(diag);
  }

  static Future<void> _openAndAwaitResume(
    Future<void> Function() openSettings,
  ) async {
    final completer = Completer<void>();
    late final AppLifecycleListener listener;
    listener = AppLifecycleListener(
      onResume: () {
        if (!completer.isCompleted) completer.complete();
        listener.dispose();
      },
    );

    try {
      await openSettings();
      await completer.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () {},
      );
    } finally {
      listener.dispose();
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
}

enum _PermissionAction { allow, openSettings }

class _PermStep {
  const _PermStep({
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.verify,
    required this.onAllow,
    this.specialAccess = false,
  });

  final String title;
  final String body;
  final String actionLabel;
  final Future<bool> Function() verify;
  final Future<void> Function() onAllow;
  final bool specialAccess;
}
