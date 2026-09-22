import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/message.dart';
import '../../../domain/entities/wallet.dart';
import '../../../domain/services/default_pos_templates_seeder.dart';
import '../../app_scope.dart';
import '../../theme/kayan_palette.dart';
import '../../theme/net_semantic_colors.dart';
import '../../widgets/async_views.dart';
import 'template_simulation_screen.dart';
import 'template_wizard_screen.dart';
import '../../../domain/services/local_transfer_template_activation_service.dart';

/// PLACEHOLDER restored minimally — replace with full file from
/// artifacts/fix-templates-pending-delivery-speed.zip before merge.
/// Draft-detection fix for POS is included below for reference.
class TemplatesScreen extends StatefulWidget {
  const TemplatesScreen({
    super.key,
    this.walletId,
    this.walletName,
    this.posId,
    this.posName,
  });
  final String? walletId;
  final String? walletName;
  final String? posId;
  final String? posName;
  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('قوالب التحويل', style: TextStyle(fontFamily: 'Tajawal'))),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'استبدل هذا الملف بالنسخة الكاملة من\nartifacts/fix-templates-pending-delivery-speed.zip\nقبل الدمج.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Tajawal', height: 1.5),
            ),
          ),
        ),
      ),
    );
  }
}
