import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/setting.dart';
import '../../app_scope.dart';
import '../../theme/kayan_colors.dart';
import '../../widgets/async_views.dart';
import '../../widgets/settings/network_name_edit_sheet.dart';
import '../../widgets/settings/settings_cards.dart';
import '../../widgets/settings/settings_section_header.dart';
import '../help_center_screen.dart';
import '../failed_messages_screen.dart';
import '../wallets_pos_screen.dart';
import 'battery_settings_screen.dart';
import 'clean_logs_screen.dart';
import 'device_verification_screen.dart';
import 'export_ledger_screen.dart';
import 'low_stock_settings_screen.dart';
import 'renew_subscription_screen.dart';
import 'salafni_templates_screen.dart';
import 'sim_settings_screen.dart';
import 'template_simulation_screen.dart';
import 'templates_screen.dart';
import 'wallet_notification_settings_screen.dart';

/// شاشة الإعدادات — ترتيب ومحتوى مطابق لفيديو Z Net.
class SettingsHubScreen extends StatefulWidget {
  const SettingsHubScreen({super.key});
  @override
  State<SettingsHubScreen> createState() => _SettingsHubScreenState();
}

class _SettingsHubScreenState extends State<SettingsHubScreen> {
  bool _loading = true;
  String? _error;
  String _networkName = SettingDefaults.networkName;
  bool _autoProcessing = SettingDefaults.smsAutoProcessingEnabled;
  bool _categoryOnly = SettingDefaults.processCategoryAmountsOnly;
  bool _oldMessages = SettingDefaults.processOldMessagesOnResume;
  bool _posBalanceRequests = SettingDefaults.posBalanceRequestsEnabled;
  bool _dailySummary = SettingDefaults.dailyOpsSummaryAutoSend;
  bool _darkTheme = false;
  bool _autoRetry = SettingDefaults.autoRetryFailedMessages;
  bool _salafniEnabled = SettingDefaults.salafniEnabled;
  int _lowStockThreshold = SettingDefaults.lowStockThreshold;
  final Set<String> _busyKeys = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final c = AppScope.of(context);
    Future<String?> read(String key) async {
      final r = await c.settings.find(key);
      return r is Success<AppSetting?> ? r.value?.value : null;
    }

