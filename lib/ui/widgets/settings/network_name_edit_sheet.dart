import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/setting.dart';
import '../../app_scope.dart';
import '../../theme/kayan_palette.dart';
import '../../theme/net_tokens.dart';
import '../net/net_sheet.dart';

/// Bottom sheet — PD-07 Q6 / PD-02.
class NetworkNameEditSheet extends StatefulWidget {
  const NetworkNameEditSheet({super.key, required this.initialName});

  final String initialName;

  /// Returns the saved name on success, null on cancel.
  static Future<String?> show(BuildContext context, {required String initialName}) {
    return NetSheet.show<String>(
      context,
      builder: (ctx) => NetworkNameEditSheet(initialName: initialName),
    );
  }

  @override
  State<NetworkNameEditSheet> createState() => _NetworkNameEditSheetState();
}

class _NetworkNameEditSheetState extends State<NetworkNameEditSheet> {
  late final TextEditingController _controller;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'اسم الشبكة مطلوب');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final c = AppScope.of(context);
    final result = await c.settings.save(
      AppSetting(
        key: SettingKeys.networkName,
        value: name,
        updatedAt: c.clock.now(),
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (result is Failure) {
      setState(() => _error = 'تعذر حفظ اسم الشبكة');
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);

    return NetSheet(
      title: 'تعديل اسم الشبكة',
      subtitle: 'سيتم استخدام هذا الاسم في نهاية رسائل SMS المرسلة للعملاء.',
      icon: Icons.edit_rounded,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          NetSpacing.xl,
          NetSpacing.lg,
          NetSpacing.xl,
          NetSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              enabled: !_saving,
              maxLength: 48,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontSize: 15,
                color: palette.textPrimary,
              ),
              decoration: InputDecoration(
                labelText: 'اسم الشبكة',
                labelStyle: const TextStyle(fontFamily: NetTypography.family),
                hintText: SettingDefaults.networkName,
                counterText: '',
                border: const OutlineInputBorder(),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: palette.primary, width: 1.4),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: NetSpacing.sm),
              Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: NetSizes.iconSm,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: NetSpacing.sm),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(
                        fontFamily: NetTypography.family,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      footer: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
          ),
          const SizedBox(width: NetSpacing.md),
          Expanded(
            flex: 2,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'جاري الحفظ…' : 'حفظ'),
            ),
          ),
        ],
      ),
    );
  }
}
