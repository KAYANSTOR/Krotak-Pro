part of 'inventory_screen.dart';

/// تأكيد حذف كرت واحد أو عدة كروت من المخزون.
///
/// يعرض الكروت المحددة مع فئتها وحالتها، ويحذّر صراحةً عند تضمين كروت محجوزة
/// أو مباعة (الحذف مخزوني فقط ولا يلغي العملية المالية المرتبطة).
/// لا يرجع `true` إلا بضغط المستخدم على «حذف نهائي».
Future<bool> showDeleteCardsConfirm({
  required BuildContext context,
  required List<domain.Card> cards,
  required String Function(String categoryId) categoryNameOf,
}) async {
  if (cards.isEmpty) return false;

  final reserved = cards.where((e) => e.status == domain.CardStatus.reserved).length;
  final sold = cards.where((e) => e.status == domain.CardStatus.sold).length;
  final available = cards.where((e) => e.status == domain.CardStatus.available).length;
  const previewLimit = 6;
  final preview = cards.take(previewLimit).toList(growable: false);
  final remaining = cards.length - preview.length;

  final result = await NetSheet.show<bool>(
    context,
    builder: (ctx) {
      final palette = KayanPalette.of(ctx);
      final net = ctx.netColors;
      return NetSheet(
        title: cards.length == 1
            ? 'حذف الكرت'
            : 'حذف ' + cards.length.toString() + ' كروت',
        subtitle: 'الحذف يزيل الكروت من المخزون نهائياً ولا يمكن التراجع عنه',
        icon: Icons.delete_forever_rounded,
        children: [
          Wrap(
            spacing: NetSpacing.sm,
            runSpacing: NetSpacing.sm,
            children: [
              if (available > 0)
                _DeleteChip(
                  color: net.available,
                  label: 'متاح ' + available.toString(),
                ),
              if (reserved > 0)
                _DeleteChip(
                  color: net.reserved,
                  label: 'محجوز ' + reserved.toString(),
                ),
              if (sold > 0)
                _DeleteChip(color: net.sold, label: 'مباع ' + sold.toString()),
            ],
          ),
          const SizedBox(height: NetSpacing.md),
          Container(
            decoration: BoxDecoration(
              color: palette.surfaceVariant.withValues(alpha: 0.35),
              borderRadius: NetRadii.smAll,
              border: Border.all(color: palette.border),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: NetSpacing.md,
              vertical: NetSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final card in preview)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Icon(Icons.style_rounded, size: 14, color: palette.textTertiary),
                        const SizedBox(width: NetSpacing.sm),
                        Expanded(
                          child: Text(
                            card.serialNumber,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: NetTypography.family,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: palette.textPrimary,
                            ),
                          ),
                        ),
                        Flexible(
                          child: Text(
                            categoryNameOf(card.categoryId) +
                                ' · ' +
                                cardStatusLabel(card.status),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.left,
                            style: TextStyle(
                              fontFamily: NetTypography.family,
                              fontSize: 11.5,
                              color: palette.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (remaining > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: NetSpacing.xs),
                    child: Text(
                      'و' + remaining.toString() + ' كرت آخر',
                      style: TextStyle(
                        fontFamily: NetTypography.family,
                        fontSize: 11.5,
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (reserved > 0 || sold > 0) ...[
            const SizedBox(height: NetSpacing.md),
            Container(
              decoration: BoxDecoration(
                color: net.warningContainer,
                borderRadius: NetRadii.smAll,
              ),
              padding: const EdgeInsets.all(NetSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 18, color: net.warning),
                  const SizedBox(width: NetSpacing.sm),
                  Expanded(
                    child: Text(
                      'التحذير: بين الكروت المحددة كروت محجوزة أو مباعة. حذفها يزيلها من المخزون فقط '
                      'ولا يلغي العملية المالية أو رسالة العميل المرتبطة بها، لذلك راجع السجلات قبل الحذف.',
                      style: TextStyle(
                        fontFamily: NetTypography.family,
                        fontSize: 12,
                        height: 1.5,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: NetSpacing.xl),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    'إلغاء',
                    style: TextStyle(fontFamily: NetTypography.family, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(width: NetSpacing.md),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, true),
                  icon: const Icon(Icons.delete_forever_rounded, size: 20),
                  label: const Text(
                    'حذف نهائي',
                    style: TextStyle(fontFamily: NetTypography.family, fontWeight: FontWeight.w800),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: net.rejected,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    },
  );
  return result ?? false;
}

/// ملخّص تحليل ملف/نص الاستيراد: الصالح، والمكرر في المخزون، والأسطر المرفوضة.
class _ImportPreviewCard extends StatelessWidget {
  const _ImportPreviewCard({required this.preview});

  final CardImportPreview preview;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final net = context.netColors;
    final ok = preview.canImport;
    final shownErrors = preview.parseErrors.take(4).toList(growable: false);
    return Container(
      margin: const EdgeInsets.only(top: NetSpacing.md),
      padding: const EdgeInsets.all(NetSpacing.md),
      decoration: BoxDecoration(
        color: ok ? net.successContainer : net.warningContainer,
        borderRadius: NetRadii.smAll,
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                ok ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
                size: 18,
                color: ok ? net.success : net.warning,
              ),
              const SizedBox(width: NetSpacing.sm),
              Expanded(
                child: Text(
                  preview.fileName == null
                      ? 'ملخص التحليل'
                      : 'ملخص التحليل · ' + preview.fileName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: palette.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: NetSpacing.sm),
          _previewLine(context, 'جاهز للاستيراد', preview.acceptedCount, net.success),
          if (preview.stockDuplicateCount > 0)
            _previewLine(
              context,
              'موجود مسبقاً في المخزون (سيُتخطى)',
              preview.stockDuplicateCount,
              net.warning,
            ),
          if (preview.parseErrors.isNotEmpty)
            _previewLine(
              context,
              'سطر مرفوض (صيغة غير صحيحة)',
              preview.parseErrors.length,
              net.rejected,
            ),
          if (shownErrors.isNotEmpty) ...[
            const SizedBox(height: NetSpacing.sm),
            for (final error in shownErrors)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '• ' + error,
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 11,
                    color: palette.textSecondary,
                  ),
                ),
              ),
            if (preview.parseErrors.length > shownErrors.length)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'و' + (preview.parseErrors.length - shownErrors.length).toString() + ' سطر آخر...',
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 11,
                    color: palette.textSecondary,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _previewLine(BuildContext context, String label, int value, Color color) {
    final palette = KayanPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: NetSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontSize: 12,
                color: palette.textSecondary,
              ),
            ),
          ),
          Text(
            value.toString(),
            style: TextStyle(
              fontFamily: NetTypography.family,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeleteChip extends StatelessWidget {
  const _DeleteChip({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: NetSpacing.sm, vertical: NetSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: NetRadii.pillAll,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: NetTypography.family,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _AddCardsSheet extends StatefulWidget {
  const _AddCardsSheet({
    required this.categories,
    required this.initialCategoryId,
    required this.onDone,
    this.initialTab = 0,
    this.fileOnly = false,
  });
  final List<domain.CardCategory> categories;
  final String initialCategoryId;
  final Future<void> Function() onDone;
  /// 0 = مفرد، 1 = مجموعة/ملف.
  final int initialTab;
  /// عند true تُخفى تبويبة الإدخال المفرد ويُفتح مسار الملف مباشرة.
  final bool fileOnly;
  @override
  State<_AddCardsSheet> createState() => _AddCardsSheetState();
}

class _AddCardsSheetState extends State<_AddCardsSheet> {
  late String _categoryId;
  final _serialCtrl = TextEditingController();
  final _secretCtrl = TextEditingController();
  final _batchCtrl = TextEditingController();
  late int _tab;
  CardImportFormat _format = CardImportFormat.serialAndPin;
  bool _busy = false;
  bool _analyzing = false;

  /// نتيجة تحليل آخر نص/ملف — تُحفظ مع مصدرها لتفادي قراءة المخزون عند كل حرف.
  CardImportPreview? _preview;
  String _analyzedSource = '';
  CardImportFormat? _analyzedFormat;
  String? _fileName;

  /// يحلل النص الحالي: يفصل السطور الصالحة عن المرفوضة وعن المكرر في المخزون.
  ///
  /// يُعيد النتيجة المخزنة إن كان النص والنوع لم يتغيرا، وإلا يقرأ المخزون مرة.
  Future<CardImportPreview?> _analyze({bool force = false}) async {
    final raw = _batchCtrl.text;
    if (raw.trim().isEmpty) {
      if (mounted) setState(() => _preview = null);
      return null;
    }
    final cached = _preview;
    if (!force && cached != null && _analyzedSource == raw && _analyzedFormat == _format) {
      return cached;
    }

    setState(() => _analyzing = true);
    final parsed = CardImportParser.parse(raw, format: _format);
    final c = AppScope.of(context);
    final existing = await c.cards.existingSerialsAmong(
      parsed.drafts.map((d) => d.serialNumber),
    );
    if (!mounted) return null;
    final stockDuplicates =
        existing is Success<Set<String>> ? existing.value : const <String>{};
    final preview = CardImportPreview(
      drafts: parsed.drafts,
      parseErrors: parsed.errors,
      stockDuplicateSerials: stockDuplicates,
      fileName: _fileName,
    );
    setState(() {
      _analyzing = false;
      _preview = preview;
      _analyzedSource = raw;
      _analyzedFormat = _format;
    });
    return preview;
  }

  @override
  void initState() {
    super.initState();
    _categoryId = widget.initialCategoryId;
    _tab = widget.fileOnly ? 1 : widget.initialTab.clamp(0, 1);
  }

  @override
  void dispose() {
    _serialCtrl.dispose();
    _secretCtrl.dispose();
    _batchCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        // pdf مدعوم عبر CardImportFileReader، والامتدادات المجهولة تُقرأ كنص UTF-8.
        allowedExtensions: CardImportFileReader.allowedExtensions,
        withData: true,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      Uint8List? bytes = file.bytes;
      if ((bytes == null || bytes.isEmpty) &&
          file.path != null &&
          file.path!.isNotEmpty) {
        bytes = await File(file.path!).readAsBytes();
      }
      if (bytes == null || bytes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تعذر قراءة الملف أو الملف فارغ',
              style: TextStyle(fontFamily: 'Tajawal'),
            ),
          ),
        );
        return;
      }

      // قراءة UTF-8 صحيحة (مع تجاوز BOM) بدل `String.fromCharCodes` الذي كان
      // يُفسد الأرقام العربية والرموز، واستخراج نص PDF المدعوم.
      final read = CardImportFileReader.read(fileName: file.name, bytes: bytes);
      if (!read.isOk) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              read.errorMessage ??
                  'يُسمح فقط بملفات PDF أو Excel (.xlsx) أو CSV',
              style: const TextStyle(fontFamily: 'Tajawal'),
            ),
          ),
        );
        return;
      }
      final content = read.text;
      if (content.trim().isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'لم يُعثر على بيانات كروت في الملف (' + file.name + ')',
              style: const TextStyle(fontFamily: 'Tajawal'),
            ),
          ),
        );
        return;
      }
      setState(() {
        _batchCtrl.text = content;
        _fileName = file.name;
        _tab = 1;
        _preview = null;
      });
      final preview = await _analyze(force: true);
      if (!mounted || preview == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم تحميل الملف: ' +
                preview.acceptedCount.toString() +
                ' كرت صالح' +
                (preview.stockDuplicateCount > 0
                    ? ' · ' + preview.stockDuplicateCount.toString() + ' مكرر في المخزون'
                    : '') +
                (preview.parseErrors.isNotEmpty
                    ? ' · ' + preview.parseErrors.length.toString() + ' سطر مرفوض'
                    : ''),
            style: const TextStyle(fontFamily: 'Tajawal'),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'فشل اختيار الملف: ' + e.toString(),
            style: const TextStyle(fontFamily: 'Tajawal'),
          ),
        ),
      );
    }
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text((r as Failure<dynamic>).error.message, style: const TextStyle(fontFamily: 'Tajawal'))));
      return;
    }
    final n = (r as Success<int>).value;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم استيراد ' + n.toString() + ' كرت', style: const TextStyle(fontFamily: 'Tajawal'))));
    await widget.onDone();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _saveBatch() async {
    final preview = await _analyze();
    if (!mounted) return;
    if (preview == null || !preview.canImport) {
      final msg = preview == null
          ? 'لا توجد أسطر صالحة في النص أو الملف'
          : (preview.parseErrors.isNotEmpty
              ? preview.parseErrors.first
              : 'كل الأرقام في الملف موجودة مسبقاً في المخزون');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg, style: const TextStyle(fontFamily: 'Tajawal'))),
      );
      return;
    }
    setState(() => _busy = true);
    final c = AppScope.of(context);
    // يُمرَّر المقبول فقط: المكرر في المخزون كان يُفشل الدفعة كاملة قبل ذلك.
    final r = await c.catalogService.importCards(
      categoryId: _categoryId,
      drafts: preview.acceptedDrafts,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (r is Failure) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text((r as Failure<dynamic>).error.message, style: const TextStyle(fontFamily: 'Tajawal'))));
      return;
    }
    final n = (r as Success<int>).value;
    final skipped = preview.stockDuplicateCount > 0
        ? ' — تم تخطي ' + preview.stockDuplicateCount.toString() + ' مكرر'
        : '';
    final rejected = preview.parseErrors.isNotEmpty
        ? ' — ' + preview.parseErrors.length.toString() + ' سطر مرفوض'
        : '';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم استيراد ' + n.toString() + ' كرت' + skipped + rejected, style: const TextStyle(fontFamily: 'Tajawal'))));
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
          decoration: BoxDecoration(color: KayanPalette.of(context).surface, borderRadius: NetRadii.sheetTop),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: KayanPalette.of(context).border, borderRadius: NetRadii.pillAll))),
                const SizedBox(height: 12),
                const Text('إضافة الكروت', style: TextStyle(fontFamily: 'Tajawal', fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _categoryId,
                  decoration: const InputDecoration(labelText: 'الفئة', border: OutlineInputBorder()),
                  items: widget.categories.map((e) => DropdownMenuItem(value: e.id, child: Text(e.name + ' (' + (e.faceValue.minorUnits / 100).toString() + ')', style: const TextStyle(fontFamily: 'Tajawal')))).toList(),
                  onChanged: (v) { if (v != null) setState(() => _categoryId = v); },
                ),
                const SizedBox(height: 12),
                if (!widget.fileOnly)
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('مفرد', style: TextStyle(fontFamily: 'Tajawal'))),
                      ButtonSegment(value: 1, label: Text('مجموعة / ملف', style: TextStyle(fontFamily: 'Tajawal'))),
                    ],
                    selected: {_tab},
                    onSelectionChanged: (s) => setState(() => _tab = s.first),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: KayanPalette.of(context).primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: KayanPalette.of(context).primary.withValues(alpha: 0.25)),
                    ),
                    child: const Text(
                      'استيراد من ملف فقط — الصيغ المدعومة: PDF و Excel (.xlsx) و CSV.\nاضغط «اختيار ملف» ثم راجع التحليل قبل الاستيراد.',
                      style: TextStyle(fontFamily: 'Tajawal', fontSize: 13, height: 1.4),
                    ),
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
                  onSelectionChanged: (s) => setState(() {
                    _format = s.first;
                    // النوع يغيّر طريقة التحليل، فيُعاد التحليل بنوع جديد.
                    _preview = null;
                  }),
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
                    onChanged: (_) => setState(() {
                      // أي تعديل يدوي يبطل التحليل السابق حتى لا تُستورد قائمة قديمة.
                      if (_preview != null || _analyzing) {
                        _preview = null;
                        _analyzing = false;
                      }
                    }),
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
                    style: TextStyle(fontFamily: 'Tajawal', fontSize: 11, color: KayanPalette.of(context).textSecondary),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy || _analyzing ? null : () => _analyze(force: true),
                          icon: const Icon(Icons.fact_check_outlined, size: 18),
                          label: const Text(
                            'تحليل',
                            style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _pickFile,
                          icon: const Icon(Icons.folder_open_outlined, size: 18),
                          label: const Text(
                            'اختيار ملف',
                            style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_analyzing)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: LinearProgressIndicator(minHeight: 3),
                    ),
                  if (!_analyzing && _preview != null) _ImportPreviewCard(preview: _preview!),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : (_tab == 0 ? _saveSingle : _saveBatch),
                  style: FilledButton.styleFrom(backgroundColor: KayanPalette.of(context).primary, padding: const EdgeInsets.symmetric(vertical: 14)),
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
