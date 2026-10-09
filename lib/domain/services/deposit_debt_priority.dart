/// قرار مسار الإيداع بعد سداد سلفني.
///
/// القاعدة المعتمدة في خطة 2026-10-09 (البند B): إذا استُخدم أي جزء من الإيداع
/// لسداد دين، لا يُحجز كرت ولا يُباع ولا يُرسل من نفس الإيداع.
/// الباقي — إن وُجد — لا يشتري كرتًا قبل قرار المالك؛ يُحفظ رصيدًا.
enum DepositAfterDebt {
  /// لا دين مُسدَّد من هذا الإيداع: مسار الكرت الحالي يبقى.
  deliverCard,

  /// الإيداع استُهلك كاملًا في السداد: لا كرت.
  settlementOnly,

  /// جزء سُدد وباقي: لا كرت، والباقي رصيد عميل إلى حين قرار المالك.
  creditSurplusNoCard,
}

abstract final class DepositDebtPriority {
  static DepositAfterDebt decide({
    required int appliedMinorUnits,
    required int remainingMinorUnits,
  }) {
    if (appliedMinorUnits <= 0) return DepositAfterDebt.deliverCard;
    if (remainingMinorUnits <= 0) return DepositAfterDebt.settlementOnly;
    return DepositAfterDebt.creditSurplusNoCard;
  }
}
