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

  /// Bu araç için belirlenen yıkama ücreti. Her araç farklı fiyata
  /// yıkanabildiği için kuyruktaki her kayda ayrı ayrı atanır (bkz.
  /// home_screen.dart'taki "Ücret Belirle" butonu). Null ise henüz fiyat
  /// girilmemiştir.
  final double? price;

  /// "Araç Bekleme Süresi Uyarısı" için: bu kayıt için uzun bekleme
  /// bildirimi daha önce gönderildiyse zamanı burada tutulur. Null ise
  /// henüz gönderilmemiştir. Aynı araç için bildirimin tekrar tekrar
  /// atılmasını engeller (bkz. HomeScreen._checkWaitTimes).
  final DateTime? waitWarnedAt;

  const QueueEntry({
    this.id,
    required this.plate,
    this.phone,
    this.status = QueueStatus.inQueue,
    required this.createdAt,
    this.notifiedAt,
    this.price,
    this.waitWarnedAt,
  });

  QueueEntry copyWith({
    int? id,
    String? plate,
    String? phone,
    QueueStatus? status,
    DateTime? createdAt,
    DateTime? notifiedAt,
    double? price,
    DateTime? waitWarnedAt,
  }) {
    return QueueEntry(
      id: id ?? this.id,
      plate: plate ?? this.plate,
      phone: phone ?? this.phone,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      notifiedAt: notifiedAt ?? this.notifiedAt,
      price: price ?? this.price,
      waitWarnedAt: waitWarnedAt ?? this.waitWarnedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'plate': plate,
      'phone': phone,
      'status': status.name,
      'createdAt': createdAt.toIso8601String(),
      'notifiedAt': notifiedAt?.toIso8601String(),
      'price': price,
      'waitWarnedAt': waitWarnedAt?.toIso8601String(),
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
      price: (map['price'] as num?)?.toDouble(),
      waitWarnedAt: map['waitWarnedAt'] != null
          ? DateTime.parse(map['waitWarnedAt'] as String)
          : null,
    );
  }
}

class Customer {
  final String plate;
  final String phone;
  final DateTime createdAt;

  /// Opsiyonel müşteri adı. Rehber ekranından "Düzenle" ile girilebilir;
  /// boşsa rehberde sadece plaka gösterilir.
  final String? name;

  const Customer({
    required this.plate,
    required this.phone,
    required this.createdAt,
    this.name,
  });

  Customer copyWith({
    String? plate,
    String? phone,
    DateTime? createdAt,
    String? name,
    bool clearName = false,
  }) {
    return Customer(
      plate: plate ?? this.plate,
      phone: phone ?? this.phone,
      createdAt: createdAt ?? this.createdAt,
      name: clearName ? null : (name ?? this.name),
    );
  }

  Map<String, dynamic> toMap() => {
        'plate': plate,
        'phone': phone,
        'createdAt': createdAt.toIso8601String(),
        'name': name,
      };

  factory Customer.fromMap(Map<String, dynamic> map) => Customer(
        plate: map['plate'] as String,
        phone: map['phone'] as String,
        createdAt: DateTime.parse(map['createdAt'] as String),
        name: (map['name'] as String?)?.trim().isNotEmpty == true
            ? (map['name'] as String).trim()
            : null,
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