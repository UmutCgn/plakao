/// Ücret politikası: Ayarlar'dan tanımlanan hazır yıkama ücretleri.
/// Kuyruktaki "Ücret Belirle" butonunda bu listeden hızlıca seçim yapılır;
/// araçlar farklı fiyata yıkanabildiği için her kayda ayrı atanır.
class PricePreset {
  final String label;
  final double price;

  const PricePreset({required this.label, required this.price});

  Map<String, dynamic> toJson() => {'label': label, 'price': price};

  factory PricePreset.fromJson(Map<String, dynamic> json) => PricePreset(
        label: (json['label'] as String?)?.trim().isNotEmpty == true
            ? (json['label'] as String).trim()
            : 'Ücret',
        price: (json['price'] as num?)?.toDouble() ?? 0,
      );

  static const List<PricePreset> defaults = [
    PricePreset(label: 'Küçük Araç', price: 150),
    PricePreset(label: 'Orta Boy / Sedan', price: 200),
    PricePreset(label: 'SUV / Pickup', price: 300),
    PricePreset(label: 'Ticari / Minibüs', price: 400),
  ];
}
