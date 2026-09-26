import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;

import '../../core/app_brand.dart';
import '../../core/clock.dart';
import '../../core/id_generator.dart';
import '../../core/result.dart';
import '../entities/setting.dart';
import '../repositories/repositories.dart';

/// Encrypted backup / restore — settings + full SQLite.
///
/// Format `.krt`:
/// - AES-GCM 256 · PBKDF2-HMAC-SHA256 10_000 · SHA-256 fingerprint
/// - Payload: settings snapshot + optional base64 `net.sqlite`
/// - License rows are never written via settings path; DB restore preserves
///   current license table by re-applying license rows after file replace
///   when [reapplyLicenseRows] is provided by the caller.
///
/// Phase 20: the embedded database is validated (SQLite magic + minimum
/// header size) on a temp file before the live DB is replaced. A
/// `.pre-restore` copy of the live file is kept when one exists.
///
/// Legacy `.znet` / `.json` backups stay restorable.
final class LocalBackupService {
  const LocalBackupService({
    required this.settings,
    required this.clock,
    required this.ids,
    required this.backupDirectory,
    this.databaseFile,
    this.legacyDirectories = const <Directory>[],
  });

  final SettingsRepository settings;
  final Clock clock;
  final IdGenerator ids;
  final Directory backupDirectory;

  /// Live app database file (`net.sqlite`). When set, backups embed it.
  final File? databaseFile;

  /// مجلدات النسخ الاحتياطي القديمة — تُقرأ للاستعادة فقط ولا يُكتب فيها.
  final List<Directory> legacyDirectories;

  /// صيغة النسخة الحالية (اسم التطبيق) — والقديمة `znet-backup-v1` ما زالت مقروءة.
  static const formatId = '${AppBrand.latinName}-backup-v1';
  static const legacyFormatIds = <String>['znet-backup-v1'];
  static const fileExtension = '.krt';
  static const restorableExtensions = <String>['.krt', '.znet', '.json'];
  static const pbkdf2Iterations = 10000;
  static const minPasswordLength = 4;
  static const sqliteHeaderPrefix = 'SQLite format 3';
  static const minSqliteHeaderBytes = 100;

  static const List<String> snapshotKeys = [
    SettingKeys.defaultCurrency,
    SettingKeys.reservationMinutes,
    SettingKeys.preferredSimSlot,
    SettingKeys.preferredSendSimSlot,
    SettingKeys.simAutoFailover,
    SettingKeys.smsListenEnabled,
    SettingKeys.networkName,
    SettingKeys.smsAutoProcessingEnabled,
    SettingKeys.processCategoryAmountsOnly,
    SettingKeys.processOldMessagesOnResume,
    SettingKeys.posBalanceRequestsEnabled,
    SettingKeys.dailyOpsSummaryAutoSend,
    SettingKeys.themeMode,
    SettingKeys.autoRetryFailedMessages,
    SettingKeys.retryMaxAttempts,
    SettingKeys.retryBaseDelaySeconds,
    SettingKeys.salafniEnabled,
    SettingKeys.autoPosSettlementEnabled,
    SettingKeys.broadcastMaxAttempts,
    SettingKeys.broadcastRateDelayMs,
    SettingKeys.lowStockThreshold,
    SettingKeys.pendingAttentionAlertEnabled,
    SettingKeys.promotionsCatalog,
    SettingKeys.promotionRewardSmsTemplate,
    SettingKeys.notificationSources,
    SettingKeys.walletExtras,
    SettingKeys.posAccounts,
  ];

