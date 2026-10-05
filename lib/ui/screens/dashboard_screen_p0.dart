part of 'dashboard_screen.dart';

/// لوحة التحكم — مطابقة بصرية وسلوكية لفيديو Z Net (المرحلة 1).
///
/// البيانات تُقرأ من نفس الخدمات والمستودعات كما قبل التحديث البصري؛
/// التغييرات محصورة في العرض والتنسيق والحركة.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    this.onNavigateToTab,
    this.refreshSignal,
    this.onMutated,
    this.onAttentionChanged,
  });

  /// عدد الرسائل التي تحتاج تدخلاً — يرفعه الشريط السفلي كشارة تنبيه حية.
  final ValueChanged<int>? onAttentionChanged;

  final ValueChanged<String>? onNavigateToTab;

  /// Bumped by the shell when another screen mutates data this dashboard shows.
  final ValueListenable<int>? refreshSignal;

  /// Called after this screen performs a mutation (direct sale, POS settlement,
  /// customer creation) so the shell can fan out one shared refresh to every
  /// kept-alive tab. Replaces per-screen reloads that left other tabs stale.
  final VoidCallback? onMutated;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _loading = true;
  String? _error;
  String _networkName = SettingDefaults.networkName;
  String _dateLabel = '';
  String? _subscriptionLabel;
  int? _remainingMessages;
  int _attentionMessagesCount = 0;
  int _rejectedCount = 0;
  int _customerBalanceMinor = 0;
  int _accountsCount = 0;
  int _availableCards = 0;
  int _dailySalesMinor = 0;
  int _dailyCards = 0;
  int _monthlySalesMinor = 0;
  int _monthlyCards = 0;
  bool _autoProcessing = SettingDefaults.smsAutoProcessingEnabled;
  bool _categoryOnly = SettingDefaults.processCategoryAmountsOnly;
  List<Transaction> _recent = const [];
  List<({String name, int available})> _lowStock = const [];
  SystemHealthSnapshot? _health;

  /// Locally dismissed alert banners (presentation-only state).
  final Set<String> _dismissedAlerts = <String>{};

  static const _attentionStatuses = <MessageProcessingStatus>[
    MessageProcessingStatus.received,
    MessageProcessingStatus.parsed,
    MessageProcessingStatus.pending,
  ];

  @override
  void initState() {
    super.initState();
    widget.refreshSignal?.addListener(_onExternalRefresh);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    widget.refreshSignal?.removeListener(_onExternalRefresh);
    super.dispose();
  }

  void _onExternalRefresh() {
    if (!mounted) return;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final c = AppScope.of(context);
    final now = c.clock.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final monthStart = DateTime(now.year, now.month, 1);
    final dateLabel = formatArabicDashboardDate(now);

    try {
      final customers = await c.customers.search('');
      final available = await c.cards.listByStatus(domain.CardStatus.available);
      final dailySales = await c.sales.listCompletedBetween(dayStart, now);
      final monthlySales = await c.sales.listCompletedBetween(monthStart, now);
      final recent = await c.transactions.listRecent(limit: 10);
      final totalBalance =
          await c.balanceService.getTotalOutstanding(currencyCode: 'YER');
      final networkSetting = await c.settings.find(SettingKeys.networkName);
      final autoSetting =
          await c.settings.find(SettingKeys.smsAutoProcessingEnabled);
      final catOnlySetting =
          await c.settings.find(SettingKeys.processCategoryAmountsOnly);
      final healthResult = await c.systemHealth.check();

      // شريط الاشتراك (عرض فقط) — من الترخيص الفعلي إن وُجد.
      String? subscriptionLabel;
      int? remainingMessages;
      final lic = await c.licenseService.current();
      if (lic is Success<domain.License>) {
        final license = lic.value;
        final exp = license.expiresAt;
        if (exp != null) {
          final d = formatArabicDashboardDate(exp.toLocal());
