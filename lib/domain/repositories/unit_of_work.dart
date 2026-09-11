import '../../core/result.dart';

abstract interface class UnitOfWork {
  Future<Result<T>> run<T>(Future<Result<T>> Function() action);
}
