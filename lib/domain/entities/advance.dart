import 'card.dart';
import 'money.dart';

/// A Salafni (emergency-credit) obligation projected from the existing ledger
/// and sale records. No second financial ledger is introduced.
enum AdvanceStatus { open, settled }

final class Advance {
  const Advance({
    required this.id,
    required this.customerId,
    required this.cardId,
    required this.amount,
    required this.outstanding,
    required this.reference,
    required this.createdAt,
    required this.status,
    this.settledAt,
  });

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
  const AdvancePaymentResult({required this.applied, required this.remaining});

  final Money applied;
  final Money remaining;
}
