import 'package:flutter/material.dart';

import '../../../core/app_brand.dart';
import '../../../core/result.dart';
import '../../../domain/entities/setting.dart';
import '../../app_scope.dart';
import '../../theme/kayan_palette.dart';
import '../../theme/net_semantic_colors.dart';
import '../../theme/net_theme_schedule.dart';
import '../../theme/net_tokens.dart';
import '../../widgets/async_views.dart';
import '../../widgets/dashboard/theme_mode_sheet.dart';
import '../../widgets/net/net_surface_card.dart';
import '../../widgets/settings/settings_cards.dart';
import '../../widgets/settings/settings_section_header.dart';
import '../pos_screen.dart';
import '../system_check_screen.dart';
import '../wallets_screen.dart';
import 'backup_restore_screen.dart';
import 'clean_logs_screen.dart';
import 'deep_clean_screen.dart';
import 'export_ledger_screen.dart';
import 'low_stock_settings_screen.dart';
import 'network_name_settings_screen.dart';
import 'renew_subscription_screen.dart';
import 'outbound_message_templates_screen.dart';
import 'sim_settings_screen.dart';
import 'template_simulation_screen.dart';
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
  bool _posBalanceRequests = SettingDefaults.posBalanceRequestsEnabled;
  int _lowStock = SettingDefaults.lowStockThreshold;
  int _posBalanceLimit = SettingDefaults.posBalanceRequestDailyLimit;
  String? _lastRecoveryAt;

  final _searchCtrl = TextEditingController();
  String _query = '';

  static const _systemKeywords =
      'اسم الشبكة شرائح الاتصال المعالجة التلقائية الفئات مبالغ الرسائل القديمة تنبيه العمليات سلفني انخفاض مخزون الكروت فحص النظام جاهزية الأذونات';
  static const _licenseKeywords = 'تجديد الاشتراك الترخيص رصيد الرسائل الباقة';
  static const _themeKeywords = 'الوضع الداكن المظهر الثيم ليلي فاتح';
  static const _messagesKeywords =
      'الرسائل القوالب صيغ محاكاة القوالب قوالب رسائل العملاء العروض النظام سلفني SMS الصادرة';
  static const _walletsKeywords =
      'المحافظ نقاط البيع إشعارات المحافظ طلبات رصيد نقاط البيع حد يومي ملخص العمليات اليومي التسوية التلقائية مصادر الإشعارات الحسابات سقف الدين قوالب المحفظة';
  static const _maintenanceKeywords = 'تنظيف السجلات تصدير السجل الأرشفة نسخ احتياطي استعادة بيانات تنظيف عميق فهارس';
  static const _aboutKeywords =
      'عن التطبيق المبرمج الحقوق كيان سوفت إصدار كروتك ${AppBrand.latinName} الموقع';

  bool _sectionVisible(String keywords) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return keywords.toLowerCase().contains(q);
  }

  bool get _anySectionVisible =>
      _sectionVisible(_systemKeywords) ||
      _sectionVisible(_licenseKeywords) ||
      _sectionVisible(_themeKeywords) ||
      _sectionVisible(_messagesKeywords) ||
      _sectionVisible(_walletsKeywords) ||
      _sectionVisible(_maintenanceKeywords) ||
      _sectionVisible(_aboutKeywords);

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
        style: TextStyle(fontFamily: NetTypography.family, color: palette.textPrimary),
        decoration: InputDecoration(
          hintText: 'ابحث في الإعدادات...',
          hintStyle: TextStyle(fontFamily: NetTypography.family, color: palette.textTertiary, fontSize: 13),
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
          border: OutlineInputBorder(borderRadius: NetRadii.pillAll, borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: NetRadii.pillAll, borderSide: BorderSide(color: palette.border)),
          focusedBorder: OutlineInputBorder(borderRadius: NetRadii.pillAll, borderSide: BorderSide(color: palette.primary, width: 1.4)),
        ),
      ),
    );
  }

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
          Row(children: [
            Icon(Icons.health_and_safety_rounded, size: NetSizes.iconSm, color: palette.primary),
            const SizedBox(width: NetSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('جاهزية التشغيل', style: TextStyle(fontFamily: NetTypography.family, fontWeight: FontWeight.w800, fontSize: 14.5, color: palette.textPrimary)),
                  Text(
                    _lastRecoveryAt == null
                        ? 'ملخص سريع — لم تُسجَّل بعد دورة استرداد. التفاصيل من «فحص النظام»'
                        : 'آخر دورة استرداد/تسليم: ${_formatRecoveryAt(_lastRecoveryAt!)}',
                    style: TextStyle(fontFamily: NetTypography.family, fontSize: 11.5, color: palette.textSecondary),
                  ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: NetSpacing.sm),
          Wrap(
            spacing: NetSpacing.sm,
            runSpacing: NetSpacing.sm,
            children: [
              for (final pill in pills)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: NetSpacing.sm, vertical: NetSpacing.xs),
                  decoration: BoxDecoration(color: pill.ok ? net.successContainer : palette.surfaceVariant, borderRadius: NetRadii.pillAll),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(pill.ok ? Icons.check_circle_rounded : Icons.cancel_outlined, size: 13, color: pill.ok ? net.success : palette.textSecondary),
                    const SizedBox(width: NetSpacing.xs),
                    Text(pill.label, style: TextStyle(fontFamily: NetTypography.family, fontSize: 11.5, fontWeight: FontWeight.w700, color: pill.ok ? net.success : palette.textSecondary)),
                  ]),
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
    final posBalance = await read(SettingKeys.posBalanceRequestsEnabled);
    final low = await read(SettingKeys.lowStockThreshold);
    final posLimit = await read(SettingKeys.posBalanceRequestDailyLimit);
    final lastRec = await read(SettingKeys.lastRecoveryPassAt);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (name != null && name.trim().isNotEmpty) _networkName = name.trim();
      _autoSms = SettingBool.read(auto, defaultValue: SettingDefaults.smsAutoProcessingEnabled);
      _categoryOnly = SettingBool.read(cat, defaultValue: SettingDefaults.processCategoryAmountsOnly);
      _oldMsgs = SettingBool.read(old, defaultValue: SettingDefaults.processOldMessagesOnResume);
      _salafni = SettingBool.read(sal, defaultValue: SettingDefaults.salafniEnabled);
      _interventionAlert = SettingBool.read(intervention, defaultValue: SettingDefaults.pendingAttentionAlertEnabled);
      _dailySummary = SettingBool.read(daily, defaultValue: SettingDefaults.dailyOpsSummaryAutoSend);
      _autoPosSettlement = SettingBool.read(settle, defaultValue: SettingDefaults.autoPosSettlementEnabled);
      _posBalanceRequests = SettingBool.read(posBalance, defaultValue: SettingDefaults.posBalanceRequestsEnabled);
      _lowStock = SettingInt.read(low, defaultValue: SettingDefaults.lowStockThreshold);
      _posBalanceLimit = SettingInt.read(posLimit, defaultValue: SettingDefaults.posBalanceRequestDailyLimit);
      _lastRecoveryAt = lastRec?.trim().isEmpty == true ? null : lastRec;
      final t = (theme ?? SettingDefaults.themeMode).toLowerCase();
      _themeMode = NetThemeSchedule.parse(theme);
      _darkMode = t == 'dark';
      c.themeModeNotifier.value = NetThemeSchedule.resolve(_themeMode, c.clock.now());
    });
  }

  Future<void> _saveBool(String key, bool value) async {
    final c = AppScope.of(context);
    await c.settings.save(AppSetting(key: key, value: value.toString(), updatedAt: c.clock.now()));
  }

  Future<void> _openPosBalanceLimit() async {
    final controller = TextEditingController(text: _posBalanceLimit.toString());
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('الحد اليومي لطلبات رصيد نقاط البيع'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'عدد الطلبات لكل نقطة بيع'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(context, int.tryParse(controller.text.trim())),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || value == null || value < 1) return;
    final c = AppScope.of(context);
    setState(() => _posBalanceLimit = value);
    await c.settings.save(AppSetting(
      key: SettingKeys.posBalanceRequestDailyLimit,
      value: value.toString(),
      updatedAt: c.clock.now(),
    ));
  }

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
    final result = await c.settings.save(AppSetting(key: SettingKeys.themeMode, value: NetThemeSchedule.encode(picked), updatedAt: c.clock.now()));
    if (!mounted) return;
    if (result is Failure) {
      setState(() {
        _themeMode = previous;
        _darkMode = previous == NetThemeMode.dark;
      });
      c.themeModeNotifier.value = NetThemeSchedule.resolve(previous, c.clock.now());
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر حفظ إعداد المظهر', style: TextStyle(fontFamily: 'Tajawal'))));
      return;
    }
    NetThemeRawCache.raw = NetThemeSchedule.encode(picked);
  }

  String _formatRecoveryAt(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    final local = dt.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/${local.year} $hour:$minute';
  }
  Future<void> _openNetworkName() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NetworkNameSettingsScreen()));
    if (mounted) await _load();
  }

  Future<void> _openLowStock() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LowStockSettingsScreen()));
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
                                  child: AsyncEmptyView(message: 'لا توجد إعدادات مطابقة للبحث', icon: Icons.search_off_rounded, hint: 'جرّب كلمة أخرى مثل: الرسائل، المظهر، المحافظ', compact: true),
                                ),
                              if (_sectionVisible(_systemKeywords)) const SettingsSectionHeader(title: 'النظام'),
                              if (_sectionVisible(_systemKeywords))
                                SettingsGroupCard(children: [
                                  SettingsGroupNavRow(icon: Icons.badge_outlined, title: 'اسم الشبكة', subtitle: 'الاسم الحالي: '+_networkName, searchText: 'النظام الشبكة الاسم', onTap: _openNetworkName),
                                  SettingsGroupSwitchRow(icon: Icons.check_circle_outline, title: 'المعالجة التلقائية للرسائل', subtitle: _autoSms
                                      ? 'مفعّل أثناء تشغيل التطبيق — الاستقبال في الخلفية يعتمد على أذونات الجهاز وOEM'
                                      : 'متوقف — تُحفظ الرسائل دون معالجة تجارية', value: _autoSms, onChanged: (v) async { setState(() => _autoSms = v); await _saveBool(SettingKeys.smsAutoProcessingEnabled, v); }),
                                  SettingsGroupSwitchRow(icon: Icons.filter_alt_outlined, title: 'معالجة مبالغ الفئات فقط', subtitle: 'عند التفعيل، سيتم فقط معالجة رسائل المحافظ التي تطابق مبالغ الفئات المعرفة في النظام', value: _categoryOnly, onChanged: (v) async { setState(() => _categoryOnly = v); await _saveBool(SettingKeys.processCategoryAmountsOnly, v); }),
                                  SettingsGroupSwitchRow(icon: Icons.history, title: 'معالجة الرسائل القديمة (عند التوقف)', subtitle: 'عند فتح التطبيق مجدداً فقط — لا تضمن المعالجة والتطبيق مغلق أو بعد Force-stop', value: _oldMsgs, onChanged: (v) async { setState(() => _oldMsgs = v); await _saveBool(SettingKeys.processOldMessagesOnResume, v); }),
                                  SettingsGroupSwitchRow(icon: Icons.notifications_active_outlined, title: 'تنبيه العمليات التي تتطلب تدخلاً', subtitle: _interventionAlert ? 'يصدر تنبيه صوتي عند وجود عملية معلّقة تحتاج تدخلاً يدوياً' : 'التنبيه الصوتي معطّل — الرسائل المعلّقة تظهر في القائمة دون صوت', value: _interventionAlert, onChanged: (v) async { setState(() => _interventionAlert = v); await _saveBool(SettingKeys.pendingAttentionAlertEnabled, v); }),
                                  SettingsGroupNavRow(icon: Icons.notifications_active_outlined, title: 'تنبيهات انخفاض مخزون الكروت', subtitle: 'سيتم تنبيهك عندما يقل مخزون أي فئة عن '+_lowStock.toString()+' كرت', onTap: _openLowStock),
                                  SettingsGroupNavRow(icon: Icons.sim_card_outlined, title: 'شرائح الاتصال', subtitle: 'اختيار شريحة الاستقبال والإرسال', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SimSettingsScreen()))),
                                  SettingsGroupNavRow(icon: Icons.health_and_safety_outlined, title: 'فحص النظام', subtitle: 'جاهزية الأذونات والخدمات', searchText: 'فحص جاهزية الأذونات الخدمات', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SystemCheckScreen()))),
                                ]),
                              if (_sectionVisible(_messagesKeywords)) const SettingsSectionHeader(title: 'الرسائل والقوالب'),
                              if (_sectionVisible(_messagesKeywords))
                                SettingsGroupCard(children: [
                                  SettingsGroupNavRow(icon: Icons.message_outlined, title: 'قوالب الرسائل', subtitle: 'رسائل العملاء والعروض والنظام ونقاط البيع وسلفني — في شاشة واحدة بتبويبات', searchText: 'قوالب رسائل العملاء العروض النظام سلفني نقاط البيع', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OutboundMessageTemplatesScreen()))),
                                  SettingsGroupNavRow(icon: Icons.science_outlined, title: 'محاكاة القوالب', subtitle: 'اختبار مطابقة الرسائل الواردة قبل التشغيل', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TemplateSimulationScreen()))),
                                  SettingsGroupSwitchRow(icon: Icons.card_giftcard_outlined, title: 'خدمة سلفني', subtitle: _salafni ? 'الميزة مفعلة — يتم استقبال ومعالجة طلبات سلفني آلياً للعملاء المؤهلين' : 'الميزة متوقفة — طلبات سلفني لا تُعالج', value: _salafni, onChanged: (v) async { setState(() => _salafni = v); await _saveBool(SettingKeys.salafniEnabled, v); }),
                                ]),
                              if (_sectionVisible(_walletsKeywords)) const SettingsSectionHeader(title: 'المحافظ ونقاط البيع'),
                              if (_sectionVisible(_walletsKeywords))
                                SettingsGroupCard(children: [
                                  SettingsGroupNavRow(icon: Icons.account_balance_wallet_outlined, title: 'إدارة المحافظ', subtitle: 'إضافة وتفعيل المحافظ وطريقة قراءة الدفع', searchText: 'المحافظ جيب جوالي ون كاش فلوسك', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WalletsScreen()))),
                                  SettingsGroupNavRow(icon: Icons.storefront_outlined, title: 'نقاط البيع', subtitle: 'حسابات النقاط وسقف الدين وقوالب رسائلها', searchText: 'نقاط البيع الحسابات القوالب الرصيد', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PosScreen()))),
                                  SettingsGroupNavRow(icon: Icons.notifications_none_outlined, title: 'إشعارات المحافظ', subtitle: 'مصادر إشعارات التطبيقات ومنح إذن الوصول', searchText: 'إشعارات المحافظ مصادر الوصول', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WalletNotificationSettingsScreen()))),
                                  SettingsGroupSwitchRow(icon: Icons.account_balance_outlined, title: 'طلبات رصيد نقاط البيع', subtitle: _posBalanceRequests ? 'مفعّل — يتم الرد تلقائياً على طلب رصيد نقطة البيع برسالة تحتوي الرصيد والدين' : 'متوقف — طلبات رصيد نقاط البيع تُترك للمراجعة اليدوية', value: _posBalanceRequests, onChanged: (v) async { setState(() => _posBalanceRequests = v); await _saveBool(SettingKeys.posBalanceRequestsEnabled, v); }),
                                  SettingsGroupNavRow(icon: Icons.pin_outlined, title: 'الحد اليومي لطلبات رصيد نقاط البيع', subtitle: 'الحد الحالي: '+_posBalanceLimit.toString()+' طلب يومياً لكل نقطة بيع', searchText: 'حد يومي طلبات رصيد نقاط البيع', onTap: _openPosBalanceLimit),
                                  SettingsGroupSwitchRow(icon: Icons.summarize_outlined, title: 'ملخص العمليات اليومي', subtitle: _dailySummary ? 'مفعّل — سيتم إرسال ملخص يومي الساعة 12 ليلاً لكل عملاء نقاط البيع' : 'متوقف — لن تُرسل ملخصات يومية لعملاء نقاط البيع', value: _dailySummary, onChanged: (v) async { setState(() => _dailySummary = v); await _saveBool(SettingKeys.dailyOpsSummaryAutoSend, v); }),
                                  SettingsGroupSwitchRow(icon: Icons.handshake_outlined, title: 'التسوية التلقائية', subtitle: _autoPosSettlement ? 'مفعّل — سيتم التسوية التلقائية لنقاط البيع عند استلام حوالة عبر المحافظ إلى النظام' : 'متوقف — تُسجَّل الحوالات دون تسوية تلقائية لحسابات نقاط البيع', value: _autoPosSettlement, onChanged: (v) async { setState(() => _autoPosSettlement = v); await _saveBool(SettingKeys.autoPosSettlementEnabled, v); }),
                                ]),
                              if (_sectionVisible(_themeKeywords)) const SettingsSectionHeader(title: 'المظهر'),
                              if (_sectionVisible(_themeKeywords))
                                SettingsGroupCard(children: [
                                  SettingsGroupNavRow(icon: Icons.dark_mode_outlined, title: 'الوضع الداكن', subtitle: NetThemeSchedule.label(_themeMode), onTap: _openThemePicker),
                                ]),
                              if (_sectionVisible(_licenseKeywords)) const SettingsSectionHeader(title: 'الاشتراك'),
                              if (_sectionVisible(_licenseKeywords))
                                SettingsGroupCard(children: [
                                  SettingsGroupNavRow(icon: Icons.workspace_premium_outlined, title: 'تجديد الاشتراك', subtitle: 'الباقة ورصيد الرسائل', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RenewSubscriptionScreen()))),
                                ]),
                              if (_sectionVisible(_maintenanceKeywords)) const SettingsSectionHeader(title: 'الصيانة'),
                              if (_sectionVisible(_maintenanceKeywords))
                                SettingsGroupCard(children: [
                                  SettingsGroupNavRow(
                                    icon: Icons.backup_outlined,
                                    title: 'النسخ الاحتياطي واستعادة البيانات',
                                    subtitle: 'إعدادات + قاعدة البيانات كاملة · تشفير AES-GCM (.krt)',
                                    searchText: 'نسخ احتياطي استعادة بيانات',
                                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BackupRestoreScreen())),
                                  ),
                                  SettingsGroupNavRow(icon: Icons.cleaning_services_outlined, title: 'تنظيف السجلات', subtitle: 'يدوي فقط — لا يوجد تنظيف دوري تلقائي في الخلفية', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CleanLogsScreen()))),
                                  SettingsGroupNavRow(icon: Icons.auto_fix_high_outlined, title: 'تنظيف عميق للنظام', subtitle: 'إعادة بناء فهارس قاعدة البيانات لتحرير المساحة وتسريع الأداء', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DeepCleanScreen()))),
                                  SettingsGroupNavRow(icon: Icons.upload_file_outlined, title: 'تصدير السجل', subtitle: 'تصدير دفتر الحسابات', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ExportLedgerScreen()))),
                                ]),
                              if (_sectionVisible(_aboutKeywords)) const SettingsSectionHeader(title: 'عن التطبيق'),
                              if (_sectionVisible(_aboutKeywords))
                                const _AboutAppCard(),
                            ],
                          ),
                        ),
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
    final palette = KayanPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          IconButton(onPressed: onBack, icon: Icon(Icons.arrow_forward_rounded, color: palette.textPrimary)),
          Expanded(
            child: Column(
              children: [
                Text('الإعدادات', textAlign: TextAlign.center, style: TextStyle(fontFamily: NetTypography.family, fontWeight: FontWeight.w800, fontSize: 18, color: palette.textPrimary)),
                Text('إعدادات النظام والتشغيل', textAlign: TextAlign.center, style: TextStyle(fontFamily: NetTypography.family, fontSize: 12, color: palette.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _AboutAppCard extends StatelessWidget {
  const _AboutAppCard();

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return NetSurfaceCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Column(
        children: [
          // أيقونة التطبيق الفعلية فوق اسم التطبيق.
          Container(
            width: 72,
            height: 72,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: palette.primary.withValues(alpha: 0.25)),
            ),
            child: Image.asset(
              'assets/icon/app_icon.png',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                alignment: Alignment.center,
                color: palette.primary.withValues(alpha: 0.12),
                child: Icon(Icons.wifi_tethering_rounded, color: palette.primary, size: 30),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            AppBrand.name,
            style: TextStyle(
              fontFamily: NetTypography.family,
              fontWeight: FontWeight.w800,
              fontSize: 17,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'الإصدار ${AppBrand.version} (${AppBrand.latinName})',
            style: TextStyle(
              fontFamily: NetTypography.family,
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'المبرمج: ${AppBrand.developer}',
            style: TextStyle(
              fontFamily: NetTypography.family,
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            AppBrand.company,
            style: TextStyle(
              fontFamily: NetTypography.family,
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'ت: ${AppBrand.phone}',
            style: TextStyle(
              fontFamily: NetTypography.family,
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'جميع الحقوق محفوظة © ${AppBrand.company}\n${AppBrand.website}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: NetTypography.family,
              fontWeight: FontWeight.w500,
              fontSize: 13,
              color: palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
