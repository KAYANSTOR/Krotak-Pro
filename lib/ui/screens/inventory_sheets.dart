part of 'inventory_screen.dart';

class _CategoriesSheet extends StatefulWidget {
  const _CategoriesSheet({required this.categories, required this.onChanged});
  final List<domain.CardCategory> categories;
  final Future<void> Function() onChanged;
  @override
  State<_CategoriesSheet> createState() => _CategoriesSheetState();
}

class _CategoriesSheetState extends State<_CategoriesSheet> {
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (ctx, scroll) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(4))),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    const Expanded(child: Text('فئات الكروت', style: TextStyle(fontFamily: 'Tajawal', fontSize: 18, fontWeight: FontWeight.w800))),
                    FilledButton.tonalIcon(
                      onPressed: () => _createCategory(context),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('فئة جديدة', style: TextStyle(fontFamily: 'Tajawal')),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: widget.categories.isEmpty
                    ? const Center(
                        child: Text(
                          'لا توجد فئات بعد — أنشئ فئة بقيمة اسمية موجبة',
                          style: TextStyle(fontFamily: 'Tajawal', color: KayanColors.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        controller: scroll,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: widget.categories.length,
                        itemBuilder: (context, i) {
                          final cat = widget.categories[i];
                          final major = cat.faceValue.minorUnits / 100.0;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: KayanColors.lightBackground,
                              child: Text(
                                major == major.roundToDouble() ? major.toInt().toString() : major.toStringAsFixed(0),
                                style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700, color: KayanColors.primary, fontSize: 12),
                              ),
                            ),
                            title: Text(cat.name, style: const TextStyle(fontFamily: 'Tajawal')),
                            subtitle: Text('${major == major.roundToDouble() ? major.toInt() : major} ر.ي', style: const TextStyle(fontFamily: 'Tajawal', fontSize: 12)),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createCategory(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final valueCtrl = TextEditingController();
    String? localError;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: const Text('فئة جديدة', style: TextStyle(fontFamily: 'Tajawal')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'اسم الفئة (مثال: كرت 100)', border: OutlineInputBorder()), style: const TextStyle(fontFamily: 'Tajawal')),
                const SizedBox(height: 12),
                TextField(controller: valueCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))], decoration: const InputDecoration(labelText: 'القيمة الاسمية (ر.ي)', border: OutlineInputBorder()), style: const TextStyle(fontFamily: 'Tajawal')),
                if (localError != null) ...[
                  const SizedBox(height: 10),
                  Text(localError!, style: const TextStyle(fontFamily: 'Tajawal', color: Color(0xFFDC2626), fontSize: 13)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal')),
              ),
              FilledButton(
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  final major = num.tryParse(valueCtrl.text.trim());
                  if (name.isEmpty) {
                    setLocal(() => localError = 'أدخل اسم الفئة');
                    return;
                  }
                  if (major == null || major <= 0) {
                    setLocal(() => localError = 'أدخل قيمة اسمية صحيحة أكبر من صفر');
                    return;
                  }
                  final c = AppScope.of(context);
                  final r = await c.catalogService.saveCategory(
                    domain.CardCategory(
                      id: '',
                      name: name,
                      faceValue: Money(minorUnits: (major * 100).round(), currencyCode: 'YER'),
                      isActive: true,
                    ),
                  );
                  if (r is Failure) {
                    setLocal(() => localError = (r as Failure).error.message);
                    return;
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('حفظ', style: TextStyle(fontFamily: 'Tajawal')),
              ),
            ],
          ),
        ),
      ),
    );
    nameCtrl.dispose();
    valueCtrl.dispose();
    await widget.onChanged();
  }
}

class _AddCardsSheet extends StatefulWidget {
  const _AddCardsSheet({required this.categories, required this.initialCategoryId, required this.onDone});
  final List<domain.CardCategory> categories;
  final String initialCategoryId;
  final Future<void> Function() onDone;
  @override
  State<_AddCardsSheet> createState() => _AddCardsSheetState();
}

