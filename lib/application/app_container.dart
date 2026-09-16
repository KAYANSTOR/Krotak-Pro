import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/clock.dart';
import '../core/id_generator.dart';
import '../core/result.dart';
import '../data/database/database_provider.dart';
import '../data/database/drift_unit_of_work.dart';
import '../data/repositories/local_repositories.dart';
import '../domain/entities/message.dart';
import '../domain/entities/setting.dart';
import '../domain/services/local_account_merge_service.dart';
import '../domain/services/local_advance_service.dart';
import '../domain/services/local_backup_service.dart';
import '../domain/services/local_broadcast_service.dart';
import '../domain/services/local_card_inventory_service.dart';
import '../domain/services/local_catalog_services.dart';
import '../domain/services/local_customer_balance_service.dart';
import '../domain/services/local_customer_service.dart';
import '../domain/services/local_device_verification_service.dart';
import '../domain/services/local_license_service.dart';
import '../domain/services/local_message_parser.dart';
import '../domain/services/local_message_recovery_service.dart';
import '../domain/services/local_message_retry_service.dart';
import '../domain/services/local_payment_source_registry.dart';
import '../domain/services/local_pos_account_registry.dart';
import '../domain/services/local_promotion_catalog.dart';
import '../domain/services/local_promotion_fulfillment_service.dart';
import '../domain/services/local_promotion_progress_service.dart';
import '../domain/services/local_sale_service.dart';
import '../domain/services/local_settlement_service.dart';
import '../domain/services/local_system_health_service.dart';
import '../domain/services/local_transfer_processor.dart';
import '../domain/services/local_voucher_ops_service.dart';
import '../domain/services/pending_attention_alarm_service.dart';
import '../domain/services/services.dart';
import '../domain/services/unified_payment_event_engine.dart';
import '../platform/sms_bridge.dart';
import '../platform/system_diagnostics_bridge.dart';
import 'incoming_notification_handler.dart';
import 'incoming_sms_handler.dart';

// TEMP STUB - will be fully restored
class AppContainer {
  AppContainer._();
  static Future<AppContainer> bootstrap({required List<TransferTemplate> templates}) async {
    throw UnimplementedError('app_container being restored');
  }
  void dispose() {}
  Future<void> startBackgroundHandlers() async {}
  final themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);
}
