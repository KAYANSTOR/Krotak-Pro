import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/core/clock.dart';
import 'package:net_app/core/id_generator.dart';
import 'package:net_app/core/result.dart';
import 'package:net_app/data/database/app_database.dart' hide Customer;
import 'package:net_app/data/database/drift_unit_of_work.dart';
import 'package:net_app/data/repositories/local_broadcast_repository.dart';
import 'package:net_app/data/repositories/local_repositories.dart';
import 'package:net_app/domain/entities/broadcast.dart';
import 'package:net_app/domain/entities/customer.dart';
import 'package:net_app/domain/services/local_broadcast_service.dart';
import 'package:net_app/domain/services/local_customer_service.dart';
import 'package:net_app/domain/services/services.dart';

final class _RecordingSender implements MessageSender {
  final sent = <(String, String)>[];
  final Set<String> failFor;

  _RecordingSender({Set<String>? failFor}) : failFor = failFor ?? <String>{};

  @override
  Future<Result<void>> send({required String destination, required String body}) async {
    if (failFor.contains(destination)) {
      return const Failure(AppFailure(code: 'sms_send_failed', message: 'denied'));
    }
    sent.add((destination, body));
    return const Success(null);
  }
}

// The remainder of the existing broadcast tests is intentionally kept as-is.
