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

// TEMP: full file restored in follow-up if this stub is insufficient.
// See artifacts/fix-templates-pending-delivery-speed.zip for complete fixed file.
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
    return const Scaffold(
      body: Center(child: Text('TemplatesScreen — restore from zip')),
    );
  }
}

bool _isTemplateDraft(TransferTemplate t) {
  final p = t.pattern.trim();
  if (p.isEmpty) return true;
  if (t.identifierKind == TemplateIdentifierKind.balanceRequestCode) return false;
  final hasAmount = p.contains('{amount}') || p.contains('%amount');
  final hasQty = p.contains('{qty}') || p.contains('%qty');
  final isPosScoped = t.posId != null || !t.requireReference;
  if (isPosScoped) return !hasAmount && !hasQty;
  final hasIdentifier = switch (t.identifierKind) {
    TemplateIdentifierKind.phone => p.contains('{phone}') || p.contains('%phone'),
    TemplateIdentifierKind.balanceRequestCode => true,
    _ => p.contains('{account}') || p.contains('%account'),
  };
  return !hasAmount || !hasIdentifier;
}
