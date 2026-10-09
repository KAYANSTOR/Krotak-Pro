/// قياس فتح الشاشات في الذاكرة فقط.
///
/// لا يُحفظ في قاعدة البيانات، ولا يُستخدم كدليل جهاز أو كميزانية معتمدة.
/// كل عينة تسجّل لحظة الطلب، ثم أول إطار إن وُجد، ثم اكتمال البيانات إن أبلغته الشاشة.

abstract final class ScreenOpenIds {
  static const pendingMessages = 'pending_messages';
  static const failedMessages = 'failed_messages';
  static const rejectedMessages = 'rejected_messages';
  static const customerDetail = 'customer_detail';
  static const transactionsLog = 'transactions_log';
  static const wallets = 'wallets';
  static const pos = 'pos';
  static const salesPeriodReport = 'sales_period_report';
  static const posReport = 'pos_report';
  static const posAccountsLedger = 'pos_accounts_ledger';
  static const systemCheck = 'system_check';
  static const cardStockSheet = 'sheet_card_stock';
  static const soldCardsSheet = 'sheet_sold_cards';
  static const broadcastSheet = 'sheet_broadcast';
  static const categoriesSheet = 'sheet_categories';
}

class ScreenOpenSample {
  ScreenOpenSample({
    required this.screenId,
    required this.kind,
    required this.openedAt,
    this.firstFrame,
    this.dataReady,
  });

  final String screenId;
  final String kind;
  final DateTime openedAt;
  Duration? firstFrame;
  Duration? dataReady;

  ScreenOpenSample copy() => ScreenOpenSample(
        screenId: screenId,
        kind: kind,
        openedAt: openedAt,
        firstFrame: firstFrame,
        dataReady: dataReady,
      );
}

class ScreenOpenHandle {
  ScreenOpenHandle(this._trace, this.sample);

  final ScreenOpenTrace _trace;
  final ScreenOpenSample sample;
  bool _frameMarked = false;
  bool _dataMarked = false;

  void markFirstFrame([DateTime? at]) {
    if (_frameMarked) return;
    _frameMarked = true;
    final now = at ?? DateTime.now();
    sample.firstFrame = now.difference(sample.openedAt);
    _trace._touch(sample);
  }

  void markDataReady([DateTime? at]) {
    if (_dataMarked) return;
    _dataMarked = true;
    final now = at ?? DateTime.now();
    sample.dataReady = now.difference(sample.openedAt);
    _trace._touch(sample);
  }
}

class ScreenOpenTrace {
  ScreenOpenTrace({this.maxSamples = 40, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  static final ScreenOpenTrace instance = ScreenOpenTrace();

  final int maxSamples;
  final DateTime Function() _clock;
  final List<ScreenOpenSample> _samples = [];
  final Map<String, ScreenOpenHandle> _open = {};

  List<ScreenOpenSample> get samples =>
      List<ScreenOpenSample>.unmodifiable(_samples.map((s) => s.copy()));

  ScreenOpenHandle start(String screenId, {String kind = 'route'}) {
    final sample = ScreenOpenSample(
      screenId: screenId,
      kind: kind,
      openedAt: _clock(),
    );
    _samples.add(sample);
    if (_samples.length > maxSamples) {
      _samples.removeAt(0);
    }
    final handle = ScreenOpenHandle(this, sample);
    _open[screenId] = handle;
    return handle;
  }

  /// أول إطار لآخر فتح لنفس المعرّف. يُكتب مرة واحدة.
  void markLatestFirstFrame(String screenId, [DateTime? at]) {
    final handle = _open[screenId];
    handle?.markFirstFrame(at);
  }

  /// تكملة بيانات آخر فتح لنفس الشاشة ما زال بلا `dataReady`.
  void markLatestDataReady(String screenId, [DateTime? at]) {
    final handle = _open[screenId];
    handle?.markDataReady(at);
  }

  /// يبدأ عينة ورقة. أول إطار واكتمال البيانات يُعلَّمان من الورقة نفسها.
  ScreenOpenHandle beginSheet(String screenId) => start(screenId, kind: 'sheet');

  void _touch(ScreenOpenSample _) {}

  void clear() {
    _samples.clear();
    _open.clear();
  }
}
