enum BroadcastJobStatus {
  draft,
  confirmed,
  running,
  paused,
  completed,
  partiallyFailed,
  failed,
  cancelled,
}

enum BroadcastRecipientStatus { pending, sent, skipped, failed }

/// نطاق المستهدفين في الرسالة الجماعية.
enum BroadcastAudience {
  /// كل العملاء النشطين.
  allCustomers,

  /// العملاء الذين عليهم دين فقط.
  debtorCustomers,

  /// تحديد يدوي لعملاء بعينهم.
  selectedCustomers,

  /// حسابات نقاط البيع (على رقم الإشعار المحفوظ لكل نقطة).
  posAccounts,
}

final class BroadcastRecipient {
  const BroadcastRecipient({
    required this.customerId,
    required this.phone,
    required this.displayName,
    required this.status,
    this.errorCode,
    this.attempts = 0,
    this.sentAt,
  });

  final String customerId;
  final String phone;
  final String displayName;
  final BroadcastRecipientStatus status;
  final String? errorCode;
  final int attempts;
  final DateTime? sentAt;

  BroadcastRecipient copyWith({
    BroadcastRecipientStatus? status,
    String? errorCode,
    int? attempts,
    DateTime? sentAt,
    bool clearError = false,
  }) {
    return BroadcastRecipient(
      customerId: customerId,
      phone: phone,
      displayName: displayName,
      status: status ?? this.status,
      errorCode: clearError ? null : (errorCode ?? this.errorCode),
      attempts: attempts ?? this.attempts,
      sentAt: sentAt ?? this.sentAt,
    );
  }

  Map<String, Object?> toJson() => {
        'customerId': customerId,
        'phone': phone,
        'displayName': displayName,
        'status': status.name,
        'errorCode': errorCode,
        'attempts': attempts,
        'sentAt': sentAt?.toIso8601String(),
      };

  static BroadcastRecipient fromJson(Map<String, dynamic> json) {
    return BroadcastRecipient(
      customerId: json['customerId'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      status: BroadcastRecipientStatus.values.byName(
        json['status'] as String? ?? 'pending',
      ),
      errorCode: json['errorCode'] as String?,
      attempts: json['attempts'] as int? ?? 0,
      sentAt: json['sentAt'] == null ? null : DateTime.tryParse(json['sentAt'] as String),
    );
  }
}

final class BroadcastJob {
  const BroadcastJob({
    required this.id,
    required this.body,
    required this.status,
    required this.createdAt,
    required this.recipients,
    this.confirmedAt,
    this.completedAt,
    this.fingerprint,
  });

  final String id;
  final String body;
  final BroadcastJobStatus status;
  final DateTime createdAt;
  final DateTime? confirmedAt;
  final DateTime? completedAt;
  final String? fingerprint;
  final List<BroadcastRecipient> recipients;

  int get total => recipients.length;
  int get sentCount => recipients.where((r) => r.status == BroadcastRecipientStatus.sent).length;
  int get failedCount => recipients.where((r) => r.status == BroadcastRecipientStatus.failed).length;
  int get skippedCount => recipients.where((r) => r.status == BroadcastRecipientStatus.skipped).length;
  int get pendingCount => recipients.where((r) => r.status == BroadcastRecipientStatus.pending).length;

  BroadcastJob copyWith({
    String? body,
    BroadcastJobStatus? status,
    DateTime? confirmedAt,
    DateTime? completedAt,
    String? fingerprint,
    List<BroadcastRecipient>? recipients,
  }) {
    return BroadcastJob(
      id: id,
      body: body ?? this.body,
      status: status ?? this.status,
      createdAt: createdAt,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      completedAt: completedAt ?? this.completedAt,
      fingerprint: fingerprint ?? this.fingerprint,
      recipients: recipients ?? this.recipients,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'body': body,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'confirmedAt': confirmedAt?.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'fingerprint': fingerprint,
        'recipients': recipients.map((r) => r.toJson()).toList(growable: false),
      };

  static BroadcastJob fromJson(Map<String, dynamic> json) {
    final rawRecipients = json['recipients'] as List<dynamic>? ?? const [];
    return BroadcastJob(
      id: json['id'] as String? ?? '',
      body: json['body'] as String? ?? '',
      status: BroadcastJobStatus.values.byName(json['status'] as String? ?? 'draft'),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      confirmedAt: json['confirmedAt'] == null ? null : DateTime.tryParse(json['confirmedAt'] as String),
      completedAt: json['completedAt'] == null ? null : DateTime.tryParse(json['completedAt'] as String),
      fingerprint: json['fingerprint'] as String?,
      recipients: rawRecipients
          .whereType<Map>()
          .map((row) => BroadcastRecipient.fromJson(Map<String, dynamic>.from(row)))
          .toList(),
    );
  }
}

final class BroadcastPreview {
  const BroadcastPreview({
    required this.body,
    required this.eligible,
    required this.excludedBlacklisted,
    required this.excludedInvalidPhone,
    required this.excludedInactive,
  });

  final String body;
  final List<BroadcastRecipient> eligible;
  final int excludedBlacklisted;
  final int excludedInvalidPhone;
  final int excludedInactive;

  int get eligibleCount => eligible.length;
}

final class BroadcastProgress {
  const BroadcastProgress({
    required this.jobId,
    required this.done,
    required this.total,
    required this.status,
  });

  final String jobId;
  final int done;
  final int total;
  final BroadcastJobStatus status;
}
