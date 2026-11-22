import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/vehicle.dart';
import 'messaging_service.dart';

/// Tum yerel (sqflite) veritabani islemlerini tek noktadan yonetir.
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
      version: 1,
      onCreate: (db, version) async {
        // Daimi musteri eslemesi: plaka -> telefon.
        await db.execute('''
          CREATE TABLE customers (
            plate TEXT PRIMARY KEY,
            phone TEXT NOT NULL,
            createdAt TEXT NOT NULL
          )
        ''');

        // Gunluk/aktif kuyruk kayitlari.
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
      },
    );
  }

  /// Plakadaki bosluk ve ozel karakterleri temizleyip buyuk harfe cevirir.
  String normalizePlate(String raw) {
    return raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '').trim();
  }

  // ---------- Customers (daimi musteri plaka -> telefon eslesmesi) ----------

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

  // ---------- Queue (aktif kuyruk / gunluk akis) ----------

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
    final rows = await db.query(
      'queue_entries',
      orderBy: 'createdAt DESC',
    );
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
}