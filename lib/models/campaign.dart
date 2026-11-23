/// Gelişmiş kampanya modeli: başlık, açıklama, opsiyonel tarih aralığı ve
/// aktif/pasif durumu tutar. Eski sistemde tek bir düz metin + manuel
/// "aktif" string'i vardı; artık tarihi geçen kampanyalar otomatik olarak
/// mesajlara eklenmiyor (isEffective), sadece aktif olarak işaretlenmiş VE
/// tarih aralığı içinde olan kampanya "geçerli" sayılır.
class Campaign {
  final int? id;
  final String title;
  final String description;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool active;
  final DateTime createdAt;

  /// Sadakat / ziyaret-bazlı kampanya eşiği. Null ise bu kampanya klasik
  /// (tarih aralığı + aktif anahtarı) bir kampanyadır. Doluysa, bir aracın
  /// o ANA KADAR kaç kez geldiği (queue_entries geçmişi) bu sayının tam
  /// katına ulaştığı ziyarette kampanya "kazanılmış" sayılır (ör. 6 girilirse
  /// her 6. yıkamada devreye girer). Bkz. CampaignService.effectiveForVisit.
  final int? visitThreshold;

  const Campaign({
    this.id,
    required this.title,
    required this.description,
    this.startDate,
    this.endDate,
    this.active = false,
    required this.createdAt,
    this.visitThreshold,
  });

  bool get isVisitBased => visitThreshold != null && visitThreshold! > 0;

  /// Belirli bir ziyaret sayısı bu kampanyayı tam olarak "kazandırıyor" mu?
  bool matchesVisitCount(int visitCount) {
    if (!isVisitBased) return false;
    return visitCount > 0 && visitCount % visitThreshold! == 0;
  }

  /// Tarih aralığı tanımlıysa bugünün o aralıkta olup olmadığını kontrol
  /// eder; tanımlı değilse (süresiz kampanya) her zaman geçerli sayılır.
  bool get isCurrentlyValid {
    final now = DateTime.now();
    if (startDate != null && now.isBefore(startDate!)) return false;
    if (endDate != null &&
        now.isAfter(endDate!.add(const Duration(days: 1)))) {
      return false;
    }
    return true;
  }

  /// Mesajlarda kullanılacak kampanya budur: hem "aktif" işaretli hem de
  /// tarih aralığı içinde.
  bool get isEffective => active && isCurrentlyValid;

  Campaign copyWith({
    int? id,
    String? title,
    String? description,
    DateTime? startDate,
    DateTime? endDate,
    bool? active,
    DateTime? createdAt,
    bool clearStartDate = false,
    bool clearEndDate = false,
    int? visitThreshold,
    bool clearVisitThreshold = false,
  }) {
    return Campaign(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      startDate: clearStartDate ? null : (startDate ?? this.startDate),
      endDate: clearEndDate ? null : (endDate ?? this.endDate),
      active: active ?? this.active,
      createdAt: createdAt ?? this.createdAt,
      visitThreshold: clearVisitThreshold
          ? null
          : (visitThreshold ?? this.visitThreshold),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'description': description,
        'startDate': startDate?.toIso8601String(),
        'endDate': endDate?.toIso8601String(),
        'active': active ? 1 : 0,
        'createdAt': createdAt.toIso8601String(),
        'visitThreshold': visitThreshold,
      };

  factory Campaign.fromMap(Map<String, dynamic> map) => Campaign(
        id: map['id'] as int?,
        title: map['title'] as String,
        description: map['description'] as String? ?? '',
        startDate: map['startDate'] != null
            ? DateTime.parse(map['startDate'] as String)
            : null,
        endDate: map['endDate'] != null
            ? DateTime.parse(map['endDate'] as String)
            : null,
        active: (map['active'] as int?) == 1,
        createdAt: DateTime.parse(map['createdAt'] as String),
        visitThreshold: map['visitThreshold'] as int?,
      );
}
