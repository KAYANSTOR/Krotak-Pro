import 'package:flutter/material.dart';

import '../activation_screen.dart';
import '../help_center_screen.dart';
import 'battery_settings_screen.dart';
import 'clean_logs_screen.dart';
import 'export_ledger_screen.dart';
import 'renew_subscription_screen.dart';
import 'sim_settings_screen.dart';
import 'templates_screen.dart';

class SettingsHubScreen extends StatelessWidget {
  const SettingsHubScreen({super.key});

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        _tile(context, Icons.sim_card_outlined, 'إعدادات الشريحة', const SimSettingsScreen()),
        _tile(context, Icons.battery_saver_outlined, 'البطارية', const BatterySettingsScreen()),
        _tile(context, Icons.pattern, 'قوالب التحويل', const TemplatesScreen()),
        _tile(context, Icons.file_upload_outlined, 'تصدير السجل', const ExportLedgerScreen()),
        _tile(context, Icons.cleaning_services_outlined, 'تنظيف السجلات', const CleanLogsScreen()),
        _tile(context, Icons.workspace_premium_outlined, 'تجديد الاشتراك', const RenewSubscriptionScreen()),
        _tile(context, Icons.verified_user_outlined, 'تفعيل الترخيص', const ActivationScreen()),
        _tile(context, Icons.help_outline, 'مركز المساعدة', const HelpCenterScreen()),
      ],
    );
  }

  Widget _tile(BuildContext context, IconData icon, String title, Widget page) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title, style: const TextStyle(fontFamily: 'Tajawal')),
      trailing: const Icon(Icons.chevron_left),
      onTap: () => _open(context, page),
    );
  }
}
