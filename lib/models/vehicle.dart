enum QueueStatus { inQueue, ready, delivered }

QueueStatus queueStatusFromString(String value) {
  return QueueStatus.values.firstWhere(
    (e) => e.name == value,
    orElse: () => QueueStatus.inQueue,
  );
}

class QueueEntry {
  final int? id;
  final String plate;
  final String? phone;
  final QueueStatus status;
  final DateTime createdAt;
  final DateTime? notifiedAt;

  const QueueEntry({
    this.id,
    required this.plate,
    this.phone,
    this.status = QueueStatus.inQueue,
    required this.createdAt,
    this.notifiedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'plate': plate,
      'phone': phone,
      'status': status.name,
      'createdAt': createdAt.toIso8601String(),
      'notifiedAt': notifiedAt?.toIso8601String(),
    };
  }

  factory QueueEntry.fromMap(Map<String, dynamic> map) {
    return QueueEntry(
      id: map['id'] as int?,
      plate: map['plate'] as String,
      phone: map['phone'] as String?,
      status: queueStatusFromString(map['status'] as String),
      createdAt: DateTime.parse(map['createdAt'] as String),
      notifiedAt: map['notifiedAt'] != null
          ? DateTime.parse(map['notifiedAt'] as String)
          : null,
    );
  }
}

class Customer {
  final String plate;
  final String phone;
  final DateTime createdAt;

  const Customer({
    required this.plate,
    required this.phone,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'plate': plate,
        'phone': phone,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Customer.fromMap(Map<String, dynamic> map) => Customer(
        plate: map['plate'] as String,
        phone: map['phone'] as String,
        createdAt: DateTime.parse(map['createdAt'] as String),
      );
}

/// Rehber ekranı için: bir müşterinin kaç kez geldiğini ve en son ne zaman
/// geldiğini queue_entries geçmişinden türetilmiş haliyle taşır.
class CustomerVisitInfo {
  final Customer customer;
  final int visitCount;
  final DateTime lastVisit;

  const CustomerVisitInfo({
    required this.customer,
    required this.visitCount,
    required this.lastVisit,
  });
}
