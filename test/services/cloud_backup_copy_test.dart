import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/domain/services/cloud_backup_copy.dart';

void main() {
  test('keeps encrypted package name', () {
    expect(
      CloudBackupCopy.suggestedFileName('Krotak-backup-20261001.krt'),
      'Krotak-backup-20261001.krt',
    );
  });

  test('strips directories and rejects empty names safely', () {
    expect(
      CloudBackupCopy.suggestedFileName(r'backups\Krotak-backup.krt'),
      'Krotak-backup.krt',
    );
    expect(CloudBackupCopy.suggestedFileName('   '), 'Krotak-backup.krt');
  });

  test('only an existing .krt is an encrypted package', () {
    expect(CloudBackupCopy.isEncryptedPackage('Krotak-backup.krt'), isTrue);
    expect(CloudBackupCopy.isEncryptedPackage('notes.txt'), isFalse);
  });
}
