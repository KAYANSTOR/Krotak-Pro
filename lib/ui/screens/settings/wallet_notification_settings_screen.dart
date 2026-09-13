import 'package:flutter/material.dart';
import '../../../core/result.dart';
import '../../../domain/entities/payment_event.dart';
import '../../../domain/services/local_payment_source_registry.dart';
import '../../app_scope.dart';

class WalletNotificationSettingsScreen extends StatefulWidget {
  const WalletNotificationSettingsScreen({super.key});
  @override
  State<WalletNotificationSettingsScreen> createState() => _WalletNotificationSettingsScreenState();
}

class _WalletNotificationSettingsScreenState extends State<WalletNotificationSettingsScreen> {
  bool _accessGranted = false;
  bool _loading = true;
  List<PaymentSource> _sources = const [];

  @override
  void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) => _load()); }

  Future<void> _load() async {
    final c = AppScope.of(context);
    final access = await c.notificationBridge.isAccessGranted();
    final result = await c.notificationSources.list();
    if (!mounted) return;
    setState(() { _accessGranted = access; _loading = false; _sources = result is Success<List<PaymentSource>> ? result.value : const []; });
  }

  Future<void> _openAccess() => AppScope.of(context).notificationBridge.openAccessSettings();
  Future<void> _sync() async { await AppScope.of(context).notificationHandler.refreshSources(); await _load(); }

  Future<void> _add() async {
    final name = TextEditingController();
    final package = TextEditingController();
    final saved = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('إضافة مصدر محفظة'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم المحفظة')),
        const SizedBox(height: 12),
        TextField(controller: package, decoration: const InputDecoration(labelText: 'اسم حزمة Android', hintText: 'com.example.wallet')),
        const SizedBox(height: 8),
        const Text('لا نخمن أسماء الحزم. استخدم الاسم الفعلي للتطبيق بعد التحقق منه على الجهاز.', style: TextStyle(fontSize: 12)),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ'))],
    ));
    if (saved != true || !mounted) { name.dispose(); package.dispose(); return; }
    final result = await AppScope.of(context).notificationSources.upsert(displayName: name.text, packageName: package.text, enabled: true);
    name.dispose(); package.dispose();
    if (result is Failure) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.error.message))); return; }
    await _sync();
  }

  Future<void> _toggle(PaymentSource source, bool enabled) async {
    final result = await AppScope.of(context).notificationSources.setEnabled(source.packageName!, enabled);
    if (result is Failure) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.error.message))); return; }
    await _sync();
  }

  Future<void> _remove(PaymentSource source) async {
    final yes = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('حذف المصدر'),
      content: Text('سيتم إيقاف استقبال إشعارات ${source.displayName}.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف'))],
    ));
    if (yes != true || !mounted) return;
    await AppScope.of(context).notificationSources.remove(source.packageName!);
    await _sync();
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(title: const Text('إشعارات المحافظ', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold))),
      body: _loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Card(child: ListTile(
            leading: Icon(_accessGranted ? Icons.notifications_active : Icons.notifications_off_outlined),
            title: Text(_accessGranted ? 'وصول الإشعارات مفعّل' : 'وصول الإشعارات غير مفعّل', style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
            subtitle: const Text('يتم قراءة إشعارات مصادر الدفع التي يحددها المشغّل فقط.', style: TextStyle(fontFamily: 'Tajawal')),
            trailing: FilledButton(onPressed: _openAccess, child: const Text('فتح الإعدادات')),
          )),
          const SizedBox(height: 12),
          Row(children: [const Expanded(child: Text('مصادر الدفع عبر الإشعارات', style: TextStyle(fontFamily: 'Tajawal', fontSize: 17, fontWeight: FontWeight.bold))), IconButton(onPressed: _add, icon: const Icon(Icons.add_circle_outline))]),
          if (_sources.isEmpty)
            const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('لم تتم إضافة أي مصدر. لا يتم تخمين اسم الحزمة أو معالجة تطبيقات غير مهيأة.', style: TextStyle(fontFamily: 'Tajawal'))))
          else
            ..._sources.map((source) => Card(child: ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: Text(source.displayName, style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
              subtitle: Text(source.packageName!, style: const TextStyle(fontSize: 12)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [Switch(value: source.enabled, onChanged: (v) => _toggle(source, v)), IconButton(onPressed: () => _remove(source), icon: const Icon(Icons.delete_outline))]),
            )),
          const SizedBox(height: 12),
          const Text('يُحفظ الإشعار مؤقتًا في طابور نقل مشفّر، ثم يُمرر إلى محرك الدفع الموحد. الفشل في المعالجة لا يحذف الحركة من سجل المراجعة.', style: TextStyle(fontFamily: 'Tajawal', fontSize: 12)),
        ]),
      ),
    ),
  );
}
