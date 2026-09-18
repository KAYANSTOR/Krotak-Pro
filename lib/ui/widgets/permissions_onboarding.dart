import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/result.dart';
import '../../domain/entities/setting.dart';
import '../../platform/system_diagnostics_bridge.dart';
import '../app_scope.dart';
import '../theme/kayan_palette.dart';
import '../theme/net_semantic_colors.dart';
import '../theme/net_tokens.dart';
import 'net/net_surface_card.dart';

/// بوابة تهيئة إلزامية: لا تُسجّل كمكتملة إلا بعد تحقق أندرويد من جميع المتطلبات.
///
/// تُعرض الآن كمساحة تهيئة واحدة بخطوات واضحة (1/N) مع حالة تحقق لكل خطوة،
/// بدل سبعة حوارات متتالية مانعة.
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
        icon: Icons.sms_rounded,
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
        icon: Icons.notifications_active_rounded,
        title: 'إشعارات التطبيق',
        body: 'يحتاج NET إلى إذن الإشعارات للتنبيهات التشغيلية.',
        actionLabel: 'منح إذن الإشعارات',
        verify: () async => (await Permission.notification.status).isGranted,
        onAllow: () async {
          await Permission.notification.request();
        },
      ),
      _PermStep(
        icon: Icons.contacts_rounded,
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
        icon: Icons.mark_email_read_rounded,
        title: 'الوصول لإشعارات المحافظ',
        body:
            'يجب تفعيل خدمة قراءة الإشعارات من إعدادات أندرويد حتى يستطيع NET التقاط إشعارات المحافظ فعلياً.',
        actionLabel: 'فتح إعدادات إشعارات المحافظ',
        verify: () async => (await diag.probe())['notificationAccess'] == true,
        onAllow: () => diag.openNotificationAccess(),
        specialAccess: true,
      ),
      _PermStep(
        icon: Icons.battery_saver_rounded,
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
        icon: Icons.restart_alt_rounded,
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
        icon: Icons.phone_android_rounded,
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

    return await Navigator.of(context, rootNavigator: true).push<bool>(
          MaterialPageRoute<bool>(
            fullscreenDialog: true,
            builder: (_) => _PermissionsFlow(steps: steps, diagnostics: diag),
          ),
        ) ??
        false;
  }
}

