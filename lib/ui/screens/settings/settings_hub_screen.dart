import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/setting.dart';
import '../../app_scope.dart';
import '../../routing/app_routes.dart';
import '../../theme/kayan_palette.dart';
import '../../theme/net_semantic_colors.dart';
import '../../theme/net_theme_schedule.dart';
import '../../theme/net_tokens.dart';
import '../../widgets/async_views.dart';
import '../../widgets/dashboard/theme_mode_sheet.dart';
import '../../widgets/net/net_surface_card.dart';
import '../../widgets/settings/settings_cards.dart';
import '../../widgets/settings/settings_section_header.dart';
import '../system_check_screen.dart';
import '../wallets_pos_screen.dart';
import 'clean_logs_screen.dart';
import 'export_ledger_screen.dart';
import 'low_stock_settings_screen.dart';
import 'network_name_settings_screen.dart';
import 'renew_subscription_screen.dart';
import 'salafni_templates_screen.dart';
import 'outbound_message_templates_screen.dart';
import 'sim_settings_screen.dart';
import 'template_simulation_screen.dart';
import 'templates_screen.dart';
import 'wallet_notification_settings_screen.dart';

/// مركز الإعدادات — مطابق حرفياً لإطارات فيديو Z Net
class SettingsHubScreen extends StatefulWidget {
  const SettingsHubScreen({super.key});

  @override
  State<SettingsHubScreen> createState() => _SettingsHubScreenState();
}

class _SettingsHubScreenState extends State<SettingsHubScreen> {
  bool _loading = true;
  String _networkName = SettingDefaults.networkName;
  bool _autoSms = SettingDefaults.smsAutoProcessingEnabled;
  bool _categoryOnly = SettingDefaults.processCategoryAmountsOnly;
  bool _oldMsgs = SettingDefaults.processOldMessagesOnResume;
  bool _salafni = SettingDefaults.salafniEnabled;
  bool _interventionAlert = SettingDefaults.pendingAttentionAlertEnabled;
  bool _darkMode = false;
  NetThemeMode _themeMode = NetThemeMode.light;
  bool _dailySummary = SettingDefaults.dailyOpsSummaryAutoSend;
  bool _autoPosSettlement = SettingDefaults.autoPosSettlementEnabled;
  int _lowStock = SettingDefaults.lowStockThreshold;

  // ── Settings search (presentation only) ──
  final _searchCtrl = TextEditingController();
  String _query = '';

  static const _systemKeywords =
      'اسم الشبكة المعالجة التلقائية الفئات الرسائل القديمة تنبيه العمليات سلفني قوالب رسائل انخفاض مخزون شرائح الاتصال فحص النظام';
  static const _licenseKeywords = 'تجديد الاشتراك الترخيص رصيد الرسائل الباقة';
  static const _themeKeywords = 'الوضع الداكن المظهر الثيم ليلي فاتح';
  static const _walletsKeywords =
      'المحافظ نقاط البيع محاكاة القوالب قوالب التحويل طلبات الرصيد ملخص العمليات اليومي التسوية التلقائية';
  static const _maintenanceKeywords = 'تنظيف السجلات تصدير السجل الأرشفة';

