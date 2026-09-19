import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../core/result.dart';
import '../../../domain/services/local_backup_service.dart';
import '../../app_scope.dart';
import '../../theme/kayan_palette.dart';
import '../../theme/net_semantic_colors.dart';
import '../../theme/net_tokens.dart';
import '../../widgets/async_views.dart';
import '../../widgets/net/net_app_bar_title.dart';
import '../../widgets/net/net_surface_card.dart';

/// النسخ الاحتياطي واستعادة البيانات — إعدادات + قاعدة البيانات داخل .znet
class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  bool _loading = true;
  String? _error;
  List<File> _backups = const [];
  bool _creating = false;
  bool _restoring = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final c = AppScope.of(context);
    final r = await c.backupService.listBackups();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r is Failure) {
        _error = (r as Failure).error.message;
        _backups = const [];
      } else {
        _backups = (r as Success<List<File>>).value;
      }
    });
  }

  Future<void> _createBackup() async {
    final password = await _askPassword(
      title: 'إنشاء نسخة احتياطية',
      confirmLabel: 'إنشاء النسخة',
      requireConfirm: true,
    );
    if (password == null || !mounted) return;

    setState(() {
      _creating = true;
      _status = null;
    });
    final c = AppScope.of(context);
    final r = await c.backupService.createBackup(password: password);
    if (!mounted) return;
    setState(() => _creating = false);
    if (r is Failure) {
      setState(() => _status = (r as Failure).error.message);
      return;
    }
    final file = (r as Success<File>).value;
    setState(() => _status = 'تم إنشاء النسخة: ${p.basename(file.path)}');
    await _load();
  }

  Future<void> _restoreFromListed(File file) async {
    final password = await _askPassword(
      title: 'استعادة من ${p.basename(file.path)}',
      confirmLabel: 'استعادة',
      requireConfirm: false,
    );
    if (password == null || !mounted) return;
    await _runRestore(file, password);
  }

  Future<void> _pickAndRestore() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['znet', 'json'],
      dialogTitle: 'اختيار ملف النسخة (.znet)',
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final path = result.files.single.path;
    if (path == null) {
      setState(() => _status = 'تعذر قراءة مسار الملف');
      return;
    }
    final password = await _askPassword(
      title: 'استعادة من ${p.basename(path)}',
      confirmLabel: 'استعادة',
      requireConfirm: false,
    );
    if (password == null || !mounted) return;
    await _runRestore(File(path), password);
  }

  Future<void> _runRestore(File file, String password) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final palette = KayanPalette.of(ctx);
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('تأكيد الاستعادة', style: TextStyle(fontFamily: 'Tajawal')),
            content: Text(
              'ستُستبدل الإعدادات وقاعدة البيانات من النسخة المحددة.\n'
              'يُفضَّل إعادة تشغيل التطبيق بعد الاستعادة.\n\n'
              'الملف: ${p.basename(file.path)}',
              style: TextStyle(fontFamily: 'Tajawal', height: 1.5, color: palette.textSecondary),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('استعادة')),
            ],
          ),
        );
      },
    );
    if (ok != true || !mounted) return;

    setState(() {
      _restoring = true;
      _status = null;
    });
    final c = AppScope.of(context);
    final r = await c.backupService.restoreFromFile(
      file,
      password: password,
      closeDatabase: () async {
        await c.database.close();
      },
    );
    if (!mounted) return;
    setState(() => _restoring = false);
    if (r is Failure) {
      setState(() => _status = (r as Failure).error.message);
      return;
    }
    final report = (r as Success).value;
    final dbNote = report.databaseRestored ? ' مع استبدال قاعدة البيانات' : '';
    setState(() => _status =
        'تمت الاستعادة (${report.settingsCount} إعداد$dbNote) — أعد تشغيل التطبيق');
  }

  Future<String?> _askPassword({
    required String title,
    required String confirmLabel,
    required bool requireConfirm,
  }) async {
    final pwdCtrl = TextEditingController();
    final confCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final value = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final palette = KayanPalette.of(ctx);
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text(title, style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w800)),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'كلمة مرور ≥ ${LocalBackupService.minPasswordLength} أحرف · تشفير AES-GCM',
                    style: TextStyle(fontFamily: 'Tajawal', fontSize: 12, color: palette.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: pwdCtrl,
                    obscureText: true,
                    autofocus: true,
                    style: const TextStyle(fontFamily: 'Tajawal'),
                    decoration: const InputDecoration(
                      labelText: 'كلمة المرور',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().length < LocalBackupService.minPasswordLength) {
                        return 'أدخل ${LocalBackupService.minPasswordLength} أحرف على الأقل';
                      }
                      return null;
                    },
                  ),
                  if (requireConfirm) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: confCtrl,
                      obscureText: true,
                      style: const TextStyle(fontFamily: 'Tajawal'),
                      decoration: const InputDecoration(
                        labelText: 'تأكيد كلمة المرور',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if (v != pwdCtrl.text) return 'كلمتا المرور غير متطابقتين';
                        return null;
                      },
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState?.validate() != true) return;
                  Navigator.pop(ctx, pwdCtrl.text.trim());
                },
                child: Text(confirmLabel),
              ),
            ],
          ),
        );
      },
    );
    pwdCtrl.dispose();
    confCtrl.dispose();
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final net = context.netColors;
    final busy = _creating || _restoring;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: palette.appBackground,
        appBar: AppBar(
          backgroundColor: palette.appBackground,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            tooltip: 'رجوع',
            onPressed: () => Navigator.maybePop(context),
            icon: Icon(Icons.arrow_forward_rounded, color: palette.textPrimary),
          ),
          title: const NetAppBarTitle(
            icon: Icons.backup_rounded,
            title: 'النسخ الاحتياطي',
            subtitle: 'إعدادات + قاعدة البيانات · ملف .znet',
          ),
        ),
        body: _loading
            ? const AsyncLoadingView()
            : _error != null
                ? AsyncErrorView(message: _error!, onRetry: _load)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(
                      NetSpacing.lg,
                      NetSpacing.sm,
                      NetSpacing.lg,
                      NetSpacing.xxl,
                    ),
                    children: [
                      NetSurfaceCard(
                        padding: const EdgeInsets.all(NetSpacing.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'نسخة محلية مشفّرة',
                              style: TextStyle(
                                fontFamily: NetTypography.family,
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: palette.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'AES-GCM 256 · PBKDF2 10,000 · بصمة SHA-256\n'
                              'صيغة .znet · كلمة مرور ≥ 4 أحرف\n'
                              'يشمل الإعدادات وملف قاعدة البيانات net.sqlite.\n'
                              'الاستعادة تستبدل البيانات؛ عداد الترخيص يُحمى قدر الإمكان.',
                              style: TextStyle(
                                fontFamily: NetTypography.family,
                                fontSize: 12.5,
                                height: 1.45,
                                color: palette.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: NetSpacing.md),
                      FilledButton.icon(
                        onPressed: busy ? null : _createBackup,
                        icon: _creating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.save_alt_rounded),
                        label: Text(_creating ? 'جاري الإنشاء…' : 'إنشاء نسخة احتياطية'),
                      ),
                      const SizedBox(height: NetSpacing.sm),
                      OutlinedButton.icon(
                        onPressed: busy ? null : _pickAndRestore,
                        icon: _restoring
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: palette.primary),
                              )
                            : const Icon(Icons.folder_open_rounded),
                        label: Text(_restoring ? 'جاري الاستعادة…' : 'استعادة من ملف…'),
                      ),
                      if (_status != null) ...[
                        const SizedBox(height: NetSpacing.md),
                        Text(
                          _status!,
                          style: TextStyle(
                            fontFamily: NetTypography.family,
                            fontSize: 13,
                            color: net.available,
                          ),
                        ),
                      ],
                      const SizedBox(height: NetSpacing.lg),
                      Text(
                        'النسخ المحفوظة على الجهاز',
                        style: TextStyle(
                          fontFamily: NetTypography.family,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: palette.textPrimary,
                        ),
                      ),
                      const SizedBox(height: NetSpacing.sm),
                      if (_backups.isEmpty)
                        AsyncEmptyView(
                          message: 'لا توجد نسخ محفوظة بعد',
                          hint: 'أنشئ نسخة أو اختر ملف .znet للاستعادة',
                          icon: Icons.inventory_2_outlined,
                          compact: true,
                        )
                      else
                        ..._backups.map((f) {
                          final name = p.basename(f.path);
                          final modified = f.statSync().modified.toLocal();
                          final stamp =
                              '${modified.day.toString().padLeft(2, '0')}/'
                              '${modified.month.toString().padLeft(2, '0')}/'
                              '${modified.year} '
                              '${modified.hour.toString().padLeft(2, '0')}:'
                              '${modified.minute.toString().padLeft(2, '0')}';
                          return NetSurfaceCard(
                            margin: const EdgeInsets.only(bottom: NetSpacing.sm),
                            padding: const EdgeInsets.symmetric(
                              horizontal: NetSpacing.md,
                              vertical: NetSpacing.sm,
                            ),
                            onTap: busy ? null : () => _restoreFromListed(f),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: palette.primary.withValues(alpha: 0.12),
                                    borderRadius: NetRadii.smAll,
                                  ),
                                  child: Icon(Icons.lock_rounded, color: palette.primary, size: 20),
                                ),
                                const SizedBox(width: NetSpacing.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontFamily: NetTypography.family,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: palette.textPrimary,
                                        ),
                                      ),
                                      Text(
                                        stamp,
                                        style: TextStyle(
                                          fontFamily: NetTypography.family,
                                          fontSize: 11,
                                          color: palette.textTertiary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.restore_rounded, color: palette.primary, size: 20),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
      ),
    );
  }
}
