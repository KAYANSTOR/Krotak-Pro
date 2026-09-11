import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/card.dart';
import '../../domain/entities/money.dart';
import '../../domain/services/services.dart';
import '../app_scope.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _nameCtrl = TextEditingController(text: 'فئة افتراضية');
  final _faceCtrl = TextEditingController(text: '1000');
  final _serialCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  String? _status;
  String? _categoryId;
  bool _busy = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _faceCtrl.dispose();
    _serialCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveCategory() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    final c = AppScope.of(context);
    final face = int.tryParse(_faceCtrl.text.trim()) ?? 0;
    final category = CardCategory(
      id: c.ids.next('cat'),
      name: _nameCtrl.text,
      faceValue: Money(minorUnits: face * 100, currencyCode: 'YER'),
      isActive: true,
    );
    final result = await c.catalogService.saveCategory(category);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result is Success<CardCategory>) {
        _categoryId = result.value.id;
        _status = 'تم حفظ الفئة: ${result.value.name}';
      } else {
        _status = (result as Failure).error.message;
      }
    });
  }

  Future<void> _importCard() async {
    if (_categoryId == null) {
      setState(() => _status = 'أنشئ فئة أولاً');
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
    });
    final c = AppScope.of(context);
    final result = await c.catalogService.importCards(
      categoryId: _categoryId!,
      drafts: [
        CardImportDraft(
          serialNumber: _serialCtrl.text.trim(),
          secretCode: _pinCtrl.text.trim(),
        ),
      ],
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result is Success<int>) {
        _status = 'تم استيراد ${result.value} كرت';
        _serialCtrl.clear();
        _pinCtrl.clear();
      } else {
        _status = (result as Failure).error.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('فئة الكروت', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(
            labelText: 'اسم الفئة',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _faceCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'القيمة الاسمية (ريال)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _busy ? null : _saveCategory,
          child: const Text('حفظ الفئة'),
        ),
        const Divider(height: 32),
        Text('استيراد كرت', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          controller: _serialCtrl,
          decoration: const InputDecoration(
            labelText: 'الرقم التسلسلي',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _pinCtrl,
          decoration: const InputDecoration(
            labelText: 'الرمز السري',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _busy ? null : _importCard,
          child: const Text('استيراد'),
        ),
        if (_status != null) ...[
          const SizedBox(height: 12),
          Text(_status!),
        ],
      ],
    );
  }
}
