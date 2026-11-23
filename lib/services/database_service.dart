import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/campaign.dart';
import '../models/vehicle.dart';
import 'messaging_service.dart';

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
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE customers (
            plate TEXT PRIMARY KEY,
            phone TEXT NOT NULL,
            createdAt TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE queue_entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            plate TEXT NOT NULL,
            phone TEXT,
            status TEXT NOT NULL,
            createdAt TEXT NOT NULL,
            notifiedAt TEXT
          )
        ''');

        await _createCampaignsTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createCampaignsTable(db);
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
        createdAt TEXT NOT NULL
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

  Future<void> upsertCustomer(String plate, String phone) async {
    final db = await database;
    final normalizedPlate = normalizePlate(plate);
    final normalizedPhone = MessagingService.normalizePhone(phone);
    if (normalizedPlate.isEmpty || normalizedPhone.isEmpty) return;

    await db.insert(
      'customers',
      Customer(
        plate: normalizedPlate,
        phone: normalizedPhone,
        createdAt: DateTime.now(),
      ).toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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

  Future<void> deleteEntry(int id) async {
    final db = await database;
    await db.delete('queue_entries', where: 'id = ?', whereArgs: [id]);
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
