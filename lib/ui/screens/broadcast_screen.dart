import 'package:flutter/material.dart';

import '../labels/net_labels.dart';
import '../theme/kayan_palette.dart';
import '../theme/net_semantic_colors.dart';
import '../theme/net_tokens.dart';
import '../widgets/async_views.dart';
import '../widgets/net/net_app_bar_title.dart';
import '../widgets/net/net_surface_card.dart';

import '../../core/result.dart';
import '../../domain/entities/broadcast.dart';
import '../app_scope.dart';

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

  Widget _statRow(String label, String value, {Color? color}) {
    final palette = KayanPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: NetSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontSize: 13,
                color: palette.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: NetTypography.family,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: color ?? palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const NetAppBarTitle(
            icon: Icons.campaign_rounded,
            title: 'بث SMS للعملاء',
          ),
        ),
        body: ListView(
          padding: NetSpacing.screen,
          children: [
            const NetInlineNotice(
              message:
                  'أرسل رسالة جماعية للعملاء المؤهلين. يتم استبعاد المحظورين والأرقام غير الصالحة وغير النشطين.',
              icon: Icons.groups_2_outlined,
            ),
            const SizedBox(height: NetSpacing.lg),
            NetSurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _bodyCtrl,
                    minLines: 4,
                    maxLines: 8,
                    decoration: const InputDecoration(labelText: 'نص الرسالة'),
                  ),
                  const SizedBox(height: NetSpacing.md),
                  FilledButton(
                    onPressed: _loadingPreview || _running ? null : _loadPreview,
                    child: const Text('حساب المستلمين'),
                  ),
                ],
              ),
            ),
            if (_loadingPreview) ...[
              const SizedBox(height: NetSpacing.md),
              const AsyncLoadingView(skeleton: true, skeletonCount: 2),
            ],
            if (_error != null) ...[
              const SizedBox(height: NetSpacing.md),
              NetInlineNotice(
                message: _error!,
                icon: Icons.error_outline_rounded,
                color: Theme.of(context).colorScheme.error,
              ),
            ],
            if (_preview != null) ...[
              const SizedBox(height: NetSpacing.lg),
              NetSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _statRow(
                      'المستلمون المؤهلون',
                      '${_preview!.eligibleCount}',
                      color: context.netColors.available,
                    ),
                    _statRow('مستبعدون — محظورون', '${_preview!.excludedBlacklisted}'),
                    _statRow('مستبعدون — رقم تالف', '${_preview!.excludedInvalidPhone}'),
                    _statRow('مستبعدون — غير نشطين', '${_preview!.excludedInactive}'),
                    const SizedBox(height: NetSpacing.sm),
                    TextField(
                      controller: _confirmCtrl,
                      decoration: const InputDecoration(
                        labelText: 'اكتب كلمة إرسال للتأكيد',
                      ),
                    ),
                    const SizedBox(height: NetSpacing.md),
                    FilledButton.tonal(
                      onPressed: _running || _preview!.eligibleCount == 0
                          ? null
                          : _confirmAndSend,
                      child: Text(_running ? 'جاري الإرسال…' : 'تأكيد وإرسال'),
                    ),
                  ],
                ),
              ),
            ],
            if (_progress != null) ...[
              const SizedBox(height: NetSpacing.lg),
              NetSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'التقدم: ${_progress!.done} / ${_progress!.total}',
                            style: TextStyle(
                              fontFamily: NetTypography.family,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: palette.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          broadcastStatusLabel(_progress!.status),
                          style: TextStyle(
                            fontFamily: NetTypography.family,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: broadcastStatusColor(
                              _progress!.status,
                              context.netColors,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: NetSpacing.sm),
                    ClipRRect(
                      borderRadius: NetRadii.xsAll,
                      child: LinearProgressIndicator(
                        minHeight: 6,
                        value: _progress!.total == 0
                            ? 0
                            : _progress!.done / _progress!.total,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_job != null) ...[
              const SizedBox(height: NetSpacing.lg),
              NetSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _statRow(
                      'أُرسل',
                      '${_job!.sentCount}',
                      color: context.netColors.available,
                    ),
                    _statRow(
                      'فشل',
                      '${_job!.failedCount}',
                      color: _job!.failedCount > 0
                          ? context.netColors.rejected
                          : null,
                    ),
                    _statRow('تخطي', '${_job!.skippedCount}'),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