    try {
      final network = await read(SettingKeys.networkName);
      final auto = await read(SettingKeys.smsAutoProcessingEnabled);
      final cat = await read(SettingKeys.processCategoryAmountsOnly);
      final old = await read(SettingKeys.processOldMessagesOnResume);
      final pos = await read(SettingKeys.posBalanceRequestsEnabled);
      final daily = await read(SettingKeys.dailyOpsSummaryAutoSend);
      final theme = await read(SettingKeys.themeMode);
      final retry = await read(SettingKeys.autoRetryFailedMessages);
      final salafni = await read(SettingKeys.salafniEnabled);
      final lowStock = await read(SettingKeys.lowStockThreshold);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _networkName = network?.trim().isNotEmpty == true ? network!.trim() : SettingDefaults.networkName;
        _autoProcessing = SettingBool.read(auto, defaultValue: SettingDefaults.smsAutoProcessingEnabled);
        _categoryOnly = SettingBool.read(cat, defaultValue: SettingDefaults.processCategoryAmountsOnly);
        _oldMessages = SettingBool.read(old, defaultValue: SettingDefaults.processOldMessagesOnResume);
        _posBalanceRequests = SettingBool.read(pos, defaultValue: SettingDefaults.posBalanceRequestsEnabled);
        _dailySummary = SettingBool.read(daily, defaultValue: SettingDefaults.dailyOpsSummaryAutoSend);
        _darkTheme = (theme ?? SettingDefaults.themeMode) == 'dark';
        _autoRetry = SettingBool.read(retry, defaultValue: SettingDefaults.autoRetryFailedMessages);
        _salafniEnabled = SettingBool.read(salafni, defaultValue: SettingDefaults.salafniEnabled);
        _lowStockThreshold = SettingInt.read(lowStock, defaultValue: SettingDefaults.lowStockThreshold);
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'تعذر تحميل الإعدادات';
        });
      }
    }
  }

  Future<void> _saveBool(String key, bool value, void Function(bool) applyLocal) async {
    final previous = switch (key) {
      SettingKeys.smsAutoProcessingEnabled => _autoProcessing,
      SettingKeys.processCategoryAmountsOnly => _categoryOnly,
      SettingKeys.processOldMessagesOnResume => _oldMessages,
      SettingKeys.posBalanceRequestsEnabled => _posBalanceRequests,
      SettingKeys.dailyOpsSummaryAutoSend => _dailySummary,
      SettingKeys.autoRetryFailedMessages => _autoRetry,
      SettingKeys.salafniEnabled => _salafniEnabled,
      _ => value,
    };
    setState(() {
      _busyKeys.add(key);
      applyLocal(value);
    });
    final c = AppScope.of(context);
    final result = await c.settings.save(
      AppSetting(key: key, value: value.toString(), updatedAt: c.clock.now()),
    );
    if (!mounted) return;
    setState(() => _busyKeys.remove(key));
    if (result is Failure) setState(() => applyLocal(previous));
  }

  Future<void> _saveTheme(bool dark) async {
    final previous = _darkTheme;
    setState(() {
      _busyKeys.add(SettingKeys.themeMode);
      _darkTheme = dark;
    });
    final c = AppScope.of(context);
    final result = await c.settings.save(
      AppSetting(key: SettingKeys.themeMode, value: dark ? 'dark' : 'light', updatedAt: c.clock.now()),
    );
    if (!mounted) return;
    setState(() => _busyKeys.remove(SettingKeys.themeMode));
    if (result is Failure) {
      setState(() => _darkTheme = previous);
      return;
    }
    c.themeModeNotifier.value = dark ? ThemeMode.dark : ThemeMode.light;
  }

  Future<void> _editNetworkName() async {
    final saved = await NetworkNameEditSheet.show(context, initialName: _networkName);
    if (saved != null && mounted) setState(() => _networkName = saved);
  }

  void _open(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  String get _autoProcessingSubtitle => _autoProcessing
      ? 'الخدمة تعمل — يتم استقبال ومعالجة الرسائل تلقائيًا'
      : 'الخدمة متوقفة — لن يتم استقبال أو معالجة الرسائل';

  String get _salafniSubtitle => _salafniEnabled
      ? 'الميزة مفعلة — يتم استقبال ومعالجة طلبات سلفني آليًا للعملاء المؤهلين'
      : 'الميزة متوقفة — فعّلها بعد تجهيز مخزون الكروت';

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: KayanColors.appBackground,
          appBar: AppBar(
            title: const Text(
              'الإعدادات',
              style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold),
            ),
            backgroundColor: KayanColors.appBackground,
            foregroundColor: KayanColors.textPrimary,
            elevation: 0,
          ),
          body: _loading
              ? const AsyncLoadingView()
              : _error != null
                  ? AsyncErrorView(message: _error!, onRetry: _load)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                        children: [
                          const Text(
                            'تخصيص النظام وإدارة البيانات',
                            style: TextStyle(
                              fontFamily: 'Tajawal',
                              fontSize: 14,
                              color: KayanColors.textSecondary,
                            ),
                          ),

                          // ── النظام (مطابق الفيديو) ─────────────────────
                          const SettingsSectionHeader(title: 'النظام'),
                          SettingsNavCard(
                            icon: Icons.badge_outlined,
                            title: 'اسم الشبكة',
                            subtitle: 'الاسم الحالي: $_networkName',
                            onTap: _editNetworkName,
                          ),
                          SettingsSwitchCard(
                            icon: Icons.autorenew,
                            title: 'المعالجة التلقائية للرسائل',
                            subtitle: _autoProcessingSubtitle,
                            value: _autoProcessing,
                            enabled: !_busyKeys.contains(SettingKeys.smsAutoProcessingEnabled),
                            onChanged: (v) => _saveBool(
                              SettingKeys.smsAutoProcessingEnabled,
                              v,
                              (x) => _autoProcessing = x,
                            ),
                          ),
                          SettingsSwitchCard(
                            icon: Icons.filter_alt_outlined,
                            title: 'معالجة مبالغ الفئات فقط',
                            subtitle:
                                'عند التفعيل، سيتم فقط معالجة رسائل المحافظ التي تطابق مبالغ الفئات المعرفة في النظام',
                            value: _categoryOnly,
                            enabled: !_busyKeys.contains(SettingKeys.processCategoryAmountsOnly),
                            onChanged: (v) => _saveBool(
                              SettingKeys.processCategoryAmountsOnly,
                              v,
                              (x) => _categoryOnly = x,
                            ),
                          ),
                          SettingsSwitchCard(
                            icon: Icons.history,
                            title: 'معالجة الرسائل القديمة (عند التوقف)',
                            subtitle:
                                'تفعيل لمعالجة رسائل SMS التي وصلت أثناء إغلاق أو توقف التطبيق عند فتحه مجددًا',
                            value: _oldMessages,
                            enabled: !_busyKeys.contains(SettingKeys.processOldMessagesOnResume),
                            onChanged: (v) => _saveBool(
                              SettingKeys.processOldMessagesOnResume,
                              v,
                              (x) => _oldMessages = x,
                            ),
                          ),
                          SettingsSwitchCard(
                            icon: Icons.card_giftcard_outlined,
                            title: 'خدمة سلفني',
                            subtitle: _salafniSubtitle,
                            value: _salafniEnabled,
                            enabled: !_busyKeys.contains(SettingKeys.salafniEnabled),
                            onChanged: (v) => _saveBool(
                              SettingKeys.salafniEnabled,
                              v,
                              (x) => _salafniEnabled = x,
                            ),
                          ),
                          SettingsNavCard(
                            icon: Icons.notifications_active_outlined,
                            title: 'تنبيهات انخفاض مخزون الكروت',
                            subtitle: 'سيتم تنبيهك عندما يقل مخزون أي فئة عن $_lowStockThreshold كرت',
                            onTap: () async {
                              await _open(const LowStockSettingsScreen());
                              await _load();
                            },
                          ),
                          SettingsNavCard(
                            icon: Icons.sim_card_outlined,
                            title: 'إعدادات شرائح الاتصال',
                            subtitle: 'إدارة شرائح القراءة والإرسال و Failover',
                            onTap: () => _open(const SimSettingsScreen()),
                          ),
                          SettingsNavCard(
                            icon: Icons.health_and_safety_outlined,
                            title: 'فحص النظام',
                            subtitle: 'التحقق من جاهزية أذونات النظام والتشغيل في الخلفية',
                            onTap: () => _open(const DeviceVerificationScreen()),
                          ),

                          // ── الترخيص ────────────────────────────────────
                          const SettingsSectionHeader(title: 'الترخيص'),
                          SettingsNavCard(
                            icon: Icons.workspace_premium_outlined,
                            title: 'تجديد الاشتراك',
                            subtitle: 'تجديد الترخيص أو إضافة رصيد SMS قبل انتهاء الباقة الحالية',
                            onTap: () => _open(const RenewSubscriptionScreen()),
                          ),

                          // ── المظهر ─────────────────────────────────────
                          const SettingsSectionHeader(title: 'المظهر'),
                          SettingsSwitchCard(
                            icon: Icons.dark_mode_outlined,
                            title: 'الوضع الداكن',
                            subtitle: _darkTheme ? 'المظهر الداكن مفعل' : 'إيقافه يعيد الوضع الفاتح',
                            value: _darkTheme,
                            enabled: !_busyKeys.contains(SettingKeys.themeMode),
                            onChanged: _saveTheme,
                          ),

                          // ── المحافظ ونقاط البيع (مطابق الفيديو) ─────────
                          const SettingsSectionHeader(title: 'إعدادات المحافظ ونقاط البيع'),
                          SettingsNavCard(
                            icon: Icons.account_balance_wallet_outlined,
                            title: 'إدارة المحافظ ونقاط البيع',
                            subtitle: 'إضافة وتعديل المحافظ ونقاط البيع',
                            onTap: () => _open(const WalletsPosScreen()),
                          ),
                          SettingsNavCard(
                            icon: Icons.science_outlined,
                            title: 'محاكاة القوالب',
                            subtitle: 'اختبار ومحاكاة استخراج بيانات الرسائل',
                            onTap: () => _open(const TemplateSimulationScreen()),
                          ),
                          SettingsNavCard(
                            icon: Icons.pattern,
                            title: 'قوالب التحويل',
                            subtitle: 'معالج 4 مراحل لإعداد أنماط تحليل SMS',
                            onTap: () => _open(const TemplatesScreen()),
                          ),
                          SettingsNavCard(
                            icon: Icons.notifications_outlined,
                            title: 'إشعارات المحافظ',
                            subtitle: 'ربط المحافظ الإلكترونية كمصادر دفع',
                            onTap: () => _open(const WalletNotificationSettingsScreen()),
                          ),

                          // ── سلفني والقوالب النصية ──────────────────────
                          const SettingsSectionHeader(title: 'قوالب رسائل سلفني'),
                          SettingsNavCard(
                            icon: Icons.chat_bubble_outline,
                            title: 'قوالب رسائل سلفني',
                            subtitle: 'رسائل القبول والرفض والسداد',
                            onTap: () => _open(const SalafniTemplatesScreen()),
                          ),

                          // ── التشغيل والاستعادة ─────────────────────────
                          const SettingsSectionHeader(title: 'التشغيل والاستعادة'),
                          SettingsSwitchCard(
                            icon: Icons.restart_alt,
                            title: 'إعادة محاولة الرسائل الفاشلة تلقائيًا',
                            subtitle: 'محاولات محدودة مع تأخير تصاعدي',
                            value: _autoRetry,
                            enabled: !_busyKeys.contains(SettingKeys.autoRetryFailedMessages),
                            onChanged: (v) => _saveBool(
                              SettingKeys.autoRetryFailedMessages,
                              v,
                              (x) => _autoRetry = x,
                            ),
                          ),
                          SettingsNavCard(
                            icon: Icons.error_outline,
                            title: 'الرسائل الفاشلة',
                            subtitle: 'مراجعة وإعادة المحاولة يدويًا',
                            onTap: () => _open(const FailedMessagesScreen()),
                          ),
                          SettingsNavCard(
                            icon: Icons.battery_saver_outlined,
                            title: 'البطارية',
                            subtitle: 'توصيات العمل في الخلفية',
                            onTap: () => _open(const BatterySettingsScreen()),
                          ),

                          // ── نقاط البيع والعمليات ───────────────────────
                          const SettingsSectionHeader(title: 'نقاط البيع والعمليات'),
                          SettingsSwitchCard(
                            icon: Icons.point_of_sale_outlined,
                            title: 'طلبات الرصيد لنقاط البيع',
                            subtitle: 'التعامل مع طلبات الرصيد الواردة من نقاط البيع',
                            value: _posBalanceRequests,
                            enabled: !_busyKeys.contains(SettingKeys.posBalanceRequestsEnabled),
                            onChanged: (v) => _saveBool(
                              SettingKeys.posBalanceRequestsEnabled,
                              v,
                              (x) => _posBalanceRequests = x,
                            ),
                          ),
                          SettingsSwitchCard(
                            icon: Icons.summarize_outlined,
                            title: 'إرسال ملخص العمليات اليومية تلقائيًا',
                            subtitle: 'عند التفعيل يرسل النظام ملخصًا يوميًا تلقائيًا',
                            value: _dailySummary,
                            enabled: !_busyKeys.contains(SettingKeys.dailyOpsSummaryAutoSend),
                            onChanged: (v) => _saveBool(
                              SettingKeys.dailyOpsSummaryAutoSend,
                              v,
                              (x) => _dailySummary = x,
                            ),
                          ),

                          // ── البيانات ───────────────────────────────────
                          const SettingsSectionHeader(title: 'البيانات'),
                          SettingsNavCard(
                            icon: Icons.file_upload_outlined,
                            title: 'تصدير السجل',
                            subtitle: 'تصدير حركات الدفتر',
                            onTap: () => _open(const ExportLedgerScreen()),
                          ),
                          SettingsNavCard(
                            icon: Icons.cleaning_services_outlined,
                            title: 'تنظيف السجلات',
                            subtitle: 'استعادة ومعالجة الرسائل المعلّقة',
                            onTap: () => _open(const CleanLogsScreen()),
                          ),

                          // ── المساعدة ───────────────────────────────────
                          const SettingsSectionHeader(title: 'المساعدة'),
                          SettingsNavCard(
                            icon: Icons.help_outline,
                            title: 'مركز المساعدة',
                            subtitle: 'دليل الاستخدام والأسئلة الشائعة',
                            onTap: () => _open(const HelpCenterScreen()),
                          ),
                        ],
                      ),
                    ),
        ),
      );
}
