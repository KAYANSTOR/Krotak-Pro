/// حملة ترويجية تراكمية — مطابق سطح فيديو Z Net.
///
/// التخزين محلي عبر إعداد JSON (`SettingKeys.promotionsCatalog`) حتى لا
/// نكسر Drift codegen؛ المنطق Domain حقيقي وليس واجهة فقط.
enum PromotionStatus { active, disabled }

final class Promotion {
  const Promotion({
    required this.id,
    required this.title,
    required this.status,
    required this.thresholdMinorUnits,
    required this.currencyCode,
    required this.rewardCategoryId,
    required this.createdAt,
    this.notes,
  });

  final String id;
  final String title;
  final PromotionStatus status;

  /// مبلغ التراكم المطلوب قبل صرف المكافأة (وحدات صغرى).
  final int thresholdMinorUnits;
  final String currencyCode;

  /// فئة الكروت التي تُصرف كمكافأة عند بلوغ العتبة.
  final String rewardCategoryId;
  final DateTime createdAt;
  final String? notes;

  bool get isActive => status == PromotionStatus.active;

  Promotion copyWith({
    String? title,
    PromotionStatus? status,
    int? thresholdMinorUnits,
    String? currencyCode,
    String? rewardCategoryId,
    String? notes,
  }) {
    return Promotion(
      id: id,
      title: title ?? this.title,
      status: status ?? this.status,
      thresholdMinorUnits: thresholdMinorUnits ?? this.thresholdMinorUnits,
      currencyCode: currencyCode ?? this.currencyCode,
      rewardCategoryId: rewardCategoryId ?? this.rewardCategoryId,
      createdAt: createdAt,
      notes: notes ?? this.notes,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'status': status.name,
        'thresholdMinorUnits': thresholdMinorUnits,
        'currencyCode': currencyCode,
        'rewardCategoryId': rewardCategoryId,
        'createdAt': createdAt.toIso8601String(),
        'notes': notes,
      };

  static Promotion fromJson(Map<String, dynamic> json) {
    return Promotion(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      status: PromotionStatus.values.byName(
        json['status'] as String? ?? PromotionStatus.active.name,
      ),
      thresholdMinorUnits: (json['thresholdMinorUnits'] as num?)?.toInt() ?? 0,
      currencyCode: json['currencyCode'] as String? ?? 'YER',
      rewardCategoryId: json['rewardCategoryId'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      notes: json['notes'] as String?,
    );
  }
}
