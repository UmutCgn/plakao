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

  /// Belirli bir aracın ziyaret sayısına göre geçerli kampanyayı döner.
  /// Öncelik sırası:
  ///   1) Ziyaret-bazlı (visitThreshold'u olan) ve bu ziyaret sayısında TAM
  ///      olarak "kazanılan" (ör. her 6 yıkamada 1) aktif bir kampanya varsa
  ///      o döner — müşteri hak kazandığı anda bunu görür.
  ///   2) Yoksa, klasik tarih aralıklı / süresiz, ziyaret sayısından bağımsız
  ///      aktif bir kampanya (varsa) döner.
  ///   3) Hiçbiri yoksa null.
  Campaign? effectiveForVisit(int visitCount) {
    for (final c in _campaigns) {
      if (!c.active || !c.isCurrentlyValid) continue;
      if (c.isVisitBased && c.matchesVisitCount(visitCount)) return c;
    }
    for (final c in _campaigns) {
      if (c.isEffective && !c.isVisitBased) return c;
    }
    return null;
  }

  /// Şu an aktif olan, ziyaret/sadakat bazlı kampanya (varsa). Kampanya
  /// takibi ("3/6 yıkama") bunun üzerinden hesaplanır; klasik tarih
  /// aralıklı kampanyalardan bağımsızdır.
  Campaign? get activeVisitBasedCampaign {
    for (final c in _campaigns) {
      if (c.active && c.isCurrentlyValid && c.isVisitBased) return c;
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
