import '../services/campaign_service.dart';
import '../services/settings_service.dart';

/// Dükkan ayarları. Varsayılan değerler uygulama ilk açıldığında kullanılır,
/// Ayarlar ekranından kaydedildikçe canlı olarak güncellenir.
class ShopConfig {
  static const String defaultShopName = 'Plakao Oto Yıkama';
  static const String defaultShopWhatsAppNumber = '905434989299';

  static const String defaultFirstContactTemplate =
      'Merhaba, {plate} plakali aracim yikamaya girdi. Numaramı '
      'birakiyorum, yikama bitince bu numaradan haber bekliyorum.{campaignLine}';

  static const String defaultWelcomeTemplate =
      'Merhaba, {plate} plakali araciniz yikama kuyruguna alindi. '
      'Yikama bitince bu numaradan size haber verecegiz.{campaignLine}';

  static const String defaultReadyTemplate =
      'Merhaba, {plate} plakali araciniz yikandi ve teslime hazir. '
      'Bilginize sunariz, iyi gunler dileriz.{campaignLine}';

  static String get shopName {
    final saved = SettingsService.instance.current.shopName.trim();
    return saved.isNotEmpty ? saved : defaultShopName;
  }

  /// Dükkanın WhatsApp/SMS alabilen numarası (905xxxxxxxxx).
  static String get shopWhatsAppNumber {
    final saved = SettingsService.instance.current.ownerPhone.trim();
    return saved.isNotEmpty ? saved : defaultShopWhatsAppNumber;
  }

  static String _render(String template, String plate, {int visitCount = 0}) {
    // ÖNEMLİ DÜZELTME: eski kodda '\nKampanya: \$activeCampaign' yazıyordu.
    // Dart'ta '\$' kaçışlı (escaped) dolar işaretidir; bu satır değişkeni
    // interpolate ETMİYOR, olduğu gibi "$activeCampaign" kelimesini
    // basıyordu. Kampanyalar hiçbir zaman gerçek metinleriyle müşteriye
    // gitmiyordu. Artık CampaignService'ten (tarih aralığı VE ziyaret
    // sayısı farkında) geçerli kampanya alınıp düzgün interpolate ediliyor.
    final effective = CampaignService.instance.effectiveForVisit(visitCount);
    final campaignText = effective?.description.trim() ?? '';
    final campaignLine =
        campaignText.isNotEmpty ? '\nKampanya: $campaignText' : '';

    return template
        .replaceAll('{plate}', plate.trim().toUpperCase())
        .replaceAll('{shop}', shopName)
        .replaceAll('{campaign}', campaignText)
        .replaceAll('{campaignLine}', campaignLine);
  }

  /// Müşteri ilk kez QR okuttuğunda, kendi telefonundan dükkana atacağı
  /// hazır mesaj. [visitCount], bu aracın bu kayıtla birlikte kaçıncı
  /// ziyareti olduğudur (sadakat kampanyası hesaplaması için).
  static String firstContactMessage(String plate, {int visitCount = 0}) {
    final tpl = SettingsService.instance.current.firstContactTemplate.trim();
    return _render(tpl.isNotEmpty ? tpl : defaultFirstContactTemplate, plate,
        visitCount: visitCount);
  }

  /// Numara girişinden sonra müşteriye ilk bilgilendirme mesajı.
  static String welcomeMessage(String plate, {int visitCount = 0}) {
    final tpl = SettingsService.instance.current.welcomeTemplate.trim();
    return _render(tpl.isNotEmpty ? tpl : defaultWelcomeTemplate, plate,
        visitCount: visitCount);
  }

  /// Yıkama tamamlandığında müşteriye gönderilecek hazır mesaj.
  static String readyMessage(String plate, {int visitCount = 0}) {
    final tpl = SettingsService.instance.current.messageTemplate.trim();
    return _render(tpl.isNotEmpty ? tpl : defaultReadyTemplate, plate,
        visitCount: visitCount);
  }
}
