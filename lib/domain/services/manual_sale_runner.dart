import '../../core/result.dart';
import '../entities/audit.dart';
import '../entities/card.dart';
import '../entities/customer.dart';
import '../entities/money.dart';
import '../entities/transaction.dart';
import 'local_sale_service.dart';
import 'outbound_template_renderer.dart';
import 'services.dart';

/// Domain runner for operator manual sales.
///
/// - cash: deposit then sale
/// - credit / pos: sale only (debt)
/// - gift: sale only — **no customer ledger entry at all** (a gift is never
///   recorded as customer debt); the card is consumed and the sale is audited
///   as a gift so it shows up in the offers/gifts trail instead of the account.
final class ManualSaleRunner {
  const ManualSaleRunner(this.host);

  final LocalSaleService host;

  Future<Result<Sale>> run({
    required String phone,
    required String displayName,
    required Money amount,
    required ManualSaleMethod method,
    String? operationId,
  }) {
    final phoneTrim = phone.trim();
    final nameTrim = displayName.trim();
    if (phoneTrim.isEmpty) {
      return Future.value(
        const Failure(
          AppFailure(code: 'invalid_phone', message: 'الرجاء إدخال رقم الجوال'),
        ),
      );
    }
    if (amount.minorUnits <= 0) {
      return Future.value(
        const Failure(
          AppFailure(code: 'invalid_amount', message: 'الرجاء إدخال المبلغ'),
        ),
      );
    }

    final stableOperationId = operationId?.trim();
    if (stableOperationId != null && stableOperationId.isEmpty) {
      return Future.value(
        const Failure(
          AppFailure(
            code: 'invalid_operation_id',
            message: 'Sale operation id must not be empty',
          ),
        ),
      );
    }

    return host.unitOfWork.run(() async {
      if (stableOperationId != null) {
        final existingSale = await host.sales.findById(stableOperationId);
        if (existingSale is Failure<Sale?>) return Failure(existingSale.error);
        final existing = (existingSale as Success<Sale?>).value;
        if (existing != null) return Success(existing);
      }

      final foundByPhone = await host.customers.findByIdentifier(phoneTrim);
      if (foundByPhone is Failure<Customer?>) return Failure(foundByPhone.error);
      Customer? customer = (foundByPhone as Success<Customer?>).value;

      if (customer == null) {
        final name = nameTrim.isNotEmpty ? nameTrim : phoneTrim;
        final nowCreate = host.clock.now();
        customer = Customer(
          id: host.ids.next('customer'),
          displayName: name,
          status: CustomerStatus.active,
          createdAt: nowCreate,
          updatedAt: nowCreate,
        );
        final savedCustomer = await host.customers.save(customer);
        if (savedCustomer is Failure<void>) return Failure(savedCustomer.error);
        final savedId = await host.customers.saveIdentifier(
          CustomerIdentifier(
            id: host.ids.next('identifier'),
            customerId: customer.id,
            type: CustomerIdentifierType.phoneNumber,
            value: phoneTrim,
            isPrimary: true,
          ),
        );
        if (savedId is Failure<void>) return Failure(savedId.error);
      } else if (customer.status != CustomerStatus.active) {
        return const Failure(
          AppFailure(
            code: 'customer_not_sellable',
            message: 'Customer is not allowed to buy',
          ),
        );
      } else if (nameTrim.isNotEmpty && customer.displayName.trim() != nameTrim) {
        final updated = customer.copyWith(
          displayName: nameTrim,
          updatedAt: host.clock.now(),
        );
        final saved = await host.customers.save(updated);
        if (saved is Failure<void>) return Failure(saved.error);
        customer = updated;
      }

      final allCats = await host.categories.listAll();
      if (allCats is Failure<List<CardCategory>>) return Failure(allCats.error);
      final matches = (allCats as Success<List<CardCategory>>)
          .value
          .where(
            (c) =>
                c.isActive &&
                c.faceValue.currencyCode == amount.currencyCode &&
                c.faceValue.minorUnits == amount.minorUnits,
          )
          .toList(growable: false);
      if (matches.isEmpty) {
        return const Failure(
          AppFailure(
            code: 'category_not_found_for_amount',
            message: 'لا توجد فئة كرت مطابقة لهذا المبلغ',
          ),
        );
      }
      final category = matches.first;

      final now = host.clock.now();
      final saleId = stableOperationId ?? host.ids.next('sale');

      // Cash only: pre-deposit so net ledger is neutral after sale.
      if (method == ManualSaleMethod.cash) {
        final depositRef = stableOperationId == null
            ? 'manual-cash:$saleId'
            : 'manual-cash:$stableOperationId';
        final existingDeposit =
            await host.transactions.findByReference(depositRef);
        if (existingDeposit is Failure<Transaction?>) {
          return Failure(existingDeposit.error);
        }
        if ((existingDeposit as Success<Transaction?>).value == null) {
          final depositTxn = Transaction(
            id: host.ids.next('txn'),
            type: TransactionType.deposit,
            status: TransactionStatus.completed,
            amount: amount,
            createdAt: now,
            customerId: customer.id,
            reference: depositRef,
          );
          final deposited = await host.transactions.append(depositTxn);
          if (deposited is Failure<void>) return Failure(deposited.error);
        }
      }

      final reserved = await host.inventory.reserveAvailableCard(
        categoryId: category.id,
        reservationId: host.ids.next('reservation'),
        now: now,
        expiresAt: now.add(host.reservationTtl),
      );
      if (reserved is Failure<Card>) return Failure(reserved.error);
      final card = (reserved as Success<Card>).value;

      final sale = Sale(
        id: saleId,
        customerId: customer.id,
        cardId: card.id,
        amount: category.faceValue,
        status: TransactionStatus.completed,
        createdAt: now,
      );
      final marked = await host.cards.markSold(card.id, sale.id);
      if (marked is Failure<void>) return Failure(marked.error);

      // بطاقة الهدية لا تُسجَّل على حساب العميل — لا حركة مدينة في دفتره.
      if (method != ManualSaleMethod.gift) {
        final saleTxn = Transaction(
          id: host.ids.next('txn'),
          type: TransactionType.sale,
          status: TransactionStatus.completed,
          amount: category.faceValue,
          createdAt: now,
          customerId: customer.id,
          reference: stableOperationId == null
              ? 'manual:${sale.id}'
              : 'manual-op:$stableOperationId',
        );
        final appended = await host.transactions.append(saleTxn);
        if (appended is Failure<void>) return Failure(appended.error);
      }

      final savedSale = await host.sales.save(sale);
      if (savedSale is Failure<void>) return Failure(savedSale.error);

      final methodLabel = method.name;
      final audited = await host.auditLogs.append(
        AuditLog(
          id: host.ids.next('audit'),
          entityType: 'sale',
          entityId: sale.id,
          action: method == ManualSaleMethod.gift
              ? 'gift_completed'
              : 'manual_completed',
          payloadJson:
              '{"cardId":"${card.id}","customerId":"${customer.id}","phone":"$phoneTrim","method":"$methodLabel","operationId":"${stableOperationId ?? ''}"}',
          occurredAt: now,
        ),
      );
      if (audited is Failure<void>) return Failure(audited.error);

      // Deliver voucher SMS to customer phone (same body as auto-transfer path).
      final sender = host.messageSender;
      if (sender != null && host.settings != null) {
        final rendered = await OutboundTemplateRenderer(
          settings: host.settings!,
        ).renderVoucherDelivery(
          serialNumber: card.serialNumber,
          secretCode: card.secretCode,
        );
        if (rendered is Failure<String>) {
          await host.auditLogs.append(
            AuditLog(
              id: host.ids.next('audit'),
              entityType: 'sale',
              entityId: sale.id,
              action: 'sms_template_render_failed',
              payloadJson: '{"error":"${rendered.error.code}"}',
              occurredAt: host.clock.now(),
            ),
          );
          // Sale already committed — do not roll back; delivery worker can retry
          // only for transfer path; manual path records failure in audit.
          return Success(sale);
        }
        final body = (rendered as Success<String>).value;
        final sent = await sender.send(destination: phoneTrim, body: body);
        await host.auditLogs.append(
          AuditLog(
            id: host.ids.next('audit'),
            entityType: 'sale',
            entityId: sale.id,
            action: sent is Success<void>
                ? 'manual_sale_sms_sent'
                : 'manual_sale_sms_failed',
            occurredAt: host.clock.now(),
            payloadJson:
                '{"phone":"$phoneTrim","cardId":"${card.id}","code":"${sent is Failure<void> ? sent.error.code : 'ok'}"}',
          ),
        );
        // Sale stays committed even if SMS fails — delivery worker / resend can retry.
      }

      return Success(sale);
    });
  }
}
