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
  static const categoryCommissionBps = 'category_commission_bps';
  static const posSettlementSuccessTemplate = 'pos_settlement_template_success';
  static const posSettlementFailedTemplate = 'pos_settlement_template_failed';
  static const posSettlementUnknownTemplate = 'pos_settlement_template_unknown';
  static const broadcastMaxAttempts = 'broadcast_max_attempts';
  static const broadcastRateDelayMs = 'broadcast_rate_delay_ms';
  static const deviceVerificationGates = 'device_verification_gates';
  static const lowStockThreshold = 'low_stock_threshold';
  static const pendingAttentionAlertEnabled = 'pending_attention_alert_enabled';
  static const promotionsCatalog = 'promotions_catalog';
  static const promotionRewardSmsTemplate = 'promotion_reward_sms_template';

  static const voucherDeliverySmsTemplate = 'voucher_delivery_sms_template';
  static const customerDebtPaymentTemplate = 'customer_debt_payment_template';
  static const posBalanceResponseTemplate = 'pos_balance_response_template';
  static const posCreditLimitExceededTemplate = 'pos_credit_limit_exceeded_template';
  static const dailyPosSummaryTemplate = 'daily_pos_summary_template';
  static const posRequestRejectedTemplate = 'pos_request_rejected_template';
  static const posCustomerSmsTailTemplate = 'pos_customer_sms_tail_template';
  static const posInstantChargeConfirmTemplate =
      'pos_instant_charge_confirm_template';
  static const lowStockAlertTemplate = 'low_stock_alert_template';

  static const customOutboundTemplates = 'custom_outbound_templates';
  static const walletExtras = 'wallet_extras';
  static const defaultWalletsSeeded = 'default_wallets_seeded';
}
