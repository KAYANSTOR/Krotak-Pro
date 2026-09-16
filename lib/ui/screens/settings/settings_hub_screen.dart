import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/setting.dart';
import '../../app_scope.dart';
import '../../routing/app_routes.dart';
import '../../theme/kayan_colors.dart';
import '../../widgets/settings/settings_cards.dart';
import '../../widgets/settings/settings_section_header.dart';
import '../system_check_screen.dart';
import '../wallets_pos_screen.dart';
import 'low_stock_settings_screen.dart';
import 'network_name_settings_screen.dart';
import 'renew_subscription_screen.dart';
import 'sim_settings_screen.dart';
import 'template_simulation_screen.dart';
import 'templates_screen.dart';
import 'wallet_notification_settings_screen.dart';

/// مركز الإعدادات — تصميم مطابق حرفياً لفيديو Z Net (كروت منفصلة + أقسام).
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
  bool _darkMode = false;
  bool _dailySummary = SettingDefaults.dailyOpsSummaryAutoSend;
  bool _autoPosSettlement = SettingDefaults.autoPosSettlementEnabled;
  int _lowStock = SettingDefaults.lowStockThreshold;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
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
      _dailySummary = SettingBool.read(daily, defaultValue: SettingDefaults.dailyOpsSummaryAutoSend);
      _autoPosSettlement = SettingBool.read(settle, defaultValue: SettingDefaults.autoPosSettlementEnabled);
      _lowStock = SettingInt.read(low, defaultValue: SettingDefaults.lowStockThreshold);
      final t = (theme ?? SettingDefaults.themeMode).toLowerCase();
      _darkMode = t == 'dark';
      if (t == 'dark') {
        c.themeModeNotifier.value = ThemeMode.dark;
      } else if (t == 'light') {
        c.themeModeNotifier.value = ThemeMode.light;
      }
    });
  }

  Future<void> _saveBool(String key, bool value) async {
    final c = AppScope.of(context);
    await c.settings.save(
      AppSetting(key: key, value: value.toString(), updatedAt: c.clock.now()),
    );
  }

  Future<void> _setDarkMode(bool enabled) async {
    final c = AppScope.of(context);
    final value = enabled ? 'dark' : 'light';
    await c.settings.save(
      AppSetting(key: SettingKeys.themeMode, value: value, updatedAt: c.clock.now()),
    );
    c.themeModeNotifier.value = enabled ? ThemeMode.dark : ThemeMode.light;
    setState(() => _darkMode = enabled);
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
        backgroundColor: KayanColors.appBackground,
        body: SafeArea(
          child: Column(
            children: [
              _Header(onBack: () => Navigator.of(context).maybePop()),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: KayanColors.primary,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                          children: [
                            const SettingsSectionHeader(title: 'النظام'),
                            SettingsNavCard(
                              icon: Icons.badge_outlined,
                              title: 'اسم الشبكة',
                              subtitle: 'الاسم الحالي: $_networkName',
                              onTap: _openNetworkName,
                            ),
                            SettingsSwitchCard(
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
                            SettingsSwitchCard(
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
                            SettingsSwitchCard(
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
                            SettingsSwitchCard(
                              icon: Icons.card_giftcard_outlined,
                              title: 'خدمة سلفني',
                              subtitle:
                                  'الميزة مفعلة — يتم استقبال ومعالجة طلبات سلفني آلياً للعملاء المؤهلين',
                              value: _salafni,
                              onChanged: (v) async {
                                setState(() => _salafni = v);
                                await _saveBool(SettingKeys.salafniEnabled, v);
                              },
                            ),
                            SettingsNavCard(
                              icon: Icons.notifications_active_outlined,
                              title: 'تنبيهات انخفاض مخزون الكروت',
                              subtitle:
                                  'سيتم تنبيهك عندما يقل مخزون أي فئة عن $_lowStock كرت',
                              onTap: _openLowStock,
                            ),
                            SettingsNavCard(
                              icon: Icons.sim_card_outlined,
                              title: 'إعدادات شرائح الاتصال',
                              subtitle: 'إدارة شرائح القراءة والإرسال و Failover',
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const SimSettingsScreen()),
                              ),
                            ),
                            SettingsNavCard(
                              icon: Icons.health_and_safety_outlined,
                              title: 'فحص النظام',
                              subtitle:
                                  'التحقق من جاهزية أذونات النظام والتشغيل في الخلفية',
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const SystemCheckScreen()),
                              ),
                            ),
                            const SettingsSectionHeader(title: 'الترخيص'),
                            SettingsNavCard(
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
                            const SettingsSectionHeader(title: 'المظهر'),
                            SettingsSwitchCard(
                              icon: Icons.dark_mode_outlined,
                              title: 'الوضع الداكن',
                              subtitle: _darkMode ? 'المظهر الداكن مفعل' : 'المظهر الفاتح مفعل',
                              value: _darkMode,
                              onChanged: _setDarkMode,
                            ),
                            const SettingsSectionHeader(title: 'إعدادات المحافظ ونقاط البيع'),
                            SettingsNavCard(
                              icon: Icons.account_balance_wallet_outlined,
                              title: 'إدارة المحافظ ونقاط البيع',
                              subtitle: 'إضافة وتعديل المحافظ ونقاط البيع',
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const WalletsPosScreen()),
                              ),
                            ),
                            SettingsNavCard(
                              icon: Icons.science_outlined,
                              title: 'محاكاة القوالب',
                              subtitle: 'اختبار ومحاكاة استخراج بيانات الرسائل',
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const TemplateSimulationScreen(),
                                ),
                              ),
                            ),
                            SettingsNavCard(
                              icon: Icons.receipt_long_outlined,
                              title: 'قوالب التحويل',
                              subtitle: 'إدارة قوالب رسائل المحافظ وترتيبها',
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const TemplatesScreen()),
                              ),
                            ),
                            SettingsNavCard(
                              icon: Icons.notifications_outlined,
                              title: 'إعدادات طلبات الرصيد لنقاط البيع',
                              subtitle: 'تخصيص رمز طلب الرصيد، الحد اليومي وقالب الرد',
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const WalletNotificationSettingsScreen(),
                                ),
                              ),
                            ),
                            SettingsSwitchCard(
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
                            SettingsSwitchCard(
                              icon: Icons.sync_alt,
                              title: 'التسوية التلقائية لنقاط البيع',
                              subtitle:
                                  'تسجيل تسوية مالية تلقائياً عند استلام إشعار من نقطة البيع',
                              value: _autoPosSettlement,
                              onChanged: (v) async {
                                setState(() => _autoPosSettlement = v);
                                await _saveBool(SettingKeys.autoPosSettlementEnabled, v);
                              },
                            ),
                            const SettingsSectionHeader(title: 'العمليات والمراجعة'),
                            SettingsNavCard(
                              icon: Icons.mark_email_unread_outlined,
                              title: 'الرسائل المعلّقة',
                              subtitle: 'رسائل تحتاج تأكيداً يدوياً قبل المعالجة',
                              onTap: () => AppRoutes.openPendingMessages(context),
                            ),
                            SettingsNavCard(
                              icon: Icons.refresh,
                              title: 'الرسائل الفاشلة / إعادة المحاولة',
                              subtitle: 'إعادة محاولة الرسائل التي فشل إرسالها أو معالجتها',
                              onTap: () => AppRoutes.openFailedMessages(context),
                            ),
                            SettingsNavCard(
                              icon: Icons.block_outlined,
                              title: 'الرسائل المرفوضة',
                              subtitle: 'سجل الرسائل التي رُفضت وفق قواعد النظام',
                              onTap: () => AppRoutes.openRejectedMessages(context),
                            ),
                          ],
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_forward, color: KayanColors.textPrimary),
            tooltip: 'رجوع',
          ),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'الإعدادات',
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: KayanColors.textPrimary,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'تخصيص النظام وإدارة البيانات',
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 13,
                    color: KayanColors.textSecondary,
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
