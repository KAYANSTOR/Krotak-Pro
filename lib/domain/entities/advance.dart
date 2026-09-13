import 'card.dart';
import 'money.dart';
import 'transaction.dart';

/// A Salafni obligation projected from the existing ledger and sale records.
enum AdvanceStatus { open, settled }

final class Advance {
  const Advance({required this.id, required this.customerId, required this.cardId, required this.amount, required this.outstanding, required this.reference, required this.createdAt, required this.status, this.settledAt});
  final String id;
  final String customerId;
  final String cardId;
  final Money amount;
  final Money outstanding;
  final String reference;
  final DateTime createdAt;
  final AdvanceStatus status;
  final DateTime? settledAt;
}

final class AdvanceIssue {
  const AdvanceIssue({required this.advance, required this.card});
  final Advance advance;
  final Card card;
}

final class AdvancePaymentResult {
  const AdvancePaymentResult({required this.applied, required this.remaining, this.settlementTransaction});
  final Money applied;
  final Money remaining;
  final Transaction? settlementTransaction;
}