  Future<Result<File>> createBackup({
    required String password,
    String? label,
  }) async {
    final pwd = password.trim();
    if (pwd.length < minPasswordLength) {
      return const Failure(
        AppFailure(
          code: 'backup_password_too_short',
          message: 'Password must be at least 4 characters',
        ),
      );
    }
    try {
      if (!await backupDirectory.exists()) {
        await backupDirectory.create(recursive: true);
      }

      final map = <String, String>{};
      for (final key in snapshotKeys) {
        final result = await settings.find(key);
        if (result is Success<AppSetting?> && result.value != null) {
          map[key] = result.value!.value;
        }
      }

      final plain = <String, dynamic>{
        'id': ids.next('backup'),
        'label': label ?? 'manual',
        'createdAt': clock.now().toIso8601String(),
        'schemaVersion': 2,
        'settings': map,
      };

      final db = databaseFile;
      if (db != null && await db.exists()) {
        final bytes = await db.readAsBytes();
        plain['database'] = {
          'name': p.basename(db.path),
          'encoding': 'base64',
          'size': bytes.length,
          'bytes': base64Encode(bytes),
        };
      }

      final plainBytes = utf8.encode(
        const JsonEncoder.withIndent('  ').convert(plain),
      );

      final fingerprint = await Sha256().hash(plainBytes);
      final fingerprintHex = _toHex(fingerprint.bytes);

      final salt = _randomBytes(16);
      final secretKey = await _deriveKey(pwd, salt);
      final algorithm = AesGcm.with256bits();
      final secretBox = await algorithm.encrypt(
        plainBytes,
        secretKey: secretKey,
      );

      final envelope = <String, dynamic>{
        'format': formatId,
        'kdf': 'PBKDF2-HMAC-SHA256',
        'iterations': pbkdf2Iterations,
        'cipher': 'AES-256-GCM',
        'salt': base64Encode(salt),
        'nonce': base64Encode(secretBox.nonce),
        'ciphertext': base64Encode(secretBox.cipherText),
        'mac': base64Encode(secretBox.mac.bytes),
        'fingerprint': fingerprintHex,
        'createdAt': clock.now().toIso8601String(),
        'label': label ?? 'manual',
        'includesDatabase': plain.containsKey('database'),
      };

      final fileName =
          '${AppBrand.latinName}-backup-${clock.now().millisecondsSinceEpoch}$fileExtension';
      final file = File(p.join(backupDirectory.path, fileName));
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(envelope),
        flush: true,
      );
      return Success(file);
    } catch (e) {
      return Failure(
        AppFailure(code: 'backup_failed', message: e.toString()),
      );
    }
  }

  /// Restores settings and optionally the SQLite file.
  ///
  /// When the backup embeds a database, [closeDatabase] must close the open
  /// Drift connection first; [onDatabaseRestored] can reopen / restart.
  /// [preserveLicenseRows] is raw INSERT-ready maps applied after DB write
  /// so license counters are not lost (caller supplies current rows).
  Future<Result<BackupRestoreReport>> restoreFromFile(
    File file, {
    String? password,
    Future<void> Function()? closeDatabase,
    Future<void> Function()? onDatabaseRestored,
    List<Map<String, dynamic>>? preserveLicenseRows,
    Future<void> Function(List<Map<String, dynamic>> rows)? reapplyLicenseRows,
  }) async {
    try {
      if (!await file.exists()) {
        return const Failure(
          AppFailure(code: 'backup_not_found', message: 'Backup file missing'),
        );
      }
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;

      Map<String, dynamic> plainPayload;
      final format = decoded['format'];
      if (format == formatId || legacyFormatIds.contains(format)) {
        final pwd = (password ?? '').trim();
        if (pwd.length < minPasswordLength) {
          return const Failure(
            AppFailure(
              code: 'backup_password_required',
              message: 'Password required for encrypted backup',
            ),
          );
        }
        final plain = await _decryptEnvelope(decoded, pwd);
        if (plain is Failure<Map<String, dynamic>>) {
          return Failure(plain.error);
        }
        plainPayload = (plain as Success<Map<String, dynamic>>).value;
      } else {
        plainPayload = decoded;
      }

      final settingsMap = Map<String, dynamic>.from(
        plainPayload['settings'] as Map? ?? {},
      );
      for (final entry in settingsMap.entries) {
        final key = entry.key;
        if (key.toLowerCase().contains('license')) continue;
        final save = await settings.save(
          AppSetting(
            key: key,
            value: entry.value.toString(),
            updatedAt: clock.now(),
          ),
        );
        if (save is Failure<void>) return Failure(save.error);
      }

      var restoredDb = false;
      final dbSection = plainPayload['database'];
      final target = databaseFile;
      if (dbSection is Map && target != null) {
        final b64 = dbSection['bytes'] as String?;
        if (b64 != null && b64.isNotEmpty) {
          final bytes = base64Decode(b64);
          if (!_isSqliteDatabase(bytes)) {
            return const Failure(
              AppFailure(
                code: 'backup_database_invalid',
                message: 'Backup database is not a valid SQLite file',
              ),
            );
          }
          if (closeDatabase != null) {
            await closeDatabase();
          }
          final parent = target.parent;
          if (!await parent.exists()) {
            await parent.create(recursive: true);
          }
          final tmp = File('${target.path}.restore-tmp');
          await tmp.writeAsBytes(bytes, flush: true);
          final written = await tmp.readAsBytes();
          if (!_isSqliteDatabase(written)) {
            await tmp.delete();
            return const Failure(
              AppFailure(
                code: 'backup_database_invalid',
                message: 'Temp restore file failed SQLite validation',
              ),
            );
          }
          if (await target.exists()) {
            final safety = File('${target.path}.pre-restore');
            if (await safety.exists()) {
              await safety.delete();
            }
            await target.copy(safety.path);
            await target.delete();
          }
          await tmp.rename(target.path);
          restoredDb = true;
          final licenseRows =
              preserveLicenseRows ?? const <Map<String, dynamic>>[];
          if (licenseRows.isNotEmpty && reapplyLicenseRows != null) {
            await reapplyLicenseRows(licenseRows);
          }
          if (onDatabaseRestored != null) {
            await onDatabaseRestored();
          }
        }
      }

      return Success(
        BackupRestoreReport(
          settingsCount: settingsMap.length,
          databaseRestored: restoredDb,
          licenseRowsPreserved: preserveLicenseRows?.length ?? 0,
        ),
      );
    } catch (e) {
      return Failure(
        AppFailure(code: 'restore_failed', message: e.toString()),
      );
    }
  }

  Future<Result<List<File>>> listBackups() async {
    try {
      final files = <File>[];
      for (final directory in [backupDirectory, ...legacyDirectories]) {
        if (!await directory.exists()) continue;
        files.addAll(
          directory
              .listSync()
              .whereType<File>()
              .where(
                (f) => restorableExtensions.any(f.path.endsWith),
              ),
        );
      }
      files.sort((a, b) => b.path.compareTo(a.path));
      return Success(files);
    } catch (e) {
      return Failure(
        AppFailure(code: 'list_backups_failed', message: e.toString()),
      );
    }
  }

  /// SQLite files start with `SQLite format 3\0` and a 100-byte header.
  static bool isSqliteDatabase(List<int> bytes) =>
      LocalBackupService._isSqliteDatabase(bytes);

  static bool _isSqliteDatabase(List<int> bytes) {
    if (bytes.length < minSqliteHeaderBytes) return false;
    final prefix = utf8.encode(sqliteHeaderPrefix);
    if (bytes.length < prefix.length + 1) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) return false;
    }
    return bytes[prefix.length] == 0;
  }

  Future<Result<Map<String, dynamic>>> _decryptEnvelope(
    Map<String, dynamic> envelope,
    String password,
  ) async {
    try {
      final iterations = envelope['iterations'] as int? ?? pbkdf2Iterations;
      final salt = base64Decode(envelope['salt'] as String);
      final nonce = base64Decode(envelope['nonce'] as String);
      final cipherText = base64Decode(envelope['ciphertext'] as String);
      final macBytes = base64Decode(envelope['mac'] as String);
      final expectedFp = envelope['fingerprint'] as String?;

      final secretKey =
          await _deriveKey(password, salt, iterations: iterations);
      final algorithm = AesGcm.with256bits();
      final clear = await algorithm.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
        secretKey: secretKey,
      );

      if (expectedFp != null) {
        final hash = await Sha256().hash(clear);
        if (_toHex(hash.bytes) != expectedFp) {
          return const Failure(
            AppFailure(
              code: 'backup_fingerprint_mismatch',
              message: 'Backup integrity check failed',
            ),
          );
        }
      }

      final decoded = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
      return Success(decoded);
    } on SecretBoxAuthenticationError {
      return const Failure(
        AppFailure(
          code: 'backup_wrong_password',
          message: 'Wrong password or corrupted backup',
        ),
      );
    } catch (e) {
      return Failure(
        AppFailure(code: 'backup_decrypt_failed', message: e.toString()),
      );
    }
  }

  Future<SecretKey> _deriveKey(
    String password,
    List<int> salt, {
    int iterations = pbkdf2Iterations,
  }) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    return pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
  }

  List<int> _randomBytes(int length) {
    final rnd = Random.secure();
    return List<int>.generate(length, (_) => rnd.nextInt(256));
  }

  String _toHex(List<int> bytes) {
    final b = StringBuffer();
    for (final v in bytes) {
      b.write(v.toRadixString(16).padLeft(2, '0'));
    }
    return b.toString();
  }
}

final class BackupRestoreReport {
  const BackupRestoreReport({
    required this.settingsCount,
    required this.databaseRestored,
    required this.licenseRowsPreserved,
  });

  final int settingsCount;
  final bool databaseRestored;
  final int licenseRowsPreserved;
}
