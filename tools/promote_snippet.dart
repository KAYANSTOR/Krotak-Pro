    await _load();
  }

  Future<void> _promoteToCustomer() async {
    final customer = _customer;
    if (customer == null || customer.status != CustomerStatus.provisional) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'اعتماد كعميل',
            style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800),
          ),
          content: Text(
            'سيتم تحويل هذا الحساب الدفتري المؤقت إلى عميل نشط.\nالاسم الحالي: ${customer.displayName}',
            style: const TextStyle(fontFamily: 'Tajawal'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('اعتماد', style: TextStyle(fontFamily: 'Tajawal')),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final r = await AppScope.of(context).customerService.promoteToActive(widget.customerId);
    if (!mounted) return;
    if (r is Failure<Customer>) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r.error.message, style: const TextStyle(fontFamily: 'Tajawal'))),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم اعتماد الحساب كعميل نشط', style: TextStyle(fontFamily: 'Tajawal'))),
    );
    await _load();
  }

  Future<void> _adjustBalance() async {