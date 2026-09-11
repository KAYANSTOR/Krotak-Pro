import 'money.dart';

enum TransactionType {
  deposit,
  withdrawal,
  sale,
  settlement,
  reversal,
  advance,
  reward,
}

enum TransactionStatus { pending, completed, reversed, rejected }

final class Transaction {
  const Transaction({
    required this.id,
    required this.type,
    required this.status,
    required this.amount,
    required this.createdAt,
    this.customerId,
    this.reference,
    this.relatedTransactionId,
  });

  final String id;
  final TransactionType type;
  final TransactionStatus status;
  final Money amount;
  final DateTime createdAt;
  final String? customerId;
  final String? reference;
  final String? relatedTransactionId;
}

final class Sale {
  const Sale({
    required this.id,
    required this.customerId,
    required this.cardId,
    required this.amount,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String customerId;
  final String cardId;
  final Money amount;
  final TransactionStatus status;
  final DateTime createdAt;
}
