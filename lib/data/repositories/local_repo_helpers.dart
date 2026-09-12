part of local_repositories;

AppFailure _failure(String code, Object error) {
  final text = error.toString();
  final lower = text.toLowerCase();
  if (lower.contains('unique constraint failed')) {
    if (lower.contains('customer_identifiers')) {
      return const AppFailure(
        code: 'duplicate_identifier',
        message: 'Identifier already exists',
      );
    }
    if (lower.contains('serial')) {
      return const AppFailure(
        code: 'duplicate_serial',
        message: 'Card serial already exists',
      );
    }
    if (lower.contains('secret')) {
      return const AppFailure(
        code: 'duplicate_secret',
        message: 'Card secret already exists',
      );
    }
    if (lower.contains('external_reference') || lower.contains('incoming_messages')) {
      return const AppFailure(
        code: 'duplicate_message_reference',
        message: 'Message reference already exists',
      );
    }
    if (lower.contains('reference')) {
      return const AppFailure(
        code: 'duplicate_reference',
        message: 'Reference already exists',
      );
    }
    return AppFailure(code: 'unique_constraint', message: text);
  }
  return AppFailure(code: code, message: text);
}
