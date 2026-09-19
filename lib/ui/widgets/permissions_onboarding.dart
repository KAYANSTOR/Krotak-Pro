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

/// بوابة تهيئة الأذونات — مطابقة فيديو المنتج (ورقة سفلية فوق الواجهة، ليست شاشة كاملة).
///
/// لا تُسجّل كمكتملة إلا بعد تحقق أندرويد من المتطلبات. العرض: bottom sheet
/// بهوية NET (بطاقة + تقدم + خطوة واحدة) فوق لوحة التحكم دون شاشة كاملة.
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

    return await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          isDismissible: false,
          enableDrag: false,
          backgroundColor: Colors.transparent,
          builder: (ctx) => _PermissionsSheet(steps: steps, diagnostics: diag),
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

/// ورقة أذونات سفلية مطابقة الفيديو: خطوة بخطوة فوق الواجهة (ليست شاشة كاملة).
class _PermissionsSheet extends StatefulWidget {
  const _PermissionsSheet({required this.steps, required this.diagnostics});

  final List<_PermStep> steps;
  final SystemDiagnosticsBridge diagnostics;

  @override
  State<_PermissionsSheet> createState() => _PermissionsSheetState();
}

class _PermissionsSheetState extends State<_PermissionsSheet>
    with WidgetsBindingObserver {
  int _index = 0;
  bool _verified = false;
  bool _checking = false;
  final Set<int> _satisfied = <int>{};

  _PermStep get _step => widget.steps[_index];
  bool get _isLast => _index >= widget.steps.length - 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  /// يبدأ من أول متطلب ناقص بدل إعادة المرور على الخطوات الممنوحة مسبقاً.
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
    await _recheck();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _recheck();
    }
  }

  Future<void> _recheck() async {
    if (!mounted) return;
    setState(() => _checking = true);
    final ok = await _step.verify();
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

  Future<void> _allow() async {
    setState(() => _checking = true);
    try {
      await _step.onAllow();
    } catch (_) {
      // OEM builds may throw; next check reports real state.
    }
    if (mounted) await _recheck();
    if (_step.optionalAfterOpen && mounted) {
      _advance(force: true);
    }
  }

  void _advance({bool force = false}) {
    if (!force && !_verified && !_step.optionalAfterOpen) return;
    if (_isLast) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _index += 1;
      _verified = false;
      _checking = false;
    });
    _recheck();
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final net = context.netColors;
    final progress = (_index + 1) / widget.steps.length;
    final canAdvance = _verified || _step.optionalAfterOpen;
    final media = MediaQuery.of(context);
    final maxH = media.size.height * 0.78;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: Material(
              color: palette.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 10),
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: palette.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'تهيئة التشغيل',
                                  style: TextStyle(
                                    fontFamily: NetTypography.family,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 17,
                                    color: palette.primary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'الخطوة ' +
                                      (_index + 1).toString() +
                                      ' من ' +
                                      widget.steps.length.toString() +
                                      ' · مكتمل ' +
                                      _satisfied.length.toString(),
                                  style: TextStyle(
                                    fontFamily: NetTypography.family,
                                    fontSize: 12.5,
                                    color: palette.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'إغلاق',
                            onPressed: () => Navigator.of(context).pop(false),
                            icon: Icon(
                              Icons.close_rounded,
                              color: palette.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          backgroundColor: palette.surfaceVariant,
                          color: palette.primary,
                        ),
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                        child: NetSurfaceCard(
                          padding: const EdgeInsets.all(16),
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
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _step.title,
                                      style: TextStyle(
                                        fontFamily: NetTypography.family,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15.5,
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
                              const SizedBox(height: 12),
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
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: net.warningContainer.withValues(
                                      alpha: 0.55,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.settings_rounded,
                                        size: 18,
                                        color: net.warning,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'يتطلب فتح إعدادات النظام ثم العودة للتطبيق للتحقق.',
                                          style: TextStyle(
                                            fontFamily: NetTypography.family,
                                            fontSize: 12,
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
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FilledButton.icon(
                            onPressed: _checking ? null : _allow,
                            icon: Icon(
                              _step.specialAccess
                                  ? Icons.open_in_new_rounded
                                  : Icons.verified_user_rounded,
                              size: 18,
                            ),
                            label: Text(
                              _step.actionLabel,
                              style: const TextStyle(
                                fontFamily: NetTypography.family,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _checking ? null : _recheck,
                                  child: const Text(
                                    'إعادة الفحص',
                                    style: TextStyle(
                                      fontFamily: NetTypography.family,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 2,
                                child: FilledButton.tonal(
                                  onPressed: canAdvance && !_checking
                                      ? () => _advance(
                                            force: _step.optionalAfterOpen,
                                          )
                                      : null,
                                  child: Text(
                                    _isLast
                                        ? 'إنهاء التهيئة'
                                        : (_step.optionalAfterOpen
                                            ? 'تم — متابعة'
                                            : 'التالي'),
                                    style: const TextStyle(
                                      fontFamily: NetTypography.family,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (!canAdvance && !_checking) ...[
                            const SizedBox(height: 8),
                            Text(
                              'أكمل هذه الخطوة للانتقال. إن لم يعمل الزر، افتح الإعدادات يدوياً ثم «إعادة الفحص».',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: NetTypography.family,
                                fontSize: 11.5,
                                height: 1.4,
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
            ),
          ),
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