class _AddCardsSheetState extends State<_AddCardsSheet> {
  late String _categoryId;
  final _serialCtrl = TextEditingController();
  final _secretCtrl = TextEditingController();
  final _batchCtrl = TextEditingController();
  int _tab = 0;
  CardImportFormat _format = CardImportFormat.serialAndPin;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.initialCategoryId;
  }

  @override
  void dispose() {
    _serialCtrl.dispose();
    _secretCtrl.dispose();
    _batchCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveSingle() async {
    final serial = _serialCtrl.text.trim();
    final secret = _secretCtrl.text.trim();
    if (serial.isEmpty) return;
    if (_format == CardImportFormat.serialAndPin && secret.isEmpty) return;
    setState(() => _busy = true);
    final c = AppScope.of(context);
    final r = await c.catalogService.importCards(
      categoryId: _categoryId,
      drafts: [
        CardImportDraft(
          serialNumber: serial,
          secretCode: _format == CardImportFormat.serialOnly ? '' : secret,
          format: _format,
        ),
      ],
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (r is Failure) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text((r as Failure).error.message, style: const TextStyle(fontFamily: 'Tajawal'))));
      return;
    }
    final n = (r as Success<int>).value;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم استيراد $n كرت', style: const TextStyle(fontFamily: 'Tajawal'))));
    await widget.onDone();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _saveBatch() async {
    final parsed = CardImportParser.parse(_batchCtrl.text, format: _format);
    if (!parsed.hasDrafts) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(parsed.hasErrors ? parsed.errors.first : 'لا توجد أسطر صالحة', style: const TextStyle(fontFamily: 'Tajawal'))));
      return;
    }
    setState(() => _busy = true);
    final c = AppScope.of(context);
    final r = await c.catalogService.importCards(categoryId: _categoryId, drafts: parsed.drafts);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r is Failure) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text((r as Failure).error.message, style: const TextStyle(fontFamily: 'Tajawal'))));
      return;
    }
    final n = (r as Success<int>).value;
    final msg = parsed.hasErrors ? 'تم استيراد $n كرت — ${parsed.errors.length} سطر مرفوض' : 'تم استيراد $n كرت';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg, style: const TextStyle(fontFamily: 'Tajawal'))));
    await widget.onDone();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: Container(
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(4)))),
                const SizedBox(height: 12),
                const Text('إضافة الكروت', style: TextStyle(fontFamily: 'Tajawal', fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _categoryId,
                  decoration: const InputDecoration(labelText: 'الفئة', border: OutlineInputBorder()),
                  items: widget.categories.map((e) => DropdownMenuItem(value: e.id, child: Text('${e.name} (${e.faceValue.minorUnits / 100})', style: const TextStyle(fontFamily: 'Tajawal')))).toList(),
                  onChanged: (v) { if (v != null) setState(() => _categoryId = v); },
                ),
                const SizedBox(height: 12),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('مفرد', style: TextStyle(fontFamily: 'Tajawal'))),
                    ButtonSegment(value: 1, label: Text('مجموعة / ملف', style: TextStyle(fontFamily: 'Tajawal'))),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (s) => setState(() => _tab = s.first),
                ),
                const SizedBox(height: 12),
                const Text('نوع الكرت', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                SegmentedButton<CardImportFormat>(
                  segments: const [
                    ButtonSegment(
                      value: CardImportFormat.serialAndPin,
                      label: Text('رقم + رمز', style: TextStyle(fontFamily: 'Tajawal', fontSize: 12)),
                    ),
                    ButtonSegment(
                      value: CardImportFormat.serialOnly,
                      label: Text('رقم فقط', style: TextStyle(fontFamily: 'Tajawal', fontSize: 12)),
                    ),
                  ],
                  selected: {_format},
                  onSelectionChanged: (s) => setState(() => _format = s.first),
                ),
                const SizedBox(height: 12),
                if (_tab == 0) ...[
                  TextField(controller: _serialCtrl, decoration: const InputDecoration(labelText: 'رقم الكرت', border: OutlineInputBorder()), style: const TextStyle(fontFamily: 'Tajawal')),
                  if (_format == CardImportFormat.serialAndPin) ...[
                    const SizedBox(height: 10),
                    TextField(controller: _secretCtrl, decoration: const InputDecoration(labelText: 'رمز الكود / PIN', border: OutlineInputBorder()), style: const TextStyle(fontFamily: 'Tajawal')),
                  ],
                ] else ...[
                  TextField(
                    controller: _batchCtrl,
                    minLines: 6,
                    maxLines: 12,
                    decoration: InputDecoration(
                      labelText: _format == CardImportFormat.serialOnly
                          ? 'الصق أرقام الكروت (سطر لكل كرت)'
                          : 'الصق الأسطر (رقم,رمز) أو من ملف نصي',
                      alignLabelWithHint: true,
                      border: const OutlineInputBorder(),
                      hintText: _format == CardImportFormat.serialOnly
                          ? '776733907\n8273738\n99001122'
                          : '776733907,77330393\n8273738,112233',
                    ),
                    style: const TextStyle(fontFamily: 'Tajawal', fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _format == CardImportFormat.serialOnly
                        ? 'وضع رقم فقط: سطر واحد = رقم كرت. الفواصل تُتجاهل ويُؤخذ الحقل الأول.'
                        : 'وضع رقم+رمز: serial,secret أو serial;secret. سطر لكل كرت.',
                    style: const TextStyle(fontFamily: 'Tajawal', fontSize: 11, color: KayanColors.textSecondary),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : (_tab == 0 ? _saveSingle : _saveBatch),
                  style: FilledButton.styleFrom(backgroundColor: KayanColors.primary, padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('استيراد', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
