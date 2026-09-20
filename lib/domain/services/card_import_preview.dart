import 'services.dart';

/// Result of validating a parsed batch against current inventory.
final class CardImportPreview {
  const CardImportPreview({
    required this.drafts,
    required this.parseErrors,
    required this.stockDuplicateSerials,
    this.fileName,
  });

  final List<CardImportDraft> drafts;
  final List<String> parseErrors;
  final Set<String> stockDuplicateSerials;
  final String? fileName;

  List<CardImportDraft> get acceptedDrafts => drafts
      .where((d) => !stockDuplicateSerials.contains(d.serialNumber))
      .toList(growable: false);

  int get acceptedCount => acceptedDrafts.length;
  int get stockDuplicateCount => stockDuplicateSerials.length;
  bool get canImport => acceptedDrafts.isNotEmpty;
}