final class _PermStep {
  const _PermStep({
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.verify,
    required this.onAllow,
    this.icon = Icons.check_circle_outline_rounded,
    this.specialAccess = false,
    this.optionalAfterOpen = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final Future<bool> Function() verify;
  final Future<void> Function() onAllow;
  final bool specialAccess;
  final bool optionalAfterOpen;
}

/// A single guided flow: progress, live verification and one primary action
/// per step instead of a chain of blocking dialogs.
class _PermissionsFlow extends StatefulWidget {
  const _PermissionsFlow({required this.steps, required this.diagnostics});

  final List<_PermStep> steps;
  final SystemDiagnosticsBridge diagnostics;

  @override
  State<_PermissionsFlow> createState() => _PermissionsFlowState();
}

class _PermissionsFlowState extends State<_PermissionsFlow> {
  int _index = 0;
  bool _checking = true;
  bool _verified = false;
  bool _busy = false;

  /// أرقام الخطوات التي تحقق شرطها فعليًا — تُعرض كتقدّم وتُتخطّى عند الفتح.
  final Set<int> _satisfied = <int>{};

  _PermStep get _step => widget.steps[_index];
  bool get _isLast => _index >= widget.steps.length - 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  /// يبدأ المستخدم من أول متطلب ناقص فعليًا بدل إعادة المرور على كل الخطوات
  /// الممنوحة مسبقًا في كل مرة يفتح فيها التطبيق.
  Future<void> _bootstrap() async {
    for (var i = 0; i < widget.steps.length - 1; i++) {
      var ok = false;
      try {
        ok = await widget.steps[i].verify();
      } catch (_) {
        ok = false;
      }
      if (!ok) break;
      _satisfied.add(i);
      if (!mounted) return;
      setState(() {
        _index = i + 1;
        _verified = false;
        _checking = true;
      });
    }
    if (!mounted) return;
    await _check();
  }

  Future<void> _check() async {
    if (!mounted) return;
    setState(() => _checking = true);
    var ok = false;
    try {
      ok = await _step.verify();
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() {
      _checking = false;
      _verified = ok;
      if (ok) {
        _satisfied.add(_index);
      } else {
        _satisfied.remove(_index);
      }
    });
  }

  Future<void> _runAction() async {
    setState(() => _busy = true);
    try {
      await _step.onAllow();
    } catch (_) {
      // Permission plugins can throw on unsupported OEM builds; the next check
      // reports the real state instead of failing the flow.
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    setState(() => _busy = false);
    await _check();
    if (!mounted) return;
    if (_step.optionalAfterOpen) _advance(force: true);
  }

  Future<void> _openAppSettings() async {
    await widget.diagnostics.openAppSettings();
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    await _check();
  }

  void _advance({bool force = false}) {
    if (!force && !_verified) return;
    if (_isLast) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _index += 1;
      _verified = false;
      _checking = true;
    });
    _check();
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final net = context.netColors;
    final progress = (_index + 1) / widget.steps.length;
    final canAdvance = _verified || _step.optionalAfterOpen;

    return Scaffold(
      backgroundColor: palette.appBackground,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NetSpacing.lg,
                NetSpacing.sm,
                NetSpacing.lg,
                NetSpacing.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'تهيئة NET',
                          style: TextStyle(
                            fontFamily: NetTypography.family,
                            fontWeight: FontWeight.w800,
                            fontSize: 19,
                            color: palette.textPrimary,
                          ),
                        ),
                        Text(
                          _satisfied.isEmpty
                              ? 'الخطوة ${_index + 1} من ${widget.steps.length} · مطلوب لإكمال التشغيل'
                              : 'الخطوة ${_index + 1} من ${widget.steps.length} · مكتمل ${_satisfied.length} من ${widget.steps.length}',
                          style: TextStyle(
                            fontFamily: NetTypography.family,
                            fontSize: 12,
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'إغلاق',
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: Icon(Icons.close_rounded, color: palette.textSecondary),
                  ),
                ],
              ),
            ),
            Padding(
              padding: NetSpacing.pageH,
              child: ClipRRect(
                borderRadius: NetRadii.pillAll,
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: palette.surfaceVariant,
                  color: palette.primary,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  NetSpacing.lg,
                  NetSpacing.lg,
                  NetSpacing.lg,
                  NetSpacing.xxl,
                ),
                children: [
                  NetSurfaceCard(
                    padding: NetSpacing.card,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: palette.iconBadgeBackground,
                                borderRadius: NetRadii.smAll,
                              ),
                              child: Icon(
                                _step.icon,
                                color: palette.primary,
                                size: NetSizes.iconLg,
                              ),
                            ),
                            const SizedBox(width: NetSpacing.md),
                            Expanded(
                              child: Text(
                                _step.title,
                                style: TextStyle(
                                  fontFamily: NetTypography.family,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                  color: palette.textPrimary,
                                ),
                              ),
                            ),
                            _StatusChip(
                              checking: _checking,
                              verified: _verified,
                              optional: _step.optionalAfterOpen,
                            ),
                          ],
                        ),
                        const SizedBox(height: NetSpacing.md),
                        Text(
                          _step.body,
                          style: TextStyle(
                            fontFamily: NetTypography.family,
                            fontSize: 13.5,
                            height: 1.5,
                            color: palette.textSecondary,
                          ),
                        ),
                        if (_step.specialAccess) ...[
                          const SizedBox(height: NetSpacing.md),
                          Row(
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: NetSizes.iconSm,
                                color: net.info,
                              ),
                              const SizedBox(width: NetSpacing.sm),
                              Expanded(
                                child: Text(
                                  'هذه الصلاحية تُمنح من إعدادات أندرويد وليس من حوار التطبيق.',
                                  style: TextStyle(
                                    fontFamily: NetTypography.family,
                                    fontSize: 12,
                                    color: net.info,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: NetSpacing.lg),
                  FilledButton.icon(
                    onPressed: _busy ? null : _runAction,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_rounded, size: NetSizes.iconSm),
                    label: Text(_step.actionLabel),
                  ),
                  const SizedBox(height: NetSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _openAppSettings,
                          icon: const Icon(Icons.settings_rounded, size: NetSizes.iconSm),
                          label: const Text('فتح الإعدادات'),
                        ),
                      ),
                      const SizedBox(width: NetSpacing.sm),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _check,
                          icon: const Icon(Icons.refresh_rounded, size: NetSizes.iconSm),
                          label: const Text('إعادة الفحص'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: NetSpacing.lg),
                  FilledButton.tonal(
                    onPressed: canAdvance ? () => _advance(force: _step.optionalAfterOpen) : null,
                    child: Text(
                      _isLast
                          ? 'إنهاء التهيئة'
                          : (_step.optionalAfterOpen ? 'تم — متابعة' : 'التالي'),
                    ),
                  ),
                  if (!canAdvance && !_checking) ...[
                    const SizedBox(height: NetSpacing.sm),
                    Text(
                      'أكمل هذه الخطوة للانتقال إلى التالية. إذا لم يعمل الزر، افتح الإعدادات وامنح الصلاحية يدويًا ثم اضغط «إعادة الفحص».',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: NetTypography.family,
                        fontSize: 11.5,
                        height: 1.45,
                        color: palette.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.checking,
    required this.verified,
    required this.optional,
  });

  final bool checking;
  final bool verified;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final net = context.netColors;

    late final Color color;
    late final Color background;
    late final String label;
    late final IconData icon;

    if (checking) {
      color = palette.textSecondary;
      background = palette.surfaceVariant;
      label = 'جارٍ الفحص';
      icon = Icons.hourglass_top_rounded;
    } else if (verified) {
      color = net.success;
      background = net.successContainer;
      label = 'تم التحقق';
      icon = Icons.check_circle_rounded;
    } else if (optional) {
      color = net.warning;
      background = net.warningContainer;
      label = 'اختياري';
      icon = Icons.info_rounded;
    } else {
      color = net.error;
      background = net.errorContainer;
      label = 'غير مفعّل';
      icon = Icons.cancel_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NetSpacing.sm,
        vertical: NetSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: NetRadii.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: NetSpacing.xs),
          Text(
            label,
            style: TextStyle(
              fontFamily: NetTypography.family,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
