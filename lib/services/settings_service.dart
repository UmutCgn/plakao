import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/shop_config.dart';
import '../models/price_preset.dart';

/// Tema tercihi: sistem / açık / koyu.
enum AppThemeMode { system, light, dark }

AppThemeMode appThemeModeFromString(String? value) {
  switch (value) {
    case 'light':
      return AppThemeMode.light;
    case 'dark':
      return AppThemeMode.dark;
    default:
      return AppThemeMode.system;
  }
}

extension AppThemeModeX on AppThemeMode {
  String get storageValue => name;

  ThemeMode get materialThemeMode {
    switch (this) {
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.system:
        return ThemeMode.system;
    }
  }

  String get label {
    switch (this) {
      case AppThemeMode.light:
        return 'Açık';
      case AppThemeMode.dark:
        return 'Koyu';
      case AppThemeMode.system:
        return 'Sistem';
    }
  }
}

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

  /// Deneysel özellik anahtarı. Açıkken ana ekranın sol menüsünde
  /// "Akıllı Talep Tahmini" sayfasına erişim verir; kapatılınca menü
  /// öğesi tamamen gizlenir.
  final bool experimentalFeatureEnabled;

  /// Deneysel "Gelişmiş Mesaj Şablonları" anahtarı. Kapalıyken Ayarlar
  /// ekranı sade kalır (şablonlar varsayılan metinleriyle sabittir);
  /// açılınca ham {plate}/{shop} etiketli serbest düzenleme alanları
  /// Ayarlar > Gelişmiş Ayarlar altında belirir.
  final bool advancedMessageTemplatesEnabled;

  /// Deneysel "Akıllı Talep Tahmini" özelliğinin hava durumu sorgusu için
  /// kullandığı dükkan konumu. Varsayılan İstanbul'dur; Ayarlar ekranından
  /// değiştirilebilir.
  final double shopLat;
  final double shopLon;

  /// Görünüm tercihi (sistem/açık/koyu).
  final AppThemeMode themeMode;

  /// Ücret politikası: kuyrukta hızlı fiyat seçimi için hazır fiyat listesi.
  final List<PricePreset> pricePresets;

  /// "Araç Bekleme Süresi Uyarısı": açıkken, kuyrukta (yıkanıyor durumunda)
  /// [queueWaitWarningMinutes] dakikadan uzun süredir bekleyen araçlar için
  /// tek seferlik yerel bildirim gönderilir (bkz. HomeScreen._checkWaitTimes
  /// ve NotificationService).
  final bool queueWaitWarningEnabled;
  final int queueWaitWarningMinutes;

  /// DENEYSEL "⏱️ Akıllı Bekleme Tahmini": açıkken kuyruktaki her araç
  /// kartında, önündeki araç sayısı ve geçmiş ortalama yıkama süresine göre
  /// hesaplanan tahmini hazır olma saati gösterilir (bkz.
  /// DatabaseService.getAverageWashMinutes).
  final bool smartWaitEstimateEnabled;

  const AppSettings({
    this.shopName = ShopConfig.defaultShopName,
    this.ownerPhone = ShopConfig.defaultShopWhatsAppNumber,
    this.firstContactTemplate = ShopConfig.defaultFirstContactTemplate,
    this.welcomeTemplate = ShopConfig.defaultWelcomeTemplate,
    this.messageTemplate = ShopConfig.defaultReadyTemplate,
    this.plateConfThreshold = 0.25,
    this.strictPlateFormat = true,
    this.experimentalFeatureEnabled = false,
    this.advancedMessageTemplatesEnabled = false,
    this.shopLat = 41.0082,
    this.shopLon = 28.9784,
    this.themeMode = AppThemeMode.system,
    this.pricePresets = PricePreset.defaults,
    this.queueWaitWarningEnabled = true,
    this.queueWaitWarningMinutes = 20,
    this.smartWaitEstimateEnabled = false,
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
    bool? advancedMessageTemplatesEnabled,
    double? shopLat,
    double? shopLon,
    AppThemeMode? themeMode,
    List<PricePreset>? pricePresets,
    bool? queueWaitWarningEnabled,
    int? queueWaitWarningMinutes,
    bool? smartWaitEstimateEnabled,
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
      advancedMessageTemplatesEnabled: advancedMessageTemplatesEnabled ??
          this.advancedMessageTemplatesEnabled,
      shopLat: shopLat ?? this.shopLat,
      shopLon: shopLon ?? this.shopLon,
      themeMode: themeMode ?? this.themeMode,
      pricePresets: pricePresets ?? this.pricePresets,
      queueWaitWarningEnabled:
          queueWaitWarningEnabled ?? this.queueWaitWarningEnabled,
      queueWaitWarningMinutes:
          queueWaitWarningMinutes ?? this.queueWaitWarningMinutes,
      smartWaitEstimateEnabled:
          smartWaitEstimateEnabled ?? this.smartWaitEstimateEnabled,
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
        'advancedMessageTemplatesEnabled': advancedMessageTemplatesEnabled,
        'shopLat': shopLat,
        'shopLon': shopLon,
        'themeMode': themeMode.storageValue,
        'pricePresets': pricePresets.map((p) => p.toJson()).toList(),
        'queueWaitWarningEnabled': queueWaitWarningEnabled,
        'queueWaitWarningMinutes': queueWaitWarningMinutes,
        'smartWaitEstimateEnabled': smartWaitEstimateEnabled,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final rawPhone = (json['ownerPhone'] as String?) ?? '';
    final normalized = normalizeTrPhone(rawPhone);

    List<PricePreset> presets = PricePreset.defaults;
    final rawPresets = json['pricePresets'];
    if (rawPresets is List && rawPresets.isNotEmpty) {
      presets = rawPresets
          .whereType<Map>()
          .map((m) => PricePreset.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      if (presets.isEmpty) presets = PricePreset.defaults;
    }

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
      advancedMessageTemplatesEnabled:
          (json['advancedMessageTemplatesEnabled'] as bool?) ?? false,
      shopLat: (json['shopLat'] as num?)?.toDouble() ?? 41.0082,
      shopLon: (json['shopLon'] as num?)?.toDouble() ?? 28.9784,
      themeMode: appThemeModeFromString(json['themeMode'] as String?),
      pricePresets: presets,
      queueWaitWarningEnabled:
          (json['queueWaitWarningEnabled'] as bool?) ?? true,
      queueWaitWarningMinutes:
          ((json['queueWaitWarningMinutes'] as num?)?.toInt() ?? 20)
              .clamp(5, 120)
              .toInt(),
      smartWaitEstimateEnabled:
          (json['smartWaitEstimateEnabled'] as bool?) ?? false,
    );
  }

  String buildCompletionMessage(String plate, {int visitCount = 0}) {
    return ShopConfig.readyMessage(plate, visitCount: visitCount);
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

  /// Tema değişikliklerini anında MaterialApp'e yansıtmak için dinlenebilir
  /// bildirici. main.dart bunu ValueListenableBuilder ile dinler.
  final ValueNotifier<ThemeMode> themeNotifier =
      ValueNotifier(ThemeMode.system);

  Future<File> _getSettingsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'plakao_settings.json'));
  }

  Future<AppSettings> load() async {
    try {
      final file = await _getSettingsFile();
      if (!await file.exists()) {
        _current = const AppSettings();
        themeNotifier.value = _current.themeMode.materialThemeMode;
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
    themeNotifier.value = _current.themeMode.materialThemeMode;
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
      pricePresets:
          settings.pricePresets.isEmpty ? PricePreset.defaults : settings.pricePresets,
    );

    final file = await _getSettingsFile();
    await file.writeAsString(jsonEncode(updated.toJson()), flush: true);
    _current = updated;
    themeNotifier.value = updated.themeMode.materialThemeMode;
  }
}