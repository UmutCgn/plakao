import '../services/settings_service.dart';

/// Dukkan ayarlari. Varsayilan degerler uygulama ilk acildiginda kullanilir,
/// Ayarlar ekranindan kaydedildikce canli olarak guncellenir.
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

  /// Dukkanin WhatsApp/SMS alabilen numarasi (905xxxxxxxxx).
  static String get shopWhatsAppNumber {
    final saved = SettingsService.instance.current.ownerPhone.trim();
    return saved.isNotEmpty ? saved : defaultShopWhatsAppNumber;
  }

  static String _render(String template, String plate) {
    final current = SettingsService.instance.current;
    final activeCampaign = current.activeCampaign.trim();
    final campaignLine =
        activeCampaign.isNotEmpty ? '\nKampanya: \$activeCampaign' : '';

    return template
        .replaceAll('{plate}', plate.trim().toUpperCase())
        .replaceAll('{shop}', shopName)
        .replaceAll('{campaign}', activeCampaign)
        .replaceAll('{campaignLine}', campaignLine);
  }

  /// Musteri ilk kez QR okuttugunda, kendi telefonundan dukkana atacagi hazir mesaj.
  static String firstContactMessage(String plate) {
    final tpl = SettingsService.instance.current.firstContactTemplate.trim();
    return _render(tpl.isNotEmpty ? tpl : defaultFirstContactTemplate, plate);
  }

  /// Numara girisinden sonra musteriye ilk bilgilendirme mesaji.
  static String welcomeMessage(String plate) {
    final tpl = SettingsService.instance.current.welcomeTemplate.trim();
    return _render(tpl.isNotEmpty ? tpl : defaultWelcomeTemplate, plate);
  }

  /// Yikama tamamlandiginda musteriye gonderilecek hazir mesaj.
  static String readyMessage(String plate) {
    final tpl = SettingsService.instance.current.messageTemplate.trim();
    return _render(tpl.isNotEmpty ? tpl : defaultReadyTemplate, plate);
  }
}