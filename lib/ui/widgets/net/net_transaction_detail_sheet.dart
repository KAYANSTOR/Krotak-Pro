import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/result.dart';
import '../../../domain/entities/customer.dart';
import '../../../domain/entities/transaction.dart';
import '../../app_scope.dart';
import '../../labels/net_labels.dart';
import '../../theme/kayan_palette.dart';
import '../../theme/net_semantic_colors.dart';
import '../../theme/net_tokens.dart';
import '../async_views.dart';
import 'net_sheet.dart';

String buildTransactionReceiptText({
  required String amountText,
  required String currencyLabel,
  required String reference,
  required String typeLabel,
  required String statusLabel,
  required String dateLabel,
  required String beneficiaryLabel,
}) {
  return <String>[
    'NET — بيانات الحركة',
    'المبلغ: $amountText $currencyLabel',
    'رقم مرجع العملية: $reference',
    'العملية: $typeLabel',
    'الحالة: $statusLabel',
    'تاريخ العملية: $dateLabel',
    'المستفيد: ${beneficiaryLabel.replaceAll('\n', ' ')}',
  ].join('\n');
}
