import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/setting.dart';
import '../../app_scope.dart';
import '../../routing/app_routes.dart';
import '../../theme/kayan_colors.dart';
import '../../theme/kayan_palette.dart';
import '../../widgets/settings/settings_cards.dart';
import '../../widgets/settings/settings_section_header.dart';
import '../system_check_screen.dart';
import '../wallets_pos_screen.dart';
import 'clean_logs_screen.dart';
import 'export_ledger_screen.dart';
import 'low_stock_settings_screen.dart';
import 'network_name_settings_screen.dart';
import 'renew_subscription_screen.dart';
import 'salafni_templates_screen.dart';
import 'outbound_message_templates_screen.dart';
import 'sim_settings_screen.dart';
import 'template_simulation_screen.dart';
import 'templates_screen.dart';
import 'wallet_notification_settings_screen.dart';

/// مركز الإعدادات — مطابق حرفياً لإطارات فيديو Z Net
class SettingsHubScreen extends StatefulWidget {
  const SettingsHubScreen({super.key});

  @override
  State<SettingsHubScreen> createState() => _SettingsHubScreenState();
}
