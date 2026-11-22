import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/shop_config.dart';
import '../models/vehicle.dart';
import '../services/database_service.dart';
import '../services/messaging_service.dart';
import '../services/settings_service.dart';
import 'capture_screen.dart';
import 'settings_screen.dart';
import 'package:plakao/screens/stats_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _db = DatabaseService.instance;
  late Future<List<QueueEntry>> _queueFuture;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _queueFuture = _db.getActiveQueue();
    });
  }

  Future<void> _openCapture() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CaptureScreen()),
    );
    if (added == true) _refresh();
  }

  Future<void> _openSettings() async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    if (updated == true) _refresh();
  }

  Future<void> _markReady(QueueEntry entry) async {
    await _db.updateStatus(entry.id!, QueueStatus.ready);
    _refresh();
  }

  /// Tek tusla bildirim: once WhatsApp dener, acilmazsa SMS'e duser.
  /// [forceSms] true verilirse dogrudan SMS acar.
  Future<void> _notifyAndDeliver(QueueEntry entry, {bool forceSms = false}) async {
    String? phone = entry.phone;

    if (phone == null || !MessagingService.isValidPhone(phone)) {
      phone = await _askForPhoneNumber(entry.plate);
      if (phone == null) return;
      await _db.updatePhoneAndSaveCustomer(
        entryId: entry.id!,
        plate: entry.plate,
        phone: phone,
      );
    }

    final settings = SettingsService.instance.current;
    final message = settings.messageTemplate.trim().isNotEmpty
        ? settings.buildCompletionMessage(entry.plate)
        : ShopConfig.readyMessage(entry.plate);

    final ok = forceSms
        ? await MessagingService.sendSms(phone, message)
        : await MessagingService.sendWhatsAppOrSms(phone, message);

    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mesaj uygulaması açılamadı. Numarayı kontrol edin.'),
          ),
        );
      }
      return;
    }

    await _db.markNotified(entry.id!);
    _refresh();
  }

  Future<String?> _askForPhoneNumber(String plate) async {
    final ownerPhone = SettingsService.instance.current.ownerPhone;
    final controller = TextEditingController(text: ownerPhone);

    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$plate - Telefon Numarası'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              keyboardType: TextInputType.phone,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Müşteri telefonu',
                hintText: '05xx xxx xx xx',
              ),
            ),
            if (ownerPhone.isNotEmpty) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => controller.text = ownerPhone,
                icon: const Icon(Icons.person, size: 18),
                label: Text('Kendi numaramı kullan ($ownerPhone)'),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: () {
              final value = controller.text.trim();
              if (!MessagingService.isValidPhone(value)) return;
              Navigator.pop(ctx, value);
            },
            child: const Text('Kaydet ve Bildir'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shopName = SettingsService.instance.current.shopName;

    return Scaffold(
      appBar: AppBar(
        title: Text('$shopName - Kuyruk'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _openSettings,
            icon: const Icon(Icons.settings),
            tooltip: 'Ayarlar',
          ),
          IconButton(
            onPressed: () {
            Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const StatsScreen()),
            );
            },
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Raporlar ve Kampanyalar',
          ),
        ],
      ),
      body: FutureBuilder<List<QueueEntry>>(
        future: _queueFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final queue = snapshot.data!;
          if (queue.isEmpty) {
            return const _EmptyQueue();
          }
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: queue.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final entry = queue[index];
                return _QueueCard(
                  entry: entry,
                  onMarkReady: () => _markReady(entry),
                  onNotify: () => _notifyAndDeliver(entry),
                  onNotifySms: () => _notifyAndDeliver(entry, forceSms: true),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCapture,
        icon: const Icon(Icons.camera_alt),
        label: const Text('Plaka Al'),
      ),
    );
  }
}

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Kuyrukta araç yok.\nYeni araç eklemek için aşağıdaki\n'
          '"Plaka Al" butonuna dokunun.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Colors.black54),
        ),
      ),
    );
  }
}

class _QueueCard extends StatelessWidget {
  final QueueEntry entry;
  final VoidCallback onMarkReady;
  final VoidCallback onNotify;
  final VoidCallback onNotifySms;

  const _QueueCard({
    required this.entry,
    required this.onMarkReady,
    required this.onNotify,
    required this.onNotifySms,
  });

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('HH:mm').format(entry.createdAt);
    final statusInfo = _statusInfo(entry.status);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.plate,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: statusInfo.color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          statusInfo.label,
                          style: TextStyle(
                            color: statusInfo.color,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Giriş: $timeStr',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (entry.status == QueueStatus.inQueue)
              ElevatedButton(
                onPressed: onMarkReady,
                style: ElevatedButton.styleFrom(minimumSize: const Size(110, 48)),
                child: const Text('Hazır'),
              )
            else if (entry.status == QueueStatus.ready)
              GestureDetector(
                onLongPress: onNotifySms,
                child: ElevatedButton(
                  onPressed: onNotify,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(110, 48),
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Bildir'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  ({String label, Color color}) _statusInfo(QueueStatus status) {
    switch (status) {
      case QueueStatus.inQueue:
        return (label: 'YIKANIYOR', color: Colors.orange);
      case QueueStatus.ready:
        return (label: 'HAZIR', color: Colors.blue);
      case QueueStatus.delivered:
        return (label: 'TESLİM EDİLDİ', color: Colors.green);
    }
  }
}