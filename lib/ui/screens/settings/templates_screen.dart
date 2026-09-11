import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/message.dart';
import '../../app_scope.dart';
import '../../widgets/async_views.dart';

class TemplatesScreen extends StatefulWidget {
  const TemplatesScreen({super.key});
  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  bool _loading = true;
  String? _error;
  List<TransferTemplate> _items = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final r = await AppScope.of(context).transferTemplates.listAll();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r is Success<List<TransferTemplate>>) {
        _items = r.value;
      } else {
        _error = (r as Failure).error.message;
      }
    });
  }

  Future<void> _add() async {
    final nameCtrl = TextEditingController();
    final patternCtrl = TextEditingController(text: 'تم تحويل {amount} ريال الى {phone} برقم العملية {ref}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('قالب جديد', style: TextStyle(fontFamily: 'Tajawal')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'الاسم')),
            TextField(controller: patternCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'النمط')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok != true || !mounted) { nameCtrl.dispose(); patternCtrl.dispose(); return; }
    final c = AppScope.of(context);
    final r = await c.transferTemplates.save(TransferTemplate(id: c.ids.next('tpl'), name: nameCtrl.text.trim(), pattern: patternCtrl.text.trim(), isActive: true));
    nameCtrl.dispose(); patternCtrl.dispose();
    if (r is Failure && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text((r as Failure).error.message)));
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('قوالب التحويل')),
      floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.add)),
      body: _loading
          ? const AsyncLoadingView()
          : _error != null
              ? AsyncErrorView(message: _error!, onRetry: _load)
              : _items.isEmpty
                  ? AsyncEmptyView(message: 'لا قوالب', actionLabel: 'إضافة', onAction: _add)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final t = _items[i];
                          return ListTile(
                            title: Text(t.name, style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
                            subtitle: Text(t.pattern, maxLines: 2, style: const TextStyle(fontFamily: 'Tajawal', fontSize: 12)),
                            trailing: Text(t.isActive ? 'نشط' : 'متوقف', style: const TextStyle(fontFamily: 'Tajawal')),
                          );
                        },
                      ),
                    ),
    );
  }
}
