import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/shop_config.dart';

class AppSettings {
  final String shopName;
  final String ownerPhone;
  final String firstContactTemplate;
  final String welcomeTemplate;
  final String messageTemplate;
  final double plateConfThreshold;

  /// Plaka OCR sonucunun "İL KODU + HARFLER + SAYI" formatına zorlanıp
  /// zorlanmayacağı. Kapalıyken ham temizlenmiş metin plaka alanına yazılır
  /// (model test ederken random/eksik sonuçları görmek için kullanışlıdır).
  final bool strictPlateFormat;

  /// Deneysel özellik anahtarı. Açıkken ana ekranın sağ üstünde ⋮ menüsü
  /// belirir ve "Akıllı Talep Tahmini" sayfasına erişim verir; kapatılınca
  /// menü tamamen gizlenir.
  final bool experimentalFeatureEnabled;

  /// Deneysel "Akıllı Talep Tahmini" özelliğinin hava durumu sorgusu için
  /// kullandığı dükkan konumu. Varsayılan İstanbul'dur; Ayarlar ekranından
  /// değiştirilebilir.
  final double shopLat;
  final double shopLon;

  const AppSettings({
    this.shopName = ShopConfig.defaultShopName,
    this.ownerPhone = ShopConfig.defaultShopWhatsAppNumber,
    this.firstContactTemplate = ShopConfig.defaultFirstContactTemplate,
    this.welcomeTemplate = ShopConfig.defaultWelcomeTemplate,
    this.messageTemplate = ShopConfig.defaultReadyTemplate,
    this.plateConfThreshold = 0.25,
    this.strictPlateFormat = true,
    this.experimentalFeatureEnabled = false,
    this.shopLat = 41.0082,
    this.shopLon = 28.9784,
  });

  AppSettings copyWith({
    String? shopName,
    String? ownerPhone,
    String? firstContactTemplate,
    String? welcomeTemplate,
    String? messageTemplate,
    double? plateConfThreshold,
    bool? strictPlateFormat,
    bool? experimentalFeatureEnabled,
    double? shopLat,
    double? shopLon,
  }) {
    return AppSettings(
      shopName: shopName ?? this.shopName,
      ownerPhone: ownerPhone ?? this.ownerPhone,
      firstContactTemplate: firstContactTemplate ?? this.firstContactTemplate,
      welcomeTemplate: welcomeTemplate ?? this.welcomeTemplate,
      messageTemplate: messageTemplate ?? this.messageTemplate,
      plateConfThreshold: plateConfThreshold ?? this.plateConfThreshold,
      strictPlateFormat: strictPlateFormat ?? this.strictPlateFormat,
      experimentalFeatureEnabled:
          experimentalFeatureEnabled ?? this.experimentalFeatureEnabled,
      shopLat: shopLat ?? this.shopLat,
      shopLon: shopLon ?? this.shopLon,
    );
  }

  Map<String, dynamic> toJson() => {
        'shopName': shopName,
        'ownerPhone': ownerPhone,
        'firstContactTemplate': firstContactTemplate,
        'welcomeTemplate': welcomeTemplate,
        'messageTemplate': messageTemplate,
        'plateConfThreshold': plateConfThreshold,
        'strictPlateFormat': strictPlateFormat,
        'experimentalFeatureEnabled': experimentalFeatureEnabled,
        'shopLat': shopLat,
        'shopLon': shopLon,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final rawPhone = (json['ownerPhone'] as String?) ?? '';
    final normalized = normalizeTrPhone(rawPhone);

    return AppSettings(
      shopName: (json['shopName'] as String?)?.trim().isNotEmpty == true
          ? (json['shopName'] as String).trim()
          : ShopConfig.defaultShopName,
      ownerPhone:
          normalized.isNotEmpty ? normalized : ShopConfig.defaultShopWhatsAppNumber,
      firstContactTemplate:
          (json['firstContactTemplate'] as String?)?.trim().isNotEmpty == true
              ? (json['firstContactTemplate'] as String).trim()
              : ShopConfig.defaultFirstContactTemplate,
      welcomeTemplate:
          (json['welcomeTemplate'] as String?)?.trim().isNotEmpty == true
              ? (json['welcomeTemplate'] as String).trim()
              : ShopConfig.defaultWelcomeTemplate,
      messageTemplate:
          (json['messageTemplate'] as String?)?.trim().isNotEmpty == true
              ? (json['messageTemplate'] as String).trim()
              : ShopConfig.defaultReadyTemplate,
      plateConfThreshold:
          ((json['plateConfThreshold'] as num?)?.toDouble() ?? 0.25)
              .clamp(0.05, 0.90),
      strictPlateFormat: (json['strictPlateFormat'] as bool?) ?? true,
      experimentalFeatureEnabled:
          (json['experimentalFeatureEnabled'] as bool?) ?? false,
      shopLat: (json['shopLat'] as num?)?.toDouble() ?? 41.0082,
      shopLon: (json['shopLon'] as num?)?.toDouble() ?? 28.9784,
    );
  }

  String buildCompletionMessage(String plate) {
    return ShopConfig.readyMessage(plate);
  }

  /// Sadece geçerli 10 haneli TR cep numarasını 905xxxxxxxxx döndürür.
  static String normalizeTrPhone(String raw) {
    var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';

    if (digits.startsWith('0090') && digits.length == 14) {
      digits = digits.substring(2);
    }

    if (digits.startsWith('90') && digits.length == 12 && digits[2] == '5') {
      return digits;
    }
    if (digits.startsWith('0') && digits.length == 11 && digits[1] == '5') {
      return '9$digits';
    }
    if (digits.startsWith('5') && digits.length == 10) {
      return '90$digits';
    }
    return '';
  }
}

class SettingsService {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  AppSettings _current = const AppSettings();
  AppSettings get current => _current;

  Future<File> _getSettingsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'plakao_settings.json'));
  }

  Future<AppSettings> load() async {
    try {
      final file = await _getSettingsFile();
      if (!await file.exists()) {
        _current = const AppSettings();
        return _current;
      }
      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) {
        _current = AppSettings.fromJson(decoded);
      }
    } catch (_) {
      _current = const AppSettings();
    }
    return _current;
  }

  Future<void> save(AppSettings settings) async {
    final normalizedPhone = AppSettings.normalizeTrPhone(settings.ownerPhone);
    final updated = settings.copyWith(
      shopName: settings.shopName.trim().isEmpty
          ? ShopConfig.defaultShopName
          : settings.shopName.trim(),
      ownerPhone:
          normalizedPhone.isNotEmpty ? normalizedPhone : _current.ownerPhone,
      firstContactTemplate: settings.firstContactTemplate.trim().isEmpty
          ? ShopConfig.defaultFirstContactTemplate
          : settings.firstContactTemplate.trim(),
      welcomeTemplate: settings.welcomeTemplate.trim().isEmpty
          ? ShopConfig.defaultWelcomeTemplate
          : settings.welcomeTemplate.trim(),
      messageTemplate: settings.messageTemplate.trim().isEmpty
          ? ShopConfig.defaultReadyTemplate
          : settings.messageTemplate.trim(),
      plateConfThreshold: settings.plateConfThreshold.clamp(0.05, 0.90),
    );

    final file = await _getSettingsFile();
    await file.writeAsString(jsonEncode(updated.toJson()), flush: true);
    _current = updated;
  }
}
