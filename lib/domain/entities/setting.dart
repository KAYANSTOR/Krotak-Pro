abstract final class SettingKeys {
  static const defaultCurrency = 'default_currency';
  static const reservationMinutes = 'reservation_minutes';
  static const preferredSimSlot = 'preferred_sim_slot';
  static const preferredSendSimSlot = 'preferred_send_sim_slot';
  /// ISO-8601 of last successful recovery/delivery pass (settings honesty).
  static const lastRecoveryPassAt = 'last_recovery_pass_at';
  static const simAutoFailover = 'sim_auto_failover';
  static const smsListenEnabled = 'sms_listen_enabled';
  static const batteryOptimizationAcknowledged = 'battery_optimization_acknowledged';
  static const lastExportAt = 'last_export_at';
  static const networkName = 'network_name';
  static const smsAutoProcessingEnabled = 'sms_auto_processing_enabled';
  static const processCategoryAmountsOnly = 'process_category_amounts_only';
  static const processOldMessagesOnResume = 'process_old_messages_on_resume';
  static const posBalanceRequestsEnabled = 'pos_balance_requests_enabled';
  static const posBalanceRequestDailyLimit = 'pos_balance_request_daily_limit';
  static const dailyOpsSummaryAutoSend = 'daily_ops_summary_auto_send';
  static const themeMode = 'theme_mode';
  static const lastRejectedMessagesViewedAt = 'last_rejected_messages_viewed_at';
  static const notificationSources = 'notification_sources';
  static const blockedPhones = 'blocked_phones';
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
  static const promotionRewardSmsTemplates = 'promotion_reward_sms_templates';
  static const promotionRewardCustomerSmsTemplates =
      'promotion_reward_customer_sms_templates';
  static const promotionRewardCustomerGlobalSmsTemplates =
      'promotion_reward_customer_global_sms_templates';
  static const promotionRewardProbeReceipts =
      'promotion_reward_probe_receipts';
  static const promotionRewardProbeHolds =
      'promotion_reward_probe_holds';

  static const voucherDeliverySmsTemplate = 'voucher_delivery_sms_template';
  static const posCustomerCardDeliveryTemplate = 'pos_customer_card_delivery_template';
  static const posOrderSuccessTemplate = 'pos_order_success_template';
  static const customerDebtPaymentTemplate = 'customer_debt_payment_template';
  static const posBalanceResponseTemplate = 'pos_balance_response_template';
  static const posCreditLimitExceededTemplate = 'pos_credit_limit_exceeded_template';
  static const dailyPosSummaryTemplate = 'daily_pos_summary_template';
  static const posRequestRejectedTemplate = 'pos_request_rejected_template';
  static const posCustomerSmsTailTemplate = 'pos_customer_sms_tail_template';
  static const posInstantChargeConfirmTemplate =
      'pos_instant_charge_confirm_template';
  static const lowStockAlertTemplate = 'low_stock_alert_template';
  static const lowStockActiveJson = 'low_stock_active_json';

  // ── قوالب إرسال الكروت حسب نوع العملية (تُزرع وتُعدّل من الإعدادات) ──
  static const cardDeliveryCashTemplate = 'card_delivery_cash_template';
  static const cardDeliveryCreditTemplate = 'card_delivery_credit_template';
  static const cardDeliveryGiftTemplate = 'card_delivery_gift_template';
  static const salafniCardDeliveryTemplate = 'salafni_card_delivery_template';
  static const depositNoStockTemplate = 'deposit_no_stock_template';

  /// سجل metadata القوالب المخصّصة (معرّف/اسم/تبويب/هدف).
  ///
  /// لا يُخزّن نص القالب هنا أبدًا — النص له مصدر واحد هو
  /// [customOutboundBody].
  static const customOutboundTemplates = 'custom_outbound_templates';

  /// خريطة JSON: مفتاح قالب النظام ← معرّف القالب المخصّص الفعّال بدلاً منه.
  /// هي المصدر الوحيد لقرار «أي قالب يُرسل».
  static const activeOutboundTemplates = 'active_outbound_templates';

  /// المصدر الوحيد لنص قالب مخصّص. قالب النظام لا يُكتب فوقه أبدًا، فالاستبدال
  /// قرار في [activeOutboundTemplates] والنص في هذا المفتاح — ولا ازدواجية.
  static String customOutboundBody(String customId) =>
      'custom_outbound_body:$customId';

  /// مفاتيح توافق لبيانات القوالب المحفوظة قبل توحيد المصدر في الإعدادات.
  static String legacyCustomOutboundBody(String customId) => 'custom:$customId';

  static String outboundSystemOriginal(String systemKey) =>
      'outbound_system_original:$systemKey';

  static const walletExtras = 'wallet_extras';
  static const defaultWalletsSeeded = 'default_wallets_seeded';

  // ── حساب الشبكة (Cloud account) ───────────────────────────────────────────────────────
  /// معرّف الحساب في Firebase (نفس المعرّف المستخدم في لوحة الإدارة).
  static const cloudAccountUid = 'cloud_account_uid';

  /// رمز تجديد جلسة Firebase — يُخزّن محلياً على الجهاز فقط.
  static const cloudRefreshToken = 'cloud_refresh_token';
  static const cloudPhone = 'cloud_phone';
  static const cloudNetworkName = 'cloud_network_name';
  static const cloudIsTrial = 'cloud_is_trial';
  static const cloudIsActive = 'cloud_is_active';
  static const cloudSubscriptionEnd = 'cloud_subscription_end';
  static const cloudTrialWarning = 'cloud_trial_warning';

  /// وقت آخر قراءة للإشعارات العامة (لتمييز غير المقروء).
  static const cloudGlobalSeenAt = 'cloud_global_seen_at';
}

