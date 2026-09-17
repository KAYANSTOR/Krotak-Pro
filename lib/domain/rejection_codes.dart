/// Canonical rejection codes from the help-center screenshots (13 codes).
///
/// Use these string values in audit payloads, rejected-message filters, and
/// recovery action routing so UI and services share one vocabulary.
abstract final class RejectionCodes {
  static const voucherSendFailed = 'voucherSendFailed';
  static const voucherUnavailable = 'voucherUnavailable';
  static const missingFields = 'missingFields';
  static const categoryMismatch = 'categoryMismatch';
  static const blacklisted = 'blacklisted';
  static const parseFailure = 'parseFailure';
  static const noActiveTemplate = 'noActiveTemplate';
  static const unknownSender = 'unknownSender';
  static const duplicateTransaction = 'duplicateTransaction';
  static const invalidFormat = 'invalidFormat';
  static const licenseBlocked = 'licenseBlocked';
  static const creditLimitExceeded = 'creditLimitExceeded';
  static const other = 'other';

  static const all = <String>[
    voucherSendFailed,
    voucherUnavailable,
    missingFields,
    categoryMismatch,
    blacklisted,
    parseFailure,
    noActiveTemplate,
    unknownSender,
    duplicateTransaction,
    invalidFormat,
    licenseBlocked,
    creditLimitExceeded,
    other,
  ];

  /// True when [code] is one of the 13 documented codes.
  static bool isKnown(String? code) =>
      code != null && all.contains(code);
}
