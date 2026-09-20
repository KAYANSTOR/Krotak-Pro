import '../../core/result.dart';
import '../entities/card.dart';
import '../repositories/repositories.dart';
import '../repositories/unit_of_work.dart';
import 'services.dart';

final class LocalCardInventoryService implements CardInventoryService {
  const LocalCardInventoryService({
    required this.categories,
    required this.cards,
    required this.unitOfWork,
  });

  final CardCategoryRepository categories;
  final CardRepository cards;
  final UnitOfWork unitOfWork;

  @override
  Future<Result<Card>> reserveAvailableCard({
    required String categoryId,
    required String reservationId,
    required DateTime now,
    required DateTime expiresAt,
  }) {
    return unitOfWork.run(() async {
      final atomic = await cards.reserveFirstAvailable(
        categoryId: categoryId,
        reservationId: reservationId,
        reservedAt: now,
        expiresAt: expiresAt,
      );
      if (atomic is Success<Card>) return atomic;
      if (atomic is Failure<Card> &&
          atomic.error.code != 'card_unavailable' &&
          atomic.error.code != 'not_implemented') {
        return atomic;
      }

      final foundCategory = await categories.findById(categoryId);
      if (foundCategory is Failure<CardCategory?>) {
        return Failure(foundCategory.error);
      }
      final category = (foundCategory as Success<CardCategory?>).value;
      if (category == null) {
        return const Failure(
          AppFailure(code: 'category_not_found', message: 'Category was not found'),
        );
      }
      if (!category.isActive) {
        return const Failure(
          AppFailure(code: 'category_inactive', message: 'Category is not active'),
        );
      }

      final expired = await cards.expireReservations(now);
      if (expired is Failure<int>) return Failure(expired.error);

      final available = await cards.findAvailableByCategory(categoryId);
      if (available is Failure<List<Card>>) return Failure(available.error);
      final stock = (available as Success<List<Card>>).value;
      if (stock.isEmpty) {
        return const Failure(
          AppFailure(code: 'card_unavailable', message: 'No available card in category'),
        );
      }

      final selected = stock.first;
      final reserved = await cards.reserve(
        selected.id,
        CardReservation(
          reservationId: reservationId,
          reservedAt: now,
          expiresAt: expiresAt,
        ),
      );
      if (reserved is Failure<void>) return Failure(reserved.error);

      final reloaded = await cards.findById(selected.id);
      if (reloaded is Failure<Card?>) return Failure(reloaded.error);
      final card = (reloaded as Success<Card?>).value;
      if (card == null) {
        return const Failure(
          AppFailure(code: 'card_not_found', message: 'Card was not found'),
        );
      }
      return Success(card);
    });
  }

  @override
  Future<Result<void>> releaseReservation({
    required String cardId,
    required String reservationId,
  }) {
    return cards.releaseReservation(cardId, reservationId);
  }
}