  bool _sectionVisible(String keywords) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return keywords.toLowerCase().contains(q);
  }

  bool get _anySectionVisible =>
      _sectionVisible(_systemKeywords) ||
      _sectionVisible(_licenseKeywords) ||
      _sectionVisible(_themeKeywords) ||
      _sectionVisible(_walletsKeywords) ||
      _sectionVisible(_maintenanceKeywords);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Widget _searchField(BuildContext context) {
    final palette = KayanPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: NetSpacing.sm),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v),
        style: TextStyle(
          fontFamily: NetTypography.family,
          color: palette.textPrimary,
        ),
        decoration: InputDecoration(
          hintText: 'ابحث في الإعدادات...',
          hintStyle: TextStyle(
            fontFamily: NetTypography.family,
            color: palette.textTertiary,
            fontSize: 13,
          ),
          prefixIcon: Icon(Icons.search_rounded, color: palette.textTertiary),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  tooltip: 'مسح',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _query = '');
                  },
                ),
          filled: true,
          fillColor: palette.surface,
          border: OutlineInputBorder(
            borderRadius: NetRadii.pillAll,
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: NetRadii.pillAll,
            borderSide: BorderSide(color: palette.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: NetRadii.pillAll,
            borderSide: BorderSide(color: palette.primary, width: 1.4),
          ),
        ),
      ),
    );
  }

  /// Operational readiness at a glance (derived from the settings already loaded).
  Widget _readinessCard(BuildContext context) {
    final net = context.netColors;
    final palette = KayanPalette.of(context);
    final pills = <({String label, bool ok, IconData icon})>[
      (label: 'المعالجة التلقائية', ok: _autoSms, icon: Icons.bolt_rounded),
      (label: 'تنبيه التدخل', ok: _interventionAlert, icon: Icons.notifications_active_rounded),
      (label: 'سلفني', ok: _salafni, icon: Icons.card_giftcard_rounded),
      (label: 'المظهر الداكن', ok: _darkMode, icon: Icons.dark_mode_rounded),
    ];

    return NetSurfaceCard(
      margin: const EdgeInsets.only(top: NetSpacing.sm, bottom: NetSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.health_and_safety_rounded,
                size: NetSizes.iconSm,
                color: palette.primary,
              ),
              const SizedBox(width: NetSpacing.sm),
              Expanded(
                child: Text(
                  'جاهزية التشغيل',
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SystemCheckScreen()),
                ),
                icon: const Icon(Icons.chevron_left_rounded, size: NetSizes.iconSm),
                label: const Text('فحص النظام'),
              ),
            ],
          ),
          const SizedBox(height: NetSpacing.sm),
          Wrap(
            spacing: NetSpacing.sm,
            runSpacing: NetSpacing.sm,
            children: [
              for (final pill in pills)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NetSpacing.sm,
                    vertical: NetSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: pill.ok ? net.successContainer : palette.surfaceVariant,
                    borderRadius: NetRadii.pillAll,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        pill.ok ? Icons.check_circle_rounded : Icons.cancel_outlined,
                        size: 13,
                        color: pill.ok ? net.success : palette.textSecondary,
                      ),
                      const SizedBox(width: NetSpacing.xs),
                      Text(
                        pill.label,
                        style: TextStyle(
                          fontFamily: NetTypography.family,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: pill.ok ? net.success : palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _load() async {
    final c = AppScope.of(context);

    Future<String?> read(String key) async {
      final r = await c.settings.find(key);
      if (r is Success<AppSetting?>) return r.value?.value;
      return null;
    }

    final name = await read(SettingKeys.networkName);
    final auto = await read(SettingKeys.smsAutoProcessingEnabled);
    final cat = await read(SettingKeys.processCategoryAmountsOnly);
    final old = await read(SettingKeys.processOldMessagesOnResume);
    final sal = await read(SettingKeys.salafniEnabled);
    final intervention = await read(SettingKeys.pendingAttentionAlertEnabled);
    final theme = await read(SettingKeys.themeMode);
    final daily = await read(SettingKeys.dailyOpsSummaryAutoSend);
    final settle = await read(SettingKeys.autoPosSettlementEnabled);
    final low = await read(SettingKeys.lowStockThreshold);

    if (!mounted) return;
    setState(() {
      _loading = false;
      if (name != null && name.trim().isNotEmpty) _networkName = name.trim();
      _autoSms = SettingBool.read(auto, defaultValue: SettingDefaults.smsAutoProcessingEnabled);
      _categoryOnly = SettingBool.read(cat, defaultValue: SettingDefaults.processCategoryAmountsOnly);
      _oldMsgs = SettingBool.read(old, defaultValue: SettingDefaults.processOldMessagesOnResume);
      _salafni = SettingBool.read(sal, defaultValue: SettingDefaults.salafniEnabled);
      _interventionAlert = SettingBool.read(
        intervention,
        defaultValue: SettingDefaults.pendingAttentionAlertEnabled,
      );
      _dailySummary = SettingBool.read(daily, defaultValue: SettingDefaults.dailyOpsSummaryAutoSend);
      _autoPosSettlement = SettingBool.read(settle, defaultValue: SettingDefaults.autoPosSettlementEnabled);
      _lowStock = SettingInt.read(low, defaultValue: SettingDefaults.lowStockThreshold);
      final t = (theme ?? SettingDefaults.themeMode).toLowerCase();
      // `system` القديمة تُقرأ كوضع نهاري ثابت (توافق خلفي).
      _themeMode = NetThemeSchedule.parse(theme);
      _darkMode = t == 'dark';
      c.themeModeNotifier.value =
          NetThemeSchedule.resolve(_themeMode, c.clock.now());
    });
  }

  Future<void> _saveBool(String key, bool value) async {
    final c = AppScope.of(context);
    await c.settings.save(
      AppSetting(key: key, value: value.toString(), updatedAt: c.clock.now()),
    );
  }

  /// يفتح ورقة اختيار المظهر (نهار / ليل / تلقائي) ويطبّق الاختيار فورًا.
  Future<void> _openThemePicker() async {
    final picked = await ThemeModeSheet.show(context, _themeMode);
    if (!mounted || picked == null || picked == _themeMode) return;
    final c = AppScope.of(context);
    final previous = _themeMode;
    setState(() {
      _themeMode = picked;
      _darkMode = picked == NetThemeMode.dark;
    });
    c.themeModeNotifier.value = NetThemeSchedule.resolve(picked, c.clock.now());
    final result = await c.settings.save(
      AppSetting(
        key: SettingKeys.themeMode,
        value: NetThemeSchedule.encode(picked),
        updatedAt: c.clock.now(),
      ),
    );
    if (!mounted) return;
    if (result is Failure) {
      setState(() {
        _themeMode = previous;
        _darkMode = previous == NetThemeMode.dark;
      });
      c.themeModeNotifier.value = NetThemeSchedule.resolve(previous, c.clock.now());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تعذر حفظ إعداد المظهر',
            style: TextStyle(fontFamily: 'Tajawal'),
          ),
        ),
      );
      return;
    }
    NetThemeRawCache.raw = NetThemeSchedule.encode(picked);
  }

  Future<void> _openNetworkName() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NetworkNameSettingsScreen()),
    );
    if (mounted) await _load();
  }

  Future<void> _openLowStock() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LowStockSettingsScreen()),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          child: Column(
            children: [
              _Header(onBack: () => Navigator.of(context).maybePop()),
              Expanded(
                child: _loading
                    ? const AsyncLoadingView(skeleton: true, skeletonCount: 5)
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: KayanPalette.of(context).primary,
                        child: SettingsSearchScope(
                            query: _query,
                            child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                          children: [
                            _readinessCard(context),
                            _searchField(context),
                            if (!_anySectionVisible)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 24),
                                child: AsyncEmptyView(
                                  message: 'لا توجد إعدادات مطابقة للبحث',
                                  icon: Icons.search_off_rounded,
                                  hint: 'جرّب كلمة أخرى مثل: الرسائل، المظهر، المحافظ',
                                  compact: true,
                                ),
                              ),
                            if (_sectionVisible(_systemKeywords))
                              const SettingsSectionHeader(title: 'النظام'),
                            if (_sectionVisible(_systemKeywords))
                              SettingsGroupCard(
                              children: [
                                SettingsGroupNavRow(
                                  icon: Icons.badge_outlined,
                                  title: 'اسم الشبكة',
                                  subtitle: 'الاسم الحالي: $_networkName',
                                  searchText: 'النظام الشبكة الاسم',
                                  onTap: _openNetworkName,
                                ),
                                SettingsGroupSwitchRow(
                                  icon: Icons.check_circle_outline,
                                  title: 'المعالجة التلقائية للرسائل',
                                  subtitle:
                                      'الخدمة تعمل — يتم استقبال ومعالجة الرسائل تلقائياً',
                                  value: _autoSms,
                                  onChanged: (v) async {
                                    setState(() => _autoSms = v);
                                    await _saveBool(SettingKeys.smsAutoProcessingEnabled, v);
                                  },
                                ),
                                SettingsGroupSwitchRow(
                                  icon: Icons.filter_alt_outlined,
                                  title: 'معالجة مبالغ الفئات فقط',
                                  subtitle:
                                      'عند التفعيل، سيتم فقط معالجة رسائل المحافظ التي تطابق مبالغ الفئات المعرفة في النظام',
                                  value: _categoryOnly,
                                  onChanged: (v) async {
                                    setState(() => _categoryOnly = v);
                                    await _saveBool(SettingKeys.processCategoryAmountsOnly, v);
                                  },
                                ),
                                SettingsGroupSwitchRow(
                                  icon: Icons.history,
                                  title: 'معالجة الرسائل القديمة (عند التوقف)',
                                  subtitle:
                                      'تفعيل لمعالجة رسائل SMS التي وصلت أثناء إغلاق أو توقف التطبيق عند فتحه مجدداً',
                                  value: _oldMsgs,
                                  onChanged: (v) async {
                                    setState(() => _oldMsgs = v);
                                    await _saveBool(SettingKeys.processOldMessagesOnResume, v);
                                  },
                                ),
                                SettingsGroupSwitchRow(
                                  icon: Icons.notifications_active_outlined,
                                  title: 'تنبيه العمليات التي تتطلب تدخلاً',
                                  subtitle: _interventionAlert
                                      ? 'يصدر تنبيه صوتي عند وجود عملية معلّقة تحتاج تدخلاً يدوياً'
                                      : 'التنبيه الصوتي معطّل — الرسائل المعلّقة تظهر في القائمة دون صوت',
                                  value: _interventionAlert,
                                  onChanged: (v) async {
                                    setState(() => _interventionAlert = v);
                                    await _saveBool(SettingKeys.pendingAttentionAlertEnabled, v);
                                  },
                                ),
                                SettingsGroupSwitchRow(
                                  icon: Icons.card_giftcard_outlined,
                                  title: 'خدمة سلفني',
                                  subtitle: _salafni
                                      ? 'الميزة مفعلة — يتم استقبال ومعالجة طلبات سلفني آلياً للعملاء المؤهلين'
                                      : 'الميزة معطلة',
                                  value: _salafni,
                                  onChanged: (v) async {
                                    setState(() => _salafni = v);
                                    await _saveBool(SettingKeys.salafniEnabled, v);
                                  },
                                ),
                                SettingsGroupNavRow(
                                  icon: Icons.message_outlined,
                                  title: 'قوالب رسائل العملاء والعروض والنظام',
                                  subtitle: 'صيغ SMS الجاهزة للعملاء والعروض ونقاط البيع — قابلة للتعديل',
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const OutboundMessageTemplatesScreen(),
                                    ),
                                  ),
                                ),
                                if (_salafni)
                                  SettingsGroupNavRow(
                                    icon: Icons.sms_outlined,
                                    title: 'قوالب رسائل سلفني',
                                    subtitle: 'قبول / رفض / سداد',
                                    onTap: () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const SalafniTemplatesScreen(),
                                      ),
                                    ),
                                  ),
                                SettingsGroupNavRow(
                                  icon: Icons.notifications_active_outlined,
                                  title: 'تنبيهات انخفاض مخزون الكروت',
                                  subtitle:
                                      'سيتم تنبيهك عندما يقل مخزون أي فئة عن $_lowStock كرت',
                                  onTap: _openLowStock,
                                ),
                                SettingsGroupNavRow(
                                  icon: Icons.sim_card_outlined,
                                  title: 'إعدادات شرائح الاتصال',
                                  subtitle: 'إدارة شرائح القراءة والإرسال و Failover',
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => const SimSettingsScreen()),
                                  ),
                                ),
                                SettingsGroupNavRow(
                                  icon: Icons.health_and_safety_outlined,
                                  title: 'فحص النظام',
                                  subtitle:
                                      'التحقق من جاهزية أذونات النظام والتشغيل في الخلفية',
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => const SystemCheckScreen()),
                                  ),
                                ),
                              ],
                            ),
                            if (_sectionVisible(_licenseKeywords))
                              const SettingsSectionHeader(title: 'الترخيص'),
                            if (_sectionVisible(_licenseKeywords))
                            SettingsGroupCard(
                              children: [
                                SettingsGroupNavRow(
                                  icon: Icons.workspace_premium_outlined,
                                  title: 'تجديد الاشتراك',
                                  subtitle:
                                      'تجديد الترخيص أو إضافة رصيد SMS قبل انتهاء الباقة الحالية',
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const RenewSubscriptionScreen(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (_sectionVisible(_themeKeywords))
                              const SettingsSectionHeader(title: 'المظهر'),
                            if (_sectionVisible(_themeKeywords))
                            SettingsGroupCard(
                              children: [
                                SettingsGroupNavRow(
                                  icon: _darkMode
                                      ? Icons.dark_mode_rounded
                                      : Icons.light_mode_rounded,
                                  title: 'المظهر',
                                  subtitle:
                                      '${NetThemeSchedule.label(_themeMode)} — ${NetThemeSchedule.hint(_themeMode)}',
                                  searchText:
                                      'المظهر الثيم ليلي فاتح نهاري تلقائي دارك ${NetThemeSchedule.label(_themeMode)}',
                                  onTap: _openThemePicker,
                                ),
                              ],
                            ),
                            if (_sectionVisible(_walletsKeywords))
                              const SettingsSectionHeader(title: 'إعدادات المحافظ ونقاط البيع'),
                            if (_sectionVisible(_walletsKeywords))
                            SettingsGroupCard(
                              children: [
                                SettingsGroupNavRow(
                                  icon: Icons.account_balance_wallet_outlined,
                                  title: 'إدارة المحافظ ونقاط البيع',
                                  subtitle: 'إضافة وتعديل المحافظ ونقاط البيع',
                                  searchText: 'إعدادات المحافظ ونقاط البيع',
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => const WalletsPosScreen()),
                                  ),
                                ),
                                SettingsGroupNavRow(
                                  icon: Icons.science_outlined,
                                  title: 'محاكاة القوالب',
                                  subtitle: 'اختبار ومحاكاة استخراج بيانات الرسائل',
                                  searchText: 'المحاكاة محاكاة القوالب اختبار',
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const TemplateSimulationScreen(),
                                    ),
                                  ),
                                ),
                                SettingsGroupNavRow(
                                  icon: Icons.receipt_long_outlined,
                                  title: 'قوالب التحويل',
                                  subtitle: 'إدارة قوالب رسائل المحافظ وترتيبها',
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => const TemplatesScreen()),
                                  ),
                                ),
                                SettingsGroupNavRow(
                                  icon: Icons.notifications_outlined,
                                  title: 'إعدادات طلبات الرصيد لنقاط البيع',
                                  subtitle: 'تخصيص رمز طلب الرصيد، الحد اليومي وقالب الرد',
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const WalletNotificationSettingsScreen(),
                                    ),
                                  ),
                                ),
                                SettingsGroupSwitchRow(
                                  icon: Icons.summarize_outlined,
                                  title: 'إرسال ملخص العمليات اليومي تلقائياً',
                                  subtitle: _dailySummary
                                      ? 'ميزة رسالة الملخص اليومي مفعلة'
                                      : 'ميزة رسالة الملخص اليومي معطلة',
                                  value: _dailySummary,
                                  onChanged: (v) async {
                                    setState(() => _dailySummary = v);
                                    await _saveBool(SettingKeys.dailyOpsSummaryAutoSend, v);
                                  },
                                ),
                                SettingsGroupSwitchRow(
                                  icon: Icons.account_balance_outlined,
                                  title: 'التسوية التلقائية لنقاط البيع',
                                  subtitle: _autoPosSettlement
                                      ? 'التسوية التلقائية مفعلة'
                                      : 'التسوية التلقائية معطلة',
                                  value: _autoPosSettlement,
                                  onChanged: (v) async {
                                    setState(() => _autoPosSettlement = v);
                                    await _saveBool(SettingKeys.autoPosSettlementEnabled, v);
                                  },
                                ),
                              ],
                            ),
                            if (_sectionVisible(_maintenanceKeywords))
                              const SettingsSectionHeader(title: 'الصيانة'),
                            if (_sectionVisible(_maintenanceKeywords))
                            SettingsGroupCard(
                              children: [
                                SettingsGroupNavRow(
                                  icon: Icons.cleaning_services_outlined,
                                  title: 'تنظيف السجلات',
                                  searchText: 'الصيانة حذف السجلات',
                                  subtitle: 'حذف الرسائل القديمة والسجلات حسب سياسة الاحتفاظ',
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => const CleanLogsScreen()),
                                  ),
                                ),
                                SettingsGroupNavRow(
                                  icon: Icons.file_download_outlined,
                                  title: 'تصدير السجل',
                                  subtitle: 'تصدير سجل العمليات للتحليل أو الأرشفة',
                                  searchText: 'الصيانة الأرشفة أرشيف',
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => const ExportLedgerScreen()),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        )),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'رجوع',
            onPressed: onBack,
            icon: Icon(Icons.arrow_forward_rounded, color: scheme.onSurface),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'الإعدادات',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
                Text(
                  'تحكم كامل بالشبكة والتشغيل والمظهر',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}
