/// Türk plaka formatını zorlayan yardımcı sınıf.
///
/// Sorun: Kamera tüm kareyi OCR'dan geçirince plaka dışındaki logo, marka
/// yazısı, tampon etiketleri vs. de okunup "rastgele yazılar" olarak plaka
/// alanına düşüyordu. Çözüm: hem görsel kırpma (capture_screen'deki rehber
/// dikdörtgeni) hem de bu sınıftaki katı regex ile "İL KODU + HARFLER +
/// SAYI" formatına uymayan hiçbir sonuç plaka olarak kabul edilmiyor.
class TrPlateFormat {
  /// 01-81 il kodu, 1-3 harf (Türk plakalarında Q, W, X kullanılmaz),
  /// 2-5 rakam. Boşluklu, normalize edilmiş hali.
  static final RegExp strict = RegExp(
    r'^(0[1-9]|[1-7][0-9]|8[01]) [A-PR-VYZ]{1,3} [0-9]{2,5}$',
  );

  /// Ham OCR metnini (boşluklu/boşluksuz, küçük/büyük harf farketmez)
  /// "İL HARFLER SAYI" formatına normalize etmeye çalışır.
  /// Başarısızsa null döner — bu durumda sonuç plaka alanına YAZILMAZ,
  /// kullanıcı elle girer (akış kilitlenmez).
  static String? tryFormat(String raw) {
    final cleaned = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (cleaned.length < 5 || cleaned.length > 9) return null;

    final m = RegExp(r'^(\d{2})([A-PR-VYZ]{1,3})(\d{2,5})$').firstMatch(cleaned);
    if (m == null) return null;

    final il = int.tryParse(m.group(1)!);
    if (il == null || il < 1 || il > 81) return null;

    return '${m.group(1)} ${m.group(2)} ${m.group(3)}';
  }

  /// Zaten boşluklu/formatlı bir metnin geçerli olup olmadığını kontrol eder.
  static bool isValid(String formatted) => strict.hasMatch(formatted.trim());

  /// Sıkı format kapalıyken (Ayarlar > "Sıkı Format Kontrolü") kullanılan
  /// gevşek temizleme: sadece harf/rakam bırakır, il kodu/format zorlamaz.
  static String looseClean(String raw) =>
      raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
}
