import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/customer.dart';
import '../app_scope.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String? _status;
  bool _busy = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    final c = AppScope.of(context);
    final result = await c.customerService.create(
      displayName: _nameCtrl.text,
      identifierType: CustomerIdentifierType.phoneNumber,
      identifierValue: _phoneCtrl.text,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result is Success<Customer>) {
        _status = 'تم إنشاء العميل: ${result.value.displayName}';
        _nameCtrl.clear();
        _phoneCtrl.clear();
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
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(
            labelText: 'اسم العميل',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'رقم الهاتف',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _create,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('إضافة عميل'),
        ),
        if (_status != null) ...[
          const SizedBox(height: 12),
          Text(_status!),
        ],
      ],
    );
  }
}
