import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/campaign.dart';
import '../models/vehicle.dart';
import 'messaging_service.dart';

export '../models/campaign.dart' show PhoneCampaignProgress;

/// Tüm yerel (sqflite) veritabanı işlemlerini tek noktadan yönetir.
class DatabaseService {
  DatabaseService._internal();
  static final DatabaseService instance = DatabaseService._internal();

  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'plakao.db');

    return openDatabase(
      path,
      // v2: kampanyalar tablosu eklendi (eski düz-metin kampanya sistemi
      // yerine, tarih aralığı destekli gerçek kayıt tablosu).
      // v3: campaigns.visitThreshold eklendi — ziyaret sayısına göre
      // (ör. "her 6 yıkamada 1 ücretsiz") sadakat kampanyaları için.
      // v4: queue_entries.price (araç bazlı yıkama ücreti, istatistik/ciro
      // için) ve customers.name (rehberde isim gösterimi) eklendi.
      // v5: queue_entries.waitWarnedAt eklendi — "Araç Bekleme Süresi
      // Uyarısı" bildiriminin aynı araca birden fazla kez atılmasını
      // engellemek için gönderim zamanı burada tutulur.
      version: 5,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE customers (
            plate TEXT PRIMARY KEY,
            phone TEXT NOT NULL,
            createdAt TEXT NOT NULL,
            name TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE queue_entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            plate TEXT NOT NULL,
            phone TEXT,
            status TEXT NOT NULL,
            createdAt TEXT NOT NULL,
            notifiedAt TEXT,
            price REAL,
            waitWarnedAt TEXT
          )
        ''');

        await _createCampaignsTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createCampaignsTable(db);
        }
        if (oldVersion < 3) {
          // campaigns tablosu v2'de zaten yoksa _createCampaignsTable yeni
          // kolonla birlikte oluşturur; v2'den geliyorsa ALTER TABLE gerekir.
          try {
            await db.execute(
              'ALTER TABLE campaigns ADD COLUMN visitThreshold INTEGER',
            );
          } catch (_) {
            // Kolon zaten varsa (yeni kurulum _createCampaignsTable'dan
            // geçtiyse) sqflite hata fırlatır; görmezden gel.
          }
        }
        if (oldVersion < 4) {
          try {
            await db.execute('ALTER TABLE queue_entries ADD COLUMN price REAL');
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE customers ADD COLUMN name TEXT');
          } catch (_) {}
        }
        if (oldVersion < 5) {
          try {
            await db.execute(
              'ALTER TABLE queue_entries ADD COLUMN waitWarnedAt TEXT',
            );
          } catch (_) {}
        }
      },
    );
  }

  Future<void> _createCampaignsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS campaigns (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        description TEXT,
        startDate TEXT,
        endDate TEXT,
        active INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL,
        visitThreshold INTEGER
      )
    ''');
  }

  /// Plakadaki boşluk ve özel karakterleri temizleyip büyük harfe çevirir.
  String normalizePlate(String raw) {
    return raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '').trim();
  }

  // ---------- Customers (daimi müşteri plaka -> telefon eşlemesi) ----------

  Future<Customer?> findCustomerByPlate(String plate) async {
    final db = await database;
    final normalized = normalizePlate(plate);
    if (normalized.isEmpty) return null;

    final rows = await db.query(
      'customers',
      where: 'plate = ?',
      whereArgs: [normalized],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Customer.fromMap(rows.first);
  }

  Future<void> upsertCustomer(String plate, String phone, {String? name}) async {
    final db = await database;
    final normalizedPlate = normalizePlate(plate);
    final normalizedPhone = MessagingService.normalizePhone(phone);
    if (normalizedPlate.isEmpty || normalizedPhone.isEmpty) return;

    // İsim verilmemişse (örn. kuyruk akışından gelen çağrılar), varsa
    // mevcut ismi korumak için önce eski kaydı okuyoruz.
    String? resolvedName = name?.trim();
    if (resolvedName == null || resolvedName.isEmpty) {
      final existing = await findCustomerByPlate(normalizedPlate);
      resolvedName = existing?.name;
    }

    await db.insert(
      'customers',
      Customer(
        plate: normalizedPlate,
        phone: normalizedPhone,
        createdAt: DateTime.now(),
        name: resolvedName,
      ).toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Rehberden sadece telefon numarasını günceller (plaka/ad aynı kalır).
  Future<void> updateCustomerPhone(String plate, String phone) async {
    final db = await database;
    final normalizedPlate = normalizePlate(plate);
    final normalizedPhone = MessagingService.normalizePhone(phone);
    if (normalizedPlate.isEmpty || normalizedPhone.isEmpty) return;
    await db.update(
      'customers',
      {'phone': normalizedPhone},
      where: 'plate = ?',
      whereArgs: [normalizedPlate],
    );
  }

  /// Rehberden müşteri adını günceller/temizler.
  Future<void> updateCustomerName(String plate, String? name) async {
    final db = await database;
    final normalizedPlate = normalizePlate(plate);
    if (normalizedPlate.isEmpty) return;
    final trimmed = name?.trim();
    await db.update(
      'customers',
      {'name': (trimmed == null || trimmed.isEmpty) ? null : trimmed},
      where: 'plate = ?',
      whereArgs: [normalizedPlate],
    );
  }

  /// Rehberden bir kaydı tamamen siler (geçmiş yıkama kayıtları/istatistik
  /// etkilenmez, sadece plaka↔telefon eşlemesi kaldırılır).
  Future<void> deleteCustomer(String plate) async {
    final db = await database;
    final normalizedPlate = normalizePlate(plate);
    if (normalizedPlate.isEmpty) return;
    await db.delete('customers', where: 'plate = ?', whereArgs: [normalizedPlate]);
  }

  Future<List<Customer>> getAllCustomers() async {
    final db = await database;
    final rows = await db.query('customers', orderBy: 'createdAt DESC');
    return rows.map(Customer.fromMap).toList();
  }

  /// Rehber ekranı için: her müşterinin kaç kez geldiğini ve son ziyaretini
  /// queue_entries geçmişinden hesaplar.
  Future<List<CustomerVisitInfo>> getCustomerDirectory() async {
    final db = await database;
    final customers = await getAllCustomers();
    final result = <CustomerVisitInfo>[];

    for (final c in customers) {
      final rows = await db.query(
        'queue_entries',
        where: 'plate = ?',
        whereArgs: [c.plate],
        orderBy: 'createdAt DESC',
      );
      result.add(CustomerVisitInfo(
        customer: c,
        visitCount: rows.length,
        lastVisit: rows.isNotEmpty
            ? DateTime.parse(rows.first['createdAt'] as String)
            : c.createdAt,
      ));
    }

    result.sort((a, b) => b.lastVisit.compareTo(a.lastVisit));
    return result;
  }

  /// Bu plakanın queue_entries geçmişinde şu ana kadar kaç kaydı var.
  /// Sadakat/kampanya mesajlarında "bu kaçıncı yıkama" hesabı için kullanılır.
  Future<int> getVisitCount(String plate) async {
    final db = await database;
    final normalized = normalizePlate(plate);
    if (normalized.isEmpty) return 0;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM queue_entries WHERE plate = ?',
      [normalized],
    );
    final value = result.first['cnt'];
    return value is int ? value : int.tryParse('$value') ?? 0;
  }

  /// Bir TELEFON NUMARASININ şu ana kadarki toplam ziyaret (yıkama) sayısı.
  /// Bir kişinin birden fazla plakası olabileceği için kampanya takibi artık
  /// plaka yerine telefon numarası bazlı yapılır (bkz. CampaignService).
  Future<int> getVisitCountByPhone(String phone) async {
    final db = await database;
    final normalized = MessagingService.normalizePhone(phone);
    if (normalized.isEmpty) return 0;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM queue_entries WHERE phone = ?',
      [normalized],
    );
    final value = result.first['cnt'];
    return value is int ? value : int.tryParse('$value') ?? 0;
  }

  /// Bir kaydın ziyaret sayısını hesaplarken, telefonu varsa o numaranın
  /// TÜM plakalardaki toplam ziyaretini, yoksa sadece bu plakanın geçmişini
  /// kullanır.
  Future<int> getVisitCountForEntry({required String plate, String? phone}) async {
    if (phone != null && phone.trim().isNotEmpty) {
      final byPhone = await getVisitCountByPhone(phone);
      if (byPhone > 0) return byPhone;
    }
    return getVisitCount(plate);
  }

  /// Canlı kamera akışında otomatik yakalama kilitlendiğinde (bkz.
  /// capture_screen.dart) özet kartı tek çağrıda doldurmak için: plakanın
  /// kayıtlı müşterisi + (telefonu varsa telefon bazlı, yoksa plaka bazlı)
  /// toplam ziyaret sayısı.
  Future<({Customer? customer, int visitCount})> getQuickSummary(
    String plate,
  ) async {
    final customer = await findCustomerByPlate(plate);
    final visitCount = await getVisitCountForEntry(
      plate: plate,
      phone: customer?.phone,
    );
    return (customer: customer, visitCount: visitCount);
  }

  // ---------- Queue (aktif kuyruk / günlük akış) ----------

  Future<int> addToQueue({
    required String plate,
    String? phone,
    QueueStatus status = QueueStatus.inQueue,
  }) async {
    final db = await database;
    final normalizedPlate = normalizePlate(plate);
    final cleanPhone = (phone != null && phone.trim().isNotEmpty)
        ? MessagingService.normalizePhone(phone)
        : null;

    return db.insert(
      'queue_entries',
      QueueEntry(
        plate: normalizedPlate,
        phone: cleanPhone,
        status: status,
        createdAt: DateTime.now(),
      ).toMap(),
    );
  }

  Future<List<QueueEntry>> getActiveQueue() async {
    final db = await database;
    final rows = await db.query(
      'queue_entries',
      where: 'status != ?',
      whereArgs: [QueueStatus.delivered.name],
      orderBy: 'createdAt ASC',
    );
    return rows.map(QueueEntry.fromMap).toList();
  }

  Future<List<QueueEntry>> getAllQueueEntries() async {
    final db = await database;
    final rows = await db.query('queue_entries', orderBy: 'createdAt DESC');
    return rows.map(QueueEntry.fromMap).toList();
  }

  Future<void> updateStatus(int id, QueueStatus status) async {
    final db = await database;
    await db.update(
      'queue_entries',
      {'status': status.name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Kuyruktaki bir araca ücret atar/günceller ("Ücret Belirle" butonu).
  Future<void> setEntryPrice(int id, double? price) async {
    final db = await database;
    await db.update(
      'queue_entries',
      {'price': price},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updatePhoneAndSaveCustomer({
    required int entryId,
    required String plate,
    required String phone,
  }) async {
    final db = await database;
    final normalizedPhone = MessagingService.normalizePhone(phone);

    await db.update(
      'queue_entries',
      {'phone': normalizedPhone},
      where: 'id = ?',
      whereArgs: [entryId],
    );
    await upsertCustomer(plate, normalizedPhone);
  }

  Future<void> markNotified(int id) async {
    final db = await database;
    await db.update(
      'queue_entries',
      {
        'status': QueueStatus.delivered.name,
        'notifiedAt': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// "Araç Bekleme Süresi Uyarısı" bildirimi gönderildiğinde çağrılır; aynı
  /// kayıt için bildirimin tekrar tekrar atılmaması için zamanı kaydeder.
  Future<void> markWaitWarned(int id) async {
    final db = await database;
    await db.update(
      'queue_entries',
      {'waitWarnedAt': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteEntry(int id) async {
    final db = await database;
    await db.delete('queue_entries', where: 'id = ?', whereArgs: [id]);
  }

  /// DENEYSEL "Akıllı Bekleme Tahmini" özelliği için: son tamamlanan
  /// yıkamaların (createdAt -> notifiedAt) ortalama süresini dakika olarak
  /// hesaplar. Yeterli geçmiş veri yoksa [fallbackMinutes] döner. Aşırı uç
  /// (ör. araç kaydı açık unutulup saatler sonra teslim edilmiş) kayıtların
  /// ortalamayı bozmaması için 3 saatten uzun süren kayıtlar hesaba katılmaz.
  Future<double> getAverageWashMinutes({
    int sampleSize = 30,
    double fallbackMinutes = 20,
  }) async {
    final db = await database;
    final rows = await db.query(
      'queue_entries',
      where: 'notifiedAt IS NOT NULL',
      orderBy: 'createdAt DESC',
      limit: sampleSize,
    );
    if (rows.isEmpty) return fallbackMinutes;

    final durations = <double>[];
    for (final r in rows) {
      final created = DateTime.tryParse(r['createdAt'] as String? ?? '');
      final notified = DateTime.tryParse(r['notifiedAt'] as String? ?? '');
      if (created == null || notified == null) continue;
      final minutes = notified.difference(created).inMinutes.toDouble();
      if (minutes > 0 && minutes <= 180) durations.add(minutes);
    }
    if (durations.isEmpty) return fallbackMinutes;
    return durations.reduce((a, b) => a + b) / durations.length;
  }

  // ---------- İstatistik: ciro (günlük/haftalık/aylık) ----------

  Future<double> _sumPriceBetween(DateTime from, DateTime to) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT price, createdAt FROM queue_entries '
      "WHERE price IS NOT NULL AND status != 'inQueue' "
      'AND createdAt >= ? AND createdAt < ?',
      [from.toIso8601String(), to.toIso8601String()],
    );
    double total = 0;
    for (final r in rows) {
      total += (r['price'] as num?)?.toDouble() ?? 0;
    }
    return total;
  }

  /// Bugünün toplam cirosu (fiyatı girilmiş, kuyruktan çıkmış araçlar).
  Future<double> getTodayRevenue() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    return _sumPriceBetween(start, end);
  }

  Future<double> getWeekRevenue() async {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final start = startOfToday.subtract(const Duration(days: 6));
    final end = startOfToday.add(const Duration(days: 1));
    return _sumPriceBetween(start, end);
  }

  Future<double> getMonthRevenue() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month + 1, 1);
    return _sumPriceBetween(start, end);
  }

  /// Kampanya takip ekranı için: rehberdeki her telefon numarasının (aynı
  /// kişi birden fazla plakaya sahip olabileceğinden plaka değil telefon
  /// bazlı) toplam ziyaret sayısı.
  Future<List<PhoneCampaignProgress>> getCampaignTrackingList() async {
    final customers = await getAllCustomers();
    final platesByPhone = <String, List<String>>{};
    for (final c in customers) {
      platesByPhone.putIfAbsent(c.phone, () => []).add(c.plate);
    }

    final result = <PhoneCampaignProgress>[];
    for (final e in platesByPhone.entries) {
      final visits = await getVisitCountByPhone(e.key);
      result.add(PhoneCampaignProgress(
        phone: e.key,
        plates: e.value,
        visitCount: visits,
      ));
    }
    result.sort((a, b) => b.visitCount.compareTo(a.visitCount));
    return result;
  }

  // ---------- Campaigns (yeni, tarih aralığı destekli) ----------

  Future<int> addCampaign(Campaign c) async {
    final db = await database;
    final map = c.toMap()..remove('id');
    return db.insert('campaigns', map);
  }

  Future<void> updateCampaign(Campaign c) async {
    final db = await database;
    await db.update('campaigns', c.toMap(), where: 'id = ?', whereArgs: [c.id]);
  }

  Future<void> deleteCampaign(int id) async {
    final db = await database;
    await db.delete('campaigns', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Campaign>> getAllCampaigns() async {
    final db = await database;
    final rows = await db.query('campaigns', orderBy: 'createdAt DESC');
    return rows.map(Campaign.fromMap).toList();
  }

  /// Aynı anda sadece bir kampanya "aktif" olabilir; yenisini aktif
  /// yaparken diğerlerini otomatik pasife çeker.
  Future<void> setActiveCampaign(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update('campaigns', {'active': 0});
      await txn.update('campaigns', {'active': 1}, where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> deactivateAllCampaigns() async {
    final db = await database;
    await db.update('campaigns', {'active': 0});
  }
}