library local_repositories;

import 'package:drift/drift.dart';

import '../../core/result.dart';
import '../../domain/entities/audit.dart' as domain;
import '../../domain/entities/advance.dart' as domain;
import '../../domain/entities/card.dart' as domain;
import '../../domain/entities/customer.dart' as domain;
import '../../domain/entities/license.dart' as domain;
import '../../domain/entities/message.dart' as domain;
import '../../domain/entities/money.dart';
import '../../domain/entities/setting.dart' as domain;
import '../../domain/entities/transaction.dart' as domain;
import '../../domain/entities/wallet.dart' as domain;
import '../../domain/phone_normalizer.dart';
import '../../domain/repositories/repositories.dart';
import '../database/app_database.dart';

part 'local_customer_repository.dart';
part 'local_wallet_repository.dart';
part 'local_point_of_sale_repository.dart';
part 'local_card_category_repository.dart';
part 'local_card_repository.dart';
part 'local_transaction_repository.dart';
part 'local_sale_repository.dart';
part 'local_message_repository.dart';
part 'local_license_repository.dart';
part 'local_settings_repository.dart';
part 'local_audit_log_repository.dart';
part 'local_transfer_template_repository.dart';
part 'local_advance_repository.dart';
part 'local_repo_helpers.dart';