abstract final class SettingDefaults {
  static const networkName = 'NET';
  static const smsAutoProcessingEnabled = true;
  static const processCategoryAmountsOnly = true;
  static const processOldMessagesOnResume = true;
  static const posBalanceRequestsEnabled = true;
  static const posBalanceRequestDailyLimit = 5;
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
      'نشكرك على استخدامك شبكة {NETWORK_NAME}.\nكود الكرت: {CARD_CODE}\nفئة: {CARD_VALUE} ر.ي\nالرمز: {code}';
  static const posCustomerCardDeliveryTemplate =
      'شبكة {NETWORK_NAME}\nالفئة: {category}\n{cards}';
  static const posOrderSuccessTemplate =
      'تم إرسال {QUANTITY_TEXT} بنجاح إلى {CUSTOMER_PHONE}\nالفئة: {CARD_VALUE} {CURRENCY}\nنقطة البيع: {POS_NAME}\nإجمالي الخصم من الحساب: {TOTAL} {CURRENCY}';
  static const customerDebtPaymentTemplate =
      'تم استلام إيداع بمبلغ {amount} {CURRENCY}\n'
      'تم خصم {paid} {CURRENCY} لسداد الدين\n'
      'تم إضافة {surplus} {CURRENCY} إلى رصيد حسابك\n'
      'رصيدك الحالي: {balance} {CURRENCY}';
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
  static const posInstantChargeConfirmTemplate =
      'تم إرسال كرت {amount} ر.ي إلى {phone}';
  /// تنبيه داخلي للمشغّل (إشعار الجهاز الحي) — ليس رسالة عميل.
  static const lowStockAlertTemplate =
      'تنبيه: كروت فئة {category} أوشكت على النفاد (المتبقي: {count}).';
  static const cardDeliveryCashTemplate =
      'كرتك من شبكة {اسم_المحفظة}\n{الفئة}\n{الرقم}\n{الرمز}';
  static const cardDeliveryCreditTemplate =
      'كرت آجل عليكم في حسابكم\nمن شبكة {اسم_المحفظة}\n{الفئة}\n{الرقم}\n{الرمز}';
  static const cardDeliveryGiftTemplate =
      'كرتك الهدية\nمن شبكة {اسم_المحفظة}\n{الفئة}\n{الرقم}\n{الرمز}';
  static const salafniCardDeliveryTemplate =
      'كرتك من خدمة سلفني\nشبكة {اسم_المحفظة}\n{الفئة}\n{الرقم}\n{الرمز}';
  static const depositNoStockTemplate =
      'عزيزي {اسم_الزبون_الاول}\nتم استلام {المبلغ}﷼\nسوف يتم مشاركة الكرت آلياً فور توفره';
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
