import '../../core/result.dart';
import '../../domain/repositories/unit_of_work.dart';
import 'app_database.dart';

final class DriftUnitOfWork implements UnitOfWork {
  const DriftUnitOfWork(this.database);

  final AppDatabase database;

  @override
  Future<Result<T>> run<T>(Future<Result<T>> Function() action) async {
    try {
      return await database.transaction(() async {
        final result = await action();
        if (result is Failure<T>) {
          throw _ResultRollback(result.error);
        }
        return result;
      });
    } on _ResultRollback catch (error) {
      return Failure(error.failure);
    } catch (error) {
      return Failure(
        AppFailure(code: 'transaction_failed', message: error.toString()),
      );
    }
  }
}

final class _ResultRollback implements Exception {
  const _ResultRollback(this.failure);

  final AppFailure failure;
}
