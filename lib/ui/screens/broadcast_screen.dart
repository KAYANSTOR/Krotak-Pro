import 'package:flutter/material.dart';

import '../widgets/net/net_app_bar_title.dart';

import '../../core/result.dart';
import '../../domain/entities/broadcast.dart';
import '../app_scope.dart';
import '../theme/kayan_colors.dart';
import '../widgets/async_views.dart';

class BroadcastScreen extends StatefulWidget {
  const BroadcastScreen({super.key});

  @override
  State<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends State<BroadcastScreen> {
  final _bodyCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loadingPreview = false;
  bool _running = false;
  String? _error;
  BroadcastPreview? _preview;
  BroadcastJob? _job;
  BroadcastProgress? _progress;

  @override
  void dispose() {
    _bodyCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPreview() async {
    setState(() {
      _loadingPreview = true;
      _error = null;
    });
    final result = await AppScope.of(context).broadcastService.preview(body: _bodyCtrl.text);
    if (!mounted) return;
    setState(() {
      _loadingPreview = false;
      if (result is Failure<BroadcastPreview>) {
        _error = result.error.message;
        _preview = null;
      } else {
        _preview = (result as Success<BroadcastPreview>).value;
      }
    });
  }

  Future<void> _confirmAndSend() async {
    setState(() {
      _running = true;
      _error = null;
    });
    final c = AppScope.of(context);
    final confirmed = await c.broadcastService.confirm(
      body: _bodyCtrl.text,
      confirmationPhrase: _confirmCtrl.text,
    );
    if (!mounted) return;
    if (confirmed is Failure<BroadcastJob>) {
      setState(() {
        _running = false;
        _error = confirmed.error.message;
      });
      return;
    }
    final job = (confirmed as Success<BroadcastJob>).value;
    setState(() => _job = job);
    final ran = await c.broadcastService.run(
      job.id,
      onProgress: (progress) {
        if (!mounted) return;
        setState(() => _progress = progress);
      },
    );
    if (!mounted) return;
    setState(() {
      _running = false;
      if (ran is Failure<BroadcastJob>) {
        _error = ran.error.message;
      } else {
        _job = (ran as Success<BroadcastJob>).value;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: const NetAppBarTitle(icon: Icons.campaign_rounded, title: 'بث SMS للعملاء'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'أرسل رسالة جماعية للعملاء المؤهلين. يتم استبعاد المحظورين والأرقام غير الصالحة وغير النشطين.',
              style: TextStyle(
                fontFamily: 'Tajawal',
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _bodyCtrl,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'نص الرسالة',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _loadingPreview || _running ? null : _loadPreview,
              child: const Text('حساب المستلمين'),
            ),
            if (_loadingPreview) const Padding(padding: EdgeInsets.all(16), child: AsyncLoadingView()),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            if (_preview != null) ...[
              const SizedBox(height: 16),
              Text('المستلمون المؤهلون: ${_preview!.eligibleCount}'),
              Text('مستبعدون — محظورون: ${_preview!.excludedBlacklisted}'),
              Text('مستبعدون — رقم تالف: ${_preview!.excludedInvalidPhone}'),
              Text('مستبعدون — غير نشطين: ${_preview!.excludedInactive}'),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmCtrl,
                decoration: const InputDecoration(
                  labelText: 'اكتب كلمة إرسال للتأكيد',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: _running || _preview!.eligibleCount == 0 ? null : _confirmAndSend,
                child: Text(_running ? 'جاري الإرسال…' : 'تأكيد وإرسال'),
              ),
            ],
            if (_progress != null) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: _progress!.total == 0 ? 0 : _progress!.done / _progress!.total,
              ),
              const SizedBox(height: 8),
              Text('التقدم: ${_progress!.done} / ${_progress!.total} — ${_progress!.status.name}'),
            ],
            if (_job != null) ...[
              const SizedBox(height: 16),
              Text('أُرسل: ${_job!.sentCount}'),
              Text('فشل: ${_job!.failedCount}'),
              Text('تخطي: ${_job!.skippedCount}'),
            ],
          ],
        ),
      ),
    );
  }
}
