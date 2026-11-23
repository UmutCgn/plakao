import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/shop_config.dart';
import '../models/vehicle.dart';
import '../services/database_service.dart';
import '../services/messaging_service.dart';
import '../services/settings_service.dart';
import 'campaigns_screen.dart';
import 'capture_screen.dart';
import 'experimental_screen.dart';
import 'rehber_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';

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

  /// Tek tuşla bildirim. İki ayrı buton (WhatsApp / SMS) üzerinden çağrılır;
  /// [useWhatsApp] true ise WhatsApp, false ise SMS ile gönderir — kullanıcı
  /// hangi kanalı seçtiyse o kesin olarak denenir (sessiz bir diğerine düşme
  /// yoktur, çünkü seçim zaten kullanıcıya ait).
  Future<void> _notifyAndDeliver(QueueEntry entry, {required bool useWhatsApp}) async {
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

    // Sadakat/kampanya hesaplaması bu aracın şu ana kadarki ziyaret sayısına
    // göre yapılır (ör. "her 6 yıkamada 1 ücretsiz").
    final visitCount = await _db.getVisitCount(entry.plate);

    final settings = SettingsService.instance.current;
    final message = settings.messageTemplate.trim().isNotEmpty
        ? settings.buildCompletionMessage(entry.plate, visitCount: visitCount)
        : ShopConfig.readyMessage(entry.plate, visitCount: visitCount);

    final ok = useWhatsApp
        ? await MessagingService.sendWhatsApp(phone, message)
        : await MessagingService.sendSms(phone, message);

    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              useWhatsApp
                  ? 'WhatsApp açılamadı. Numarayı kontrol edin.'
                  : 'SMS uygulaması açılamadı. Numarayı kontrol edin.',
            ),
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
    final experimentalOn =
        SettingsService.instance.current.experimentalFeatureEnabled;

    return Scaffold(
      appBar: AppBar(
        title: Text('$shopName - Kuyruk'),
        centerTitle: true,
      ),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                ),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Text(
                    shopName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Ayarlar'),
                onTap: () {
                  Navigator.pop(context);
                  _openSettings();
                },
              ),
              ListTile(
                leading: const Icon(Icons.bar_chart),
                title: const Text('İstatistikler'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const StatsScreen()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.campaign),
                title: const Text('Kampanyalar'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CampaignsScreen()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.contacts),
                title: const Text('Rehber'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RehberScreen()),
                  );
                },
              ),
              // Deneysel özellik kapalıyken bu öğe HİÇ görünmez; Ayarlar >
              // Gelişmiş Ayarlar'dan açıldığı anda belirir, kapatılınca
              // kaybolur. Önceden sağ üstteki ⋮ menüsündeydi, artık sol
              // menüde (three-dot kaldırıldı).
              if (experimentalOn)
                ListTile(
                  leading: const Icon(Icons.science_outlined),
                  title: const Text('🧪 Akıllı Talep Tahmini'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ExperimentalScreen()),
                    );
                  },
                ),
            ],
          ),
        ),
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
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
              itemCount: queue.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final entry = queue[index];
                return _QueueCard(
                  entry: entry,
                  onMarkReady: () => _markReady(entry),
                  onNotifyWhatsapp: () => _notifyAndDeliver(entry, useWhatsApp: true),
                  onNotifySms: () => _notifyAndDeliver(entry, useWhatsApp: false),
                );
              },
            ),
          );
        },
      ),
      // "Plaka Al" butonu artık ortada (ne sağda ne solda).
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
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
  final VoidCallback onNotifyWhatsapp;
  final VoidCallback onNotifySms;

  const _QueueCard({
    required this.entry,
    required this.onMarkReady,
    required this.onNotifyWhatsapp,
    required this.onNotifySms,
  });

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('HH:mm').format(entry.createdAt);
    final statusInfo = _statusInfo(entry.status);
    final hasPhone = entry.phone != null && entry.phone!.isNotEmpty;

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
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                  if (!hasPhone)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        '⚠ Telefon yok',
                        style: TextStyle(fontSize: 11, color: Colors.orange),
                      ),
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
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 132,
                    height: 40,
                    child: ElevatedButton.icon(
                      onPressed: onNotifyWhatsapp,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.zero,
                      ),
                      icon: const Icon(Icons.chat, size: 18),
                      label: const Text('WhatsApp'),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: 132,
                    height: 40,
                    child: OutlinedButton.icon(
                      onPressed: onNotifySms,
                      style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                      icon: const Icon(Icons.sms_outlined, size: 18),
                      label: const Text('SMS'),
                    ),
                  ),
                ],
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
