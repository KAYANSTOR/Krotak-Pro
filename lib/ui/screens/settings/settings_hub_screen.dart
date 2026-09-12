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
import 'battery_settings_screen.dart';
import 'clean_logs_screen.dart';
import 'export_ledger_screen.dart';
import 'sim_settings_screen.dart';
import 'templates_screen.dart';

/// Settings hub — PD-07 sections + PD-02 network name card (S1 + S2).
///
/// Switch values persist via [SettingsRepository]. Domain effects for SMS
/// auto-processing / category filter / recovery are wired in S3.
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
      if (r is Failure<AppSetting?>) return null;
      return (r as Success<AppSetting?>).value?.value;
    }

    try {
      final network = await read(SettingKeys.networkName);
      final auto = await read(SettingKeys.smsAutoProcessingEnabled);
      final cat = await read(SettingKeys.processCategoryAmountsOnly);
      final old = await read(SettingKeys.processOldMessagesOnResume);
      final pos = await read(SettingKeys.posBalanceRequestsEnabled);
      final daily = await read(SettingKeys.dailyOpsSummaryAutoSend);
      final theme = await read(SettingKeys.themeMode);

      if (!mounted) return;
      setState(() {
        _loading = false;
        _networkName =
            (network != null && network.trim().isNotEmpty)
                ? network.trim()
                : SettingDefaults.networkName;
        _autoProcessing = _parseBool(auto, SettingDefaults.smsAutoProcessingEnabled);
        _categoryOnly = _parseBool(cat, SettingDefaults.processCategoryAmountsOnly);
        _oldMessages = _parseBool(old, SettingDefaults.processOldMessagesOnResume);
        _posBalanceRequests =
            _parseBool(pos, SettingDefaults.posBalanceRequestsEnabled);
        _dailySummary = _parseBool(daily, SettingDefaults.dailyOpsSummaryAutoSend);
        _darkTheme = (theme ?? SettingDefaults.themeMode) == 'dark';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل الإعدادات';
      });
    }
  }

  static bool _parseBool(String? raw, bool fallback) {
    if (raw == null) return fallback;
    final v = raw.trim().toLowerCase();
    if (v == 'true' || v == '1') return true;
    if (v == 'false' || v == '0') return false;
    return fallback;
  }

  Future<void> _saveBool(String key, bool value, void Function(bool) applyLocal) async {
    final previous = switch (key) {
      SettingKeys.smsAutoProcessingEnabled => _autoProcessing,
      SettingKeys.processCategoryAmountsOnly => _categoryOnly,
      SettingKeys.processOldMessagesOnResume => _oldMessages,
      SettingKeys.posBalanceRequestsEnabled => _posBalanceRequests,
      SettingKeys.dailyOpsSummaryAutoSend => _dailySummary,
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
    if (result is Failure) {
      setState(() => applyLocal(previous));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تعذر حفظ الإعداد',
            style: TextStyle(fontFamily: 'Tajawal'),
          ),
        ),
      );
    }
  }

  Future<void> _saveTheme(bool dark) async {
    final previous = _darkTheme;
    setState(() {
      _busyKeys.add(SettingKeys.themeMode);
      _darkTheme = dark;
    });
    final c = AppScope.of(context);
    final result = await c.settings.save(
      AppSetting(
        key: SettingKeys.themeMode,
        value: dark ? 'dark' : 'light',
        updatedAt: c.clock.now(),
      ),
    );
    if (!mounted) return;
    setState(() => _busyKeys.remove(SettingKeys.themeMode));
    if (result is Failure) {
      setState(() => _darkTheme = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تعذر حفظ المظهر',
            style: TextStyle(fontFamily: 'Tajawal'),
          ),
        ),
      );
      return;
    }
    c.themeModeNotifier.value = dark ? ThemeMode.dark : ThemeMode.light;
  }

  Future<void> _editNetworkName() async {
    final saved = await NetworkNameEditSheet.show(
      context,
      initialName: _networkName,
    );
    if (saved != null && mounted) {
      setState(() => _networkName = saved);
    }
  }

  void _open(Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
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
                        const SettingsSectionHeader(title: 'النظام'),
                        SettingsNavCard(
                          icon: Icons.badge_outlined,
                          title: 'اسم الشبكة',
                          subtitle: 'يظهر في لوحة التحكم ورسائل SMS للعملاء',
                          value: _networkName,
                          onTap: _editNetworkName,
                        ),
                        SettingsSwitchCard(
                          icon: Icons.autorenew,
                          title: 'المعالجة التلقائية للرسائل',
                          subtitle:
                              'تحليل وإيداع وحجز وإرسال تلقائي — مستقل عن استقبال SMS',
                          value: _autoProcessing,
                          enabled: !_busyKeys.contains(
                            SettingKeys.smsAutoProcessingEnabled,
                          ),
                          onChanged: (v) => _saveBool(
                            SettingKeys.smsAutoProcessingEnabled,
                            v,
                            (x) => _autoProcessing = x,
                          ),
                        ),
                        SettingsSwitchCard(
                          icon: Icons.category_outlined,
                          title: 'معالجة مبالغ الفئات فقط',
                          subtitle:
                              'المبلغ غير المطابق لفئة يذهب للمعلّقة لاعتماده أو رفضه',
                          value: _categoryOnly,
                          enabled: !_busyKeys.contains(
                            SettingKeys.processCategoryAmountsOnly,
                          ),
                          onChanged: (v) => _saveBool(
                            SettingKeys.processCategoryAmountsOnly,
                            v,
                            (x) => _categoryOnly = x,
                          ),
                        ),
                        SettingsSwitchCard(
                          icon: Icons.history,
                          title: 'معالجة الرسائل القديمة عند التوقف',
                          subtitle:
                              'استعادة ومعالجة ما وصل أثناء توقف الجهاز أو التطبيق',
                          value: _oldMessages,
                          enabled: !_busyKeys.contains(
                            SettingKeys.processOldMessagesOnResume,
                          ),
                          onChanged: (v) => _saveBool(
                            SettingKeys.processOldMessagesOnResume,
                            v,
                            (x) => _oldMessages = x,
                          ),
                        ),
                        const SettingsSectionHeader(title: 'الجهاز والرسائل'),
                        SettingsNavCard(
                          icon: Icons.sim_card_outlined,
                          title: 'إعدادات الشريحة',
                          subtitle: 'فتحة SIM واستقبال رسائل SMS',
                          onTap: () => _open(const SimSettingsScreen()),
                        ),
                        SettingsNavCard(
                          icon: Icons.battery_saver_outlined,
                          title: 'البطارية',
                          subtitle: 'توصيات تحسين البطارية للعمل في الخلفية',
                          onTap: () => _open(const BatterySettingsScreen()),
                        ),
                        const SettingsSectionHeader(title: 'المظهر'),
                        SettingsSwitchCard(
                          icon: Icons.dark_mode_outlined,
                          title: 'الوضع الداكن',
                          subtitle: 'إيقافه يعيد الوضع الفاتح (الافتراضي)',
                          value: _darkTheme,
                          enabled: !_busyKeys.contains(SettingKeys.themeMode),
                          onChanged: _saveTheme,
                        ),
                        const SettingsSectionHeader(title: 'نقاط البيع والعمليات'),
                        SettingsSwitchCard(
                          icon: Icons.point_of_sale_outlined,
                          title: 'طلبات الرصيد لنقاط البيع',
                          subtitle:
                              'التعامل مع طلبات الرصيد الواردة من نقاط البيع',
                          value: _posBalanceRequests,
                          enabled: !_busyKeys.contains(
                            SettingKeys.posBalanceRequestsEnabled,
                          ),
                          onChanged: (v) => _saveBool(
                            SettingKeys.posBalanceRequestsEnabled,
                            v,
                            (x) => _posBalanceRequests = x,
                          ),
                        ),
                        SettingsSwitchCard(
                          icon: Icons.summarize_outlined,
                          title: 'إرسال ملخص العمليات اليومية تلقائيًا',
                          subtitle:
                              'ملخص يومي تلقائي — تفاصيل الوقت والجهة لاحقًا',
                          value: _dailySummary,
                          enabled: !_busyKeys.contains(
                            SettingKeys.dailyOpsSummaryAutoSend,
                          ),
                          onChanged: (v) => _saveBool(
                            SettingKeys.dailyOpsSummaryAutoSend,
                            v,
                            (x) => _dailySummary = x,
                          ),
                        ),
                        const SettingsSectionHeader(title: 'البيانات والقوالب'),
                        SettingsNavCard(
                          icon: Icons.pattern,
                          title: 'قوالب التحويل',
                          subtitle: 'أنماط تحليل رسائل التحويل الواردة',
                          onTap: () => _open(const TemplatesScreen()),
                        ),
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
                        const SettingsSectionHeader(title: 'المساعدة'),
                        SettingsNavCard(
                          icon: Icons.help_outline,
                          title: 'مركز المساعدة',
                          subtitle: 'شرح النظام والسلوك المعتمد',
                          onTap: () => _open(const HelpCenterScreen()),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }
}
