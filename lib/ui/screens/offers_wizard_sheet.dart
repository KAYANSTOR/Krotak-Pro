import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/card.dart';
import '../../domain/entities/promotion.dart';
import '../app_scope.dart';
import '../theme/kayan_palette.dart';
import '../theme/net_tokens.dart';
import '../widgets/async_views.dart';

/// معالج إنشاء/تعديل عرض ترويجي — 4 خطوات مطابقة الفيديو.
Future<bool?> showOffersWizardSheet({
  required BuildContext context,
  required List<CardCategory> categories,
  Promotion? existing,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _OffersWizardSheet(
      categories: categories,
      existing: existing,
    ),
  );
}

class _OffersWizardSheet extends StatefulWidget {
  const _OffersWizardSheet({required this.categories, this.existing});
  final List<CardCategory> categories;
  final Promotion? existing;

  @override
  State<_OffersWizardSheet> createState() => _OffersWizardSheetState();
}

class _OffersWizardSheetState extends State<_OffersWizardSheet> {
  late final PageController _pageCtrl;
  late final TextEditingController _titleCtrl;
  late final TextEditingController _thresholdCtrl;
  late final TextEditingController _notesCtrl;
  late String _rewardId;
  int _step = 0;
  bool _busy = false;
  String? _status;

  static const _stepTitles = <String>[
    'عنوان الحملة',
    'عتبة التراكم',
    'فئة المكافأة',
    'مراجعة وحفظ',
  ];

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _pageCtrl = PageController();
    _titleCtrl = TextEditingController(text: existing?.title ?? '');
    _thresholdCtrl = TextEditingController(
      text: existing == null
          ? ''
          : (existing.thresholdMinorUnits / 100).toStringAsFixed(
              existing.thresholdMinorUnits % 100 == 0 ? 0 : 2,
            ),
    );
    _notesCtrl = TextEditingController(text: existing?.notes ?? '');
    _rewardId = widget.categories.any((e) => e.id == existing?.rewardCategoryId)
        ? existing!.rewardCategoryId
        : widget.categories.first.id;
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _titleCtrl.dispose();
    _thresholdCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _goTo(int s) {
    setState(() => _step = s);
    _pageCtrl.animateToPage(
      s,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  bool _validateStep(int s) {
    if (s == 0 && _titleCtrl.text.trim().isEmpty) {
      setState(() => _status = 'أدخل عنوان الحملة');
      return false;
    }
    if (s == 1) {
      final major = double.tryParse(
        _thresholdCtrl.text.trim().replaceAll(',', '.'),
      );
      if (major == null || major <= 0) {
        setState(() => _status = 'أدخل عتبة تراكم صحيحة أكبر من صفر');
        return false;
      }
    }
    if (s == 2 && _rewardId.isEmpty) {
      setState(() => _status = 'اختر فئة المكافأة');
      return false;
    }
    setState(() => _status = null);
    return true;
  }

  Future<void> _submit() async {
    if (!_validateStep(0) || !_validateStep(1) || !_validateStep(2)) return;
    final major = double.parse(
      _thresholdCtrl.text.trim().replaceAll(',', '.'),
    );
    setState(() {
      _busy = true;
      _status = null;
    });
    final c = AppScope.of(context);
    final existing = widget.existing;
    final r = existing == null
        ? await c.promotions.create(
            title: _titleCtrl.text,
            thresholdMinorUnits: (major * 100).round(),
            rewardCategoryId: _rewardId,
            notes: _notesCtrl.text,
          )
        : await c.promotions.update(
            id: existing.id,
            title: _titleCtrl.text,
            thresholdMinorUnits: (major * 100).round(),
            rewardCategoryId: _rewardId,
            notes: _notesCtrl.text,
          );
    if (!mounted) return;
    if (r is Success) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _busy = false;
        _status = (r as Failure).error.message;
      });
    }
  }

  String? get _rewardName {
    for (final cat in widget.categories) {
      if (cat.id == _rewardId) return cat.name;
    }
    return null;
  }

  Widget _stepBody(int index, KayanPalette palette) {
    switch (index) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('ما اسم العرض الترويجي؟', style: TextStyle(fontFamily: NetTypography.family, fontWeight: FontWeight.w800, fontSize: 16, color: palette.textPrimary)),
            const SizedBox(height: 8),
            Text('سيظهر العنوان للعميل عند صرف المكافأة وفي التقارير.', style: TextStyle(fontFamily: NetTypography.family, fontSize: 13, color: palette.textSecondary)),
            const SizedBox(height: 16),
            TextField(
              controller: _titleCtrl,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) { if (_validateStep(0)) _goTo(1); },
              decoration: const InputDecoration(labelText: 'عنوان الحملة', hintText: 'مثال: عرض 1000 → كرت 100', border: OutlineInputBorder()),
              style: const TextStyle(fontFamily: NetTypography.family),
            ),
          ],
        );
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('ما عتبة التراكم؟', style: TextStyle(fontFamily: NetTypography.family, fontWeight: FontWeight.w800, fontSize: 16, color: palette.textPrimary)),
            const SizedBox(height: 8),
            Text('عند بلوغ مجموع مشتريات العميل هذه العتبة يُصرف كرت المكافأة تلقائياً.', style: TextStyle(fontFamily: NetTypography.family, fontSize: 13, color: palette.textSecondary)),
            const SizedBox(height: 16),
            TextField(
              controller: _thresholdCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'عتبة التراكم (ر.ي)', hintText: '1000', border: OutlineInputBorder(), prefixIcon: Icon(Icons.stacked_line_chart_rounded)),
              style: const TextStyle(fontFamily: NetTypography.family),
            ),
          ],
        );
      case 2:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('أي فئة كروت تُصرف كمكافأة؟', style: TextStyle(fontFamily: NetTypography.family, fontWeight: FontWeight.w800, fontSize: 16, color: palette.textPrimary)),
            const SizedBox(height: 8),
            Text('اختر فئة نشطة من المخزون. يجب توفر كرت متاح عند بلوغ العتبة.', style: TextStyle(fontFamily: NetTypography.family, fontSize: 13, color: palette.textSecondary)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _rewardId,
              decoration: const InputDecoration(labelText: 'فئة المكافأة', border: OutlineInputBorder()),
              items: [
                for (final cat in widget.categories)
                  DropdownMenuItem(
                    value: cat.id,
                    child: Text(cat.name + ' · ' + formatMoneyMinor(cat.faceValue.minorUnits), style: const TextStyle(fontFamily: NetTypography.family)),
                  ),
              ],
              onChanged: (v) { if (v != null) setState(() => _rewardId = v); },
            ),
          ],
        );
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('مراجعة العرض قبل الحفظ', style: TextStyle(fontFamily: NetTypography.family, fontWeight: FontWeight.w800, fontSize: 16, color: palette.textPrimary)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: palette.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: palette.primary.withValues(alpha: 0.15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ReviewRow(label: 'العنوان', value: _titleCtrl.text.trim().isEmpty ? '—' : _titleCtrl.text.trim()),
                  const SizedBox(height: 8),
                  _ReviewRow(label: 'العتبة', value: _thresholdCtrl.text.trim().isEmpty ? '—' : _thresholdCtrl.text.trim() + ' ر.ي'),
                  const SizedBox(height: 8),
                  _ReviewRow(label: 'فئة المكافأة', value: _rewardName ?? _rewardId),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _notesCtrl,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)', border: OutlineInputBorder()),
              style: const TextStyle(fontFamily: NetTypography.family),
            ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final palette = KayanPalette.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 12),
              Text(
                widget.existing == null ? 'عرض ترويجي جديد' : 'تعديل العرض',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: NetTypography.family, fontWeight: FontWeight.w800, fontSize: 18, color: palette.primary),
              ),
              const SizedBox(height: 6),
              Text(
                'الخطوة ' + (_step + 1).toString() + ' من 4 — ' + _stepTitles[_step],
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: NetTypography.family, fontSize: 13, color: palette.textSecondary),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 4; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _step ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _step ? palette.primary : palette.border.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: PageView(
                  controller: _pageCtrl,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (i) => setState(() => _step = i),
                  children: [
                    for (var i = 0; i < 4; i++) SingleChildScrollView(child: _stepBody(i, palette)),
                  ],
                ),
              ),
              if (_status != null) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Icon(Icons.error_outline_rounded, size: 18, color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_status!, style: TextStyle(fontFamily: NetTypography.family, color: Theme.of(context).colorScheme.error))),
                ]),
              ],
              const SizedBox(height: 12),
              Row(children: [
                if (_step > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => _goTo(_step - 1),
                      child: const Text('السابق', style: TextStyle(fontFamily: NetTypography.family)),
                    ),
                  ),
                if (_step > 0) const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: _busy
                        ? null
                        : () async {
                            if (_step < 3) {
                              if (_validateStep(_step)) _goTo(_step + 1);
                              return;
                            }
                            await _submit();
                          },
                    child: _busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(
                            _step < 3 ? 'التالي' : 'حفظ العرض',
                            style: const TextStyle(fontFamily: NetTypography.family, fontWeight: FontWeight.w700),
                          ),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(label, style: TextStyle(fontFamily: NetTypography.family, fontSize: 13, color: palette.textSecondary, fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: Text(value, style: TextStyle(fontFamily: NetTypography.family, fontSize: 14, fontWeight: FontWeight.w700, color: palette.textPrimary)),
        ),
      ],
    );
  }
}
