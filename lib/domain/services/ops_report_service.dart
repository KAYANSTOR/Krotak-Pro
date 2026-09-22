import '../../core/clock.dart';
import '../../core/result.dart';
import '../entities/card.dart';
import '../entities/message.dart';
import '../entities/transaction.dart';
import '../repositories/repositories.dart';
import 'messages_source_of_truth.dart';

/// Phase 7 — single read-model for dashboard + reports hub.
///
/// All numbers come from repository contracts (no UI mocks).
final class OpsReportService {
  const OpsReportService({
    required this.messages,
    required this.sales,
    required this.transactions,
    required this.cards,
    required this.clock,
  });

  final MessageRepository messages;
  final SaleRepository sales;
  final TransactionRepository transactions;
  final CardRepository cards;
  final Clock clock;

  Future<Result<OpsSnapshot>> snapshot({int recentTxLimit = 200}) async {
    final now = clock.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final monthStart = DateTime(now.year, now.month, 1);

    final daily = await sales.listCompletedBetween(dayStart, now);
    if (daily is Failure<List<Sale>>) return Failure(daily.error);
    final monthly = await sales.listCompletedBetween(monthStart, now);
    if (monthly is Failure<List<Sale>>) return Failure(monthly.error);

    final source = MessagesFacade(RepositoryMessagesSource(messages));
    final rejected = await source.list(MessageListCategory.rejected);
    if (rejected is Failure<List<IncomingMessage>>) return Failure(rejected.error);
    final received = await messages.listByStatus(MessageProcessingStatus.received);
    if (received is Failure<List<IncomingMessage>>) return Failure(received.error);
    final parsed = await messages.listByStatus(MessageProcessingStatus.parsed);
    if (parsed is Failure<List<IncomingMessage>>) return Failure(parsed.error);
    final pending = await messages.listByStatus(MessageProcessingStatus.pending);
    if (pending is Failure<List<IncomingMessage>>) return Failure(pending.error);
    final sending = await messages.listByStatus(MessageProcessingStatus.sending);
    if (sending is Failure<List<IncomingMessage>>) return Failure(sending.error);
    final failedAll = await source.list(MessageListCategory.failed);
    if (failedAll is Failure<List<IncomingMessage>>) return Failure(failedAll.error);

    final recent = await transactions.listRecent(limit: recentTxLimit);
    if (recent is Failure<List<Transaction>>) return Failure(recent.error);

    final available = await cards.listByStatus(CardStatus.available);
    if (available is Failure<List<Card>>) return Failure(available.error);

    final d = (daily as Success<List<Sale>>).value;
    final m = (monthly as Success<List<Sale>>).value;
    final rej = (rejected as Success<List<IncomingMessage>>).value;
    final rcv = (received as Success<List<IncomingMessage>>).value;
    final prs = (parsed as Success<List<IncomingMessage>>).value;
    final pnd = (pending as Success<List<IncomingMessage>>).value;
    final snd = (sending as Success<List<IncomingMessage>>).value;
    final failedRows = (failedAll as Success<List<IncomingMessage>>).value;
    final fld = failedRows
        .where((message) => message.status == MessageProcessingStatus.failed)
        .toList(growable: false);
    final fmx = failedRows
        .where((message) => message.status == MessageProcessingStatus.failedMaxAttempts)
        .toList(growable: false);
    final tx = (recent as Success<List<Transaction>>).value;
    final avail = (available as Success<List<Card>>).value;

    final pipelineOpen = rcv.length + prs.length + pnd.length + snd.length + fld.length;

    return Success(
      OpsSnapshot(
        dailySalesCount: d.length,
        dailySalesMinor: d.fold(0, (a, s) => a + s.amount.minorUnits),
        monthlySalesCount: m.length,
        monthlySalesMinor: m.fold(0, (a, s) => a + s.amount.minorUnits),
        rejectedCount: rej.length,
        pipelineOpenCount: pipelineOpen,
        sendingCount: snd.length,
        failedRetryCount: fld.length,
        failedMaxCount: fmx.length,
        availableCards: avail.length,
        completedTxRecent: tx.where((t) => t.status == TransactionStatus.completed).length,
        asOf: now,
      ),
    );
  }
}

final class OpsSnapshot {
  const OpsSnapshot({
    required this.dailySalesCount,
    required this.dailySalesMinor,
    required this.monthlySalesCount,
    required this.monthlySalesMinor,
    required this.rejectedCount,
    required this.pipelineOpenCount,
    required this.sendingCount,
    required this.failedRetryCount,
    required this.failedMaxCount,
    required this.availableCards,
    required this.completedTxRecent,
    required this.asOf,
  });

  final int dailySalesCount;
  final int dailySalesMinor;
  final int monthlySalesCount;
  final int monthlySalesMinor;
  final int rejectedCount;
  final int pipelineOpenCount;
  final int sendingCount;
  final int failedRetryCount;
  final int failedMaxCount;
  final int availableCards;
  final int completedTxRecent;
  final DateTime asOf;

  /// Messages needing operator attention (open pipeline + rejected + exhausted).
  int get attentionCount =>
      pipelineOpenCount + rejectedCount + failedMaxCount;
}
