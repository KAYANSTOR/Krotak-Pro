import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/message.dart';
import '../../app_scope.dart';
import '../../widgets/async_views.dart';

class CleanLogsScreen extends StatefulWidget {
  const CleanLogsScreen({super.key});
  @override
  State<CleanLogsScreen> createState() => _CleanLogsScreenState();
}

class _CleanLogsScreenState extends State<CleanLogsScreen> {
  bool _loading = true;
  String? _error;
  int _pending = 0;
  int _rejected = 0;
  int _failed = 0;
  String? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final c = AppScope.of(context);
    final pending = await c.messages.pendingProcessing();
    final rejected = await c.messages.listByStatus(MessageProcessingStatus.rejected);
    final failed = await c.messages.listByStatus(MessageProcessingStatus.failed);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (pending is Failure || rejected is Failure || failed is Failure) {
        _error = 'تعذر قراءة السجلات';
        return;
      }
      _pending = (pending as Success).value.length;
      _rejected = (rejected as Success).value.length;
      _failed = (failed as Success).value.length;
    });
  }

  Future<void> _recover() async {
    final r = await AppScope.of(context).recoveryService.recoverPending();
    if (!mounted) return;
    setState(() {
      if (r is Success) {
        final report = (r as Success).value;
        _status = 'استعادة: processed=${report.processed} failed=${report.failed}';
      } else {
        _status = (r as Failure).error.message;
      }
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تنظيف السجلات')),
      body: _loading
          ? const AsyncLoadingView()
          : _error != null
              ? AsyncErrorView(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('معلّقة/واردة: $_pending', style: const TextStyle(fontFamily: 'Tajawal')),
                    Text('مرفوضة: $_rejected', style: const TextStyle(fontFamily: 'Tajawal')),
                    Text('فاشلة: $_failed', style: const TextStyle(fontFamily: 'Tajawal')),
                    const SizedBox(height: 12),
                    const Text('لا حذف جماعي في Domain. يمكن استعادة المعلّق.', style: TextStyle(fontFamily: 'Tajawal', fontSize: 13)),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _recover, child: const Text('استعادة المعلّق')),
                    if (_status != null) ...[const SizedBox(height: 12), Text(_status!, style: const TextStyle(fontFamily: 'Tajawal'))],
                  ],
                ),
    );
  }
}
