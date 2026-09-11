import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/customer.dart';
import '../app_scope.dart';
import '../routing/app_routes.dart';
import '../theme/kayan_colors.dart';
import '../widgets/async_views.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  String? _error;
  List<Customer> _items = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load([String query = '']) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final c = AppScope.of(context);
    final result = await c.customers.search(query);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result is Success<List<Customer>>) {
        _items = result.value
            .where((e) => e.status != CustomerStatus.merged)
            .toList(growable: false);
      } else {
        _error = (result as Failure).error.message;
        _items = const [];
      }
    });
  }

  Future<void> _showCreateSheet() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        var busy = false;
        String? status;
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'إضافة عميل',
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'اسم العميل',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'رقم الهاتف',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (status != null) ...[
                    const SizedBox(height: 8),
                    Text(status!, style: const TextStyle(color: KayanColors.warning)),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () async {
                            setModal(() => busy = true);
                            final c = AppScope.of(ctx);
                            final r = await c.customerService.create(
                              displayName: nameCtrl.text,
                              identifierType: CustomerIdentifierType.phoneNumber,
                              identifierValue: phoneCtrl.text,
                            );
                            if (!ctx.mounted) return;
                            if (r is Success<Customer>) {
                              Navigator.pop(ctx, true);
                            } else {
                              setModal(() {
                                busy = false;
                                status = (r as Failure).error.message;
                              });
                            }
                          },
                    child: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('حفظ'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    nameCtrl.dispose();
    phoneCtrl.dispose();
    if (created == true) await _load(_searchCtrl.text);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'بحث بالاسم أو الرقم',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    isDense: true,
                  ),
                  onSubmitted: _load,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _showCreateSheet,
                icon: const Icon(Icons.person_add_alt_1),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const AsyncLoadingView()
              : _error != null
                  ? AsyncErrorView(message: _error!, onRetry: () => _load(_searchCtrl.text))
                  : _items.isEmpty
                      ? AsyncEmptyView(
                          message: 'لا يوجد عملاء',
                          actionLabel: 'إضافة عميل',
                          onAction: _showCreateSheet,
                        )
                      : RefreshIndicator(
                          onRefresh: () => _load(_searchCtrl.text),
                          child: ListView.separated(
                            itemCount: _items.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final customer = _items[i];
                              return ListTile(
                                title: Text(
                                  customer.displayName,
                                  style: const TextStyle(
                                    fontFamily: 'Tajawal',
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  customer.status.name,
                                  style: const TextStyle(fontFamily: 'Tajawal', fontSize: 12),
                                ),
                                trailing: const Icon(Icons.chevron_left),
                                onTap: () => AppRoutes.openCustomerDetail(context, customer.id)
                                    .then((_) => _load(_searchCtrl.text)),
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }
}
