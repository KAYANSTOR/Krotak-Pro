import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/setting.dart';
import '../../app_scope.dart';
import '../../theme/kayan_colors.dart';

/// Bottom sheet — PD-07 Q6 / PD-02.
class NetworkNameEditSheet extends StatefulWidget {
  const NetworkNameEditSheet({super.key, required this.initialName});

  final String initialName;

  /// Returns the saved name on success, null on cancel.
  static Future<String?> show(BuildContext context, {required String initialName}) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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
    final bottom = MediaQuery.paddingOf(context).bottom;
    final inset = MediaQuery.viewInsetsOf(context).bottom;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.fromLTRB(24, 8, 24, 16 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 48,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(50),
                  ),
                ),
              ),
              const Text(
                'تعديل اسم الشبكة',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: KayanColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'سيتم استخدام هذا الاسم في نهاية رسائل SMS المرسلة للعملاء.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  fontSize: 13,
                  color: KayanColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                enabled: !_saving,
                maxLength: 48,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                style: const TextStyle(fontFamily: 'Tajawal', fontSize: 15),
                decoration: InputDecoration(
                  labelText: 'اسم الشبكة',
                  labelStyle: const TextStyle(fontFamily: 'Tajawal'),
                  hintText: SettingDefaults.networkName,
                  counterText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: KayanColors.primary),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(
                    fontFamily: 'Tajawal',
                    fontSize: 13,
                    color: KayanColors.error,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: const Text(
                        'إلغاء',
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 15,
                          color: KayanColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 48,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: KayanColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _saving ? null : _save,
                        child: Text(
                          _saving ? 'جاري الحفظ…' : 'حفظ',
                          style: const TextStyle(
                            fontFamily: 'Tajawal',
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
