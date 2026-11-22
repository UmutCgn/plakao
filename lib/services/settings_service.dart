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
  final String activeCampaign;
  final List<String> campaigns;
  final double plateConfThreshold;

  const AppSettings({
    this.shopName = ShopConfig.defaultShopName,
    this.ownerPhone = ShopConfig.defaultShopWhatsAppNumber,
    this.firstContactTemplate = ShopConfig.defaultFirstContactTemplate,
    this.welcomeTemplate = ShopConfig.defaultWelcomeTemplate,
    this.messageTemplate = ShopConfig.defaultReadyTemplate,
    this.activeCampaign = '',
    this.campaigns = const [],
    this.plateConfThreshold = 0.25,
  });

  AppSettings copyWith({
    String? shopName,
    String? ownerPhone,
    String? firstContactTemplate,
    String? welcomeTemplate,
    String? messageTemplate,
    String? activeCampaign,
    List<String>? campaigns,
    double? plateConfThreshold,
  }) {
    return AppSettings(
      shopName: shopName ?? this.shopName,
      ownerPhone: ownerPhone ?? this.ownerPhone,
      firstContactTemplate: firstContactTemplate ?? this.firstContactTemplate,
      welcomeTemplate: welcomeTemplate ?? this.welcomeTemplate,
      messageTemplate: messageTemplate ?? this.messageTemplate,
      activeCampaign: activeCampaign ?? this.activeCampaign,
      campaigns: campaigns ?? this.campaigns,
      plateConfThreshold: plateConfThreshold ?? this.plateConfThreshold,
    );
  }

  Map<String, dynamic> toJson() => {
        'shopName': shopName,
        'ownerPhone': ownerPhone,
        'firstContactTemplate': firstContactTemplate,
        'welcomeTemplate': welcomeTemplate,
        'messageTemplate': messageTemplate,
        'activeCampaign': activeCampaign,
        'campaigns': campaigns,
        'plateConfThreshold': plateConfThreshold,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final parsedCampaigns = ((json['campaigns'] as List?) ?? const [])
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();

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
      activeCampaign: (json['activeCampaign'] as String?)?.trim() ?? '',
      campaigns: parsedCampaigns,
      plateConfThreshold:
          ((json['plateConfThreshold'] as num?)?.toDouble() ?? 0.25)
              .clamp(0.05, 0.90),
    );
  }

  String buildCompletionMessage(String plate) {
    return ShopConfig.readyMessage(plate);
  }

  /// Sadece gecerli 10 haneli TR cep numarasini 905xxxxxxxxx dondurur.
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
      activeCampaign: settings.activeCampaign.trim(),
      campaigns: settings.campaigns
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      plateConfThreshold: settings.plateConfThreshold.clamp(0.05, 0.90),
    );

    final file = await _getSettingsFile();
    await file.writeAsString(jsonEncode(updated.toJson()), flush: true);
    _current = updated;
  }
}