import 'dart:async';
import 'dart:io';

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
  static const doneKey = 'permissions_onboarding_done_v6';

  static Future<void> maybeRun(BuildContext context) async {
    if (!Platform.isAndroid) return;

    final c = AppScope.of(context);
    final diag = SystemDiagnosticsBridge();
    final existing = await c.settings.find(doneKey);
    final alreadyDone = existing is Success<AppSetting?> &&
        existing.value?.value == 'true';

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
    final contacts = await Permission.contacts.status;
    final probe = await diag.probe();

    final smsOk = sms.isGranted && phone.isGranted;
    final notificationOk = notifications.isGranted;
    final contactsOk = contacts.isGranted;
    final listenerOk = probe['notificationAccess'] == true;
    final batteryOk = probe['batteryOptimizationIgnored'] == true;
    final phoneStateOk = phone.isGranted;

    return smsOk &&
        notificationOk &&
        contactsOk &&
        listenerOk &&
        batteryOk &&
        phoneStateOk;
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
        title: 'جهات الاتصال',
        body:
            'يحتاج NET إلى قراءة جهات الاتصال لربط أرقام العملاء بالأسماء المعروفة وتسهيل التعرف على التحويلات.',
        actionLabel: 'منح صلاحية جهات الاتصال',
        verify: () async => (await Permission.contacts.status).isGranted,
        onAllow: () async {
          final status = await Permission.contacts.request();
          if (!status.isGranted) {
            await diag.requestContactsPermission();
          }
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
        title: 'العمل في الخلفية (البطارية)',
        body:
            'يجب السماح للتطبيق بالعمل دون تقييد البطارية حتى تستمر معالجة الرسائل والإشعارات بعد إغلاق الشاشة.',
        actionLabel: 'فتح إعدادات البطارية',
        verify: () async =>
            (await diag.probe())['batteryOptimizationIgnored'] == true,
        onAllow: () => diag.openBatteryOptimization(),
        specialAccess: true,
      ),
      _PermStep(
        title: 'التشغيل التلقائي بعد إعادة تشغيل الهاتف',
        body:
            'على بعض الأجهزة (شاومي، هواوي، أوبو، فيفو…) يجب السماح بالتشغيل التلقائي حتى يعود NET للعمل بعد إقلاع الجهاز.',
        actionLabel: 'فتح إعدادات التشغيل التلقائي',
        verify: () async => false,
        onAllow: () => diag.openAutoStartSettings(),
        specialAccess: true,
        optionalAfterOpen: true,
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
              backgroundColor: KayanColors.surface,
              title: Text(
                step.title,
                style: const TextStyle(
                  fontFamily: 'Tajawal',
                  fontWeight: FontWeight.w800,
                ),
              ),
              content: Text(
                step.body,
                style: const TextStyle(fontFamily: 'Tajawal', height: 1.45),
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.pop(ctx, _PermissionAction.openSettings),
                  child: const Text(
                    'فتح الإعدادات',
                    style: TextStyle(fontFamily: 'Tajawal'),
                  ),
                ),
                if (step.optionalAfterOpen)
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(ctx, _PermissionAction.skip),
                    child: const Text(
                      'تم — متابعة',
                      style: TextStyle(fontFamily: 'Tajawal'),
                    ),
                  ),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(ctx, _PermissionAction.allow),
                  child: Text(
                    step.actionLabel,
                    style: const TextStyle(fontFamily: 'Tajawal'),
                  ),
                ),
              ],
            ),
          ),
        );

        if (!context.mounted) return false;
        if (action == null) return false;

        if (action == _PermissionAction.openSettings) {
          await diag.openAppSettings();
          await Future<void>.delayed(const Duration(milliseconds: 600));
        } else if (action == _PermissionAction.allow) {
          await step.onAllow();
          await Future<void>.delayed(const Duration(milliseconds: 400));
          if (step.optionalAfterOpen) break;
        } else if (action == _PermissionAction.skip && step.optionalAfterOpen) {
          break;
        }
      }
    }
    return context.mounted;
  }
}

final class _PermStep {
  const _PermStep({
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.verify,
    required this.onAllow,
    this.specialAccess = false,
    this.optionalAfterOpen = false,
  });

  final String title;
  final String body;
  final String actionLabel;
  final Future<bool> Function() verify;
  final Future<void> Function() onAllow;
  final bool specialAccess;
  final bool optionalAfterOpen;
}

enum _PermissionAction { allow, openSettings, skip }
