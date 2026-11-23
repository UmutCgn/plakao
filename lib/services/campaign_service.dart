import '../models/campaign.dart';
import 'database_service.dart';

/// Kampanyaları SettingsService ile aynı desende (hafızada cache'lenmiş,
/// senkron okunabilir) yönetir. `effective` getter'ı mesaj şablonlarında
/// (ShopConfig) senkron olarak kullanılabilsin diye DB'ye her seferinde
/// gitmez; `load()` çağrıldığında veya herhangi bir CRUD işleminden sonra
/// cache güncellenir.
///
/// ÖNEMLİ: main.dart içinde uygulama başlarken
///   await CampaignService.instance.load();
/// çağrısının SettingsService.instance.load() ile birlikte yapılması gerekir.
class CampaignService {
  CampaignService._();
  static final CampaignService instance = CampaignService._();

  final _db = DatabaseService.instance;
  List<Campaign> _campaigns = [];

  List<Campaign> get all => List.unmodifiable(_campaigns);

  /// Şu an mesajlara eklenmesi gereken kampanya (aktif + tarih aralığında).
  /// Yoksa null.
  Campaign? get effective {
    for (final c in _campaigns) {
      if (c.isEffective) return c;
    }
    return null;
  }

  Future<void> load() async {
    _campaigns = await _db.getAllCampaigns();
  }

  Future<void> add(Campaign c) async {
    await _db.addCampaign(c);
    await load();
  }

  Future<void> update(Campaign c) async {
    await _db.updateCampaign(c);
    await load();
  }

  Future<void> remove(int id) async {
    await _db.deleteCampaign(id);
    await load();
  }

  Future<void> setActive(int id) async {
    await _db.setActiveCampaign(id);
    await load();
  }

  Future<void> deactivateAll() async {
    await _db.deactivateAllCampaigns();
    await load();
  }
}
