abstract final class SettingKeys {
  static const defaultCurrency = 'default_currency';
  static const reservationMinutes = 'reservation_minutes';
  static const preferredSimSlot = 'preferred_sim_slot';
  static const preferredSendSimSlot = 'preferred_send_sim_slot';
  static const simAutoFailover = 'sim_auto_failover';
  static const smsListenEnabled = 'sms_listen_enabled';
  static const batteryOptimizationAcknowledged = 'battery_optimization_acknowledged';
  static const lastExportAt = 'last_export_at';
  static const networkName = 'network_name';
  static const smsAutoProcessingEnabled = 'sms_auto_processing_enabled';
  static const processCategoryAmountsOnly = 'process_category_amounts_only';
  static const processOldMessagesOnResume = 'process_old_messages_on_resume';
  static const posBalanceRequestsEnabled = 'pos_balance_requests_enabled';
  static const dailyOpsSummaryAutoSend = 'daily_ops_summary_auto_send';
  static const themeMode = 'theme_mode';
  static const lastRejectedMessagesViewedAt = 'last_rejected_messages_viewed_at';
  static const notificationSources = 'notification_sources';
  static const autoRetryFailedMessages = 'auto_retry_failed_messages';
  static const retryMaxAttempts = 'retry_max_attempts';
  static const retryBaseDelaySeconds = 'retry_base_delay_seconds';
  static const salafniEnabled = 'salafni_enabled';
  static const salafniAcceptedTemplate = 'salafni_template_accepted';
  static const salafniRejectedTemplate = 'salafni_template_rejected';
  static const salafniSettledTemplate = 'salafni_template_settled';
  static const autoPosSettlementEnabled = 'auto_pos_settlement_enabled';
  static const posAccounts = 'pos_accounts';
  static const posSettlementSuccessTemplate = 'pos_settlement_template_success';
  static const posSettlementFailedTemplate = 'pos_settlement_template_failed';
  static const posSettlementUnknownTemplate = 'pos_settlement_template_unknown';
  static const broadcastMaxAttempts = 'broadcast_max_attempts';
  static const broadcastRateDelayMs = 'broadcast_rate_delay_ms';
  static const deviceVerificationGates = 'device_verification_gates';
  static const lowStockThreshold = 'low_stock_threshold';
  static const pendingAttentionAlertEnabled = 'pending_attention_alert_enabled';
  /// JSON array of [Promotion] objects.
  static const promotionsCatalog = 'promotions_catalog';
  static const promotionRewardSmsTemplate = 'promotion_reward_sms_template';

  // Outbound message templates (customers / offers / system / POS) — product video catalog.
  static const voucherDeliverySmsTemplate = 'voucher_delivery_sms_template';
  static const customerDebtPaymentTemplate = 'customer_debt_payment_template';
  static const posBalanceResponseTemplate = 'pos_balance_response_template';
  static const posCreditLimitExceededTemplate = 'pos_credit_limit_exceeded_template';
  static const dailyPosSummaryTemplate = 'daily_pos_summary_template';
  static const posRequestRejectedTemplate = 'pos_request_rejected_template';
  static const posCustomerSmsTailTemplate = 'pos_customer_sms_tail_template';
  static const lowStockAlertTemplate = 'low_stock_alert_template';

  /// JSON map: walletId → {senderId, sourceMode, packageName}.
  static const walletExtras = 'wallet_extras';

  /// Flag once default Yemen wallets (JAIB/JAWALI/ONE CASH/FLOOSAK) are seeded.
  static const defaultWalletsSeeded = 'default_wallets_seeded';
}

abstract final class SettingDefaults {
  static const networkName = 'NET';
  static const smsAutoProcessingEnabled = true;
  static const processCategoryAmountsOnly = true;
  static const processOldMessagesOnResume = true;
  static const posBalanceRequestsEnabled = true;
  static const dailyOpsSummaryAutoSend = true;
  static const themeMode = 'system';
  static const autoRetryFailedMessages = true;
  static const retryMaxAttempts = 5;
  static const retryBaseDelaySeconds = 30;
  static const salafniEnabled = false;
  static const autoPosSettlementEnabled = true;
  static const broadcastMaxAttempts = 3;
  static const broadcastRateDelayMs = 800;
  static const lowStockThreshold = 10;
  static const pendingAttentionAlertEnabled = true;
  static const promotionRewardSmsTemplate =
      'مكافأة عرض {title}\nالرقم: {serial}\nالرمز: {secret}';
  static const voucherDeliverySmsTemplate =
      'رقم الكرت: {serial}\nالرمز: {code}';
  static const customerDebtPaymentTemplate =
      'تم تأكيد سداد مبلغ {amount} ر.ي. رصيدك الحالي: {balance} ر.ي';
  static const posBalanceResponseTemplate =
      'رصيد نقطة البيع {pos}: {balance} ر.ي\nالدين: {debt} ر.ي';
  static const posCreditLimitExceededTemplate =
      'تعذر تنفيذ الطلب: تجاوزت نقطة البيع {pos} سقف الدين المسموح ({limit} ر.ي)';
  static const dailyPosSummaryTemplate =
      'ملخص يومي لنقطة البيع {pos}\nالمبيعات: {sales}\nالتحويلات: {transfers}\nالرصيد: {balance} ر.ي';
  static const posSettlementSuccessTemplate =
      'تم تأكيد تسوية نقطة البيع {pos} بمبلغ {amount} ر.ي';
  static const posSettlementFailedTemplate =
      'فشلت تسوية نقطة البيع {pos}: {reason}';
  static const posSettlementUnknownTemplate =
      'تعذر التحقق من تسوية نقطة البيع {pos}. راجع السجل يدوياً';
  static const posRequestRejectedTemplate =
      'تم رفض طلب نقطة البيع {pos}: {reason}';
  static const posCustomerSmsTailTemplate = '\n— {pos}';
  static const lowStockAlertTemplate =
      'تنبيه مخزون منخفض: الفئة {category} متبقي {count} كرت فقط';
  static const preferredSimSlot = '0';
  static const preferredSendSimSlot = '0';
  static const simAutoFailover = true;
}

final class AppSetting {
  const AppSetting({required this.key, required this.value, required this.updatedAt});
  final String key;
  final String value;
  final DateTime updatedAt;
}

abstract final class SettingBool {
  static bool read(String? raw, {required bool defaultValue}) {
    if (raw == null) return defaultValue;
    final v = raw.trim().toLowerCase();
    if (v == 'true' || v == '1') return true;
    if (v == 'false' || v == '0') return false;
    return defaultValue;
  }
}

abstract final class SettingInt {
  static int read(String? raw, {required int defaultValue}) {
    if (raw == null) return defaultValue;
    return int.tryParse(raw.trim()) ?? defaultValue;
  }
}
