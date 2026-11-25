import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/shop_config.dart';
import '../models/vehicle.dart';
import '../services/database_service.dart';
import '../services/messaging_service.dart';
import '../services/notification_service.dart';
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

  /// DENEYSEL "⏱️ Akıllı Bekleme Tahmini" için geçmişten hesaplanan ortalama
  /// yıkama süresi (dakika). Ayarlardan özellik kapalıysa kullanılmaz.
  double _avgWashMinutes = 20;

  /// "Araç Bekleme Süresi Uyarısı" için periyodik kontrol zamanlayıcısı.
  Timer? _waitCheckTimer;

  @override
  void initState() {
    super.initState();
    _refresh();
    // Uygulama açıkken her 30 saniyede bir kuyruğu kontrol edip, belirlenen
    // süreden uzun bekleyen araç varsa bildirim gönderir. (Bkz. Ayarlar >
    // Gelişmiş Ayarlar > Araç Bekleme Süresi Uyarısı.)
    _waitCheckTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkWaitTimes(),
    );
  }

  @override
  void dispose() {
    _waitCheckTimer?.cancel();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _queueFuture = _db.getActiveQueue();
    });
    if (SettingsService.instance.current.smartWaitEstimateEnabled) {
      _db.getAverageWashMinutes().then((value) {
        if (mounted) setState(() => _avgWashMinutes = value);
      });
    }
    _checkWaitTimes();
  }

  /// Kuyrukta (yıkanıyor durumunda) ayarlarda belirlenen süreden uzun
  /// bekleyen araçlar için tek seferlik yerel bildirim gönderir. Aynı araç
  /// için bildirim [QueueEntry.waitWarnedAt] ile işaretlenip tekrar atılmaz.
  Future<void> _checkWaitTimes() async {
    final settings = SettingsService.instance.current;
    if (!settings.queueWaitWarningEnabled) return;

    final threshold = Duration(minutes: settings.queueWaitWarningMinutes);
    final queue = await _db.getActiveQueue();
    final now = DateTime.now();

    for (final entry in queue) {
      if (entry.status != QueueStatus.inQueue) continue;
      if (entry.waitWarnedAt != null) continue;

      final waited = now.difference(entry.createdAt);
      if (waited >= threshold) {
        await NotificationService.instance.showWaitWarning(
          entryId: entry.id!,
          plate: entry.plate,
          waitedMinutes: waited.inMinutes,
        );
        await _db.markWaitWarned(entry.id!);
      }
    }
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

  /// "Ücret Belirle" butonu: hazır fiyat listesinden seçim ya da elle
  /// girilen özel tutar. Her araç farklı fiyata yıkanabildiği için kayıt
  /// bazında saklanır (bkz. QueueEntry.price / İstatistikler ekranı ciro).
  Future<void> _setPrice(QueueEntry entry) async {
    final presets = SettingsService.instance.current.pricePresets;
    final customCtrl = TextEditingController(
      text: entry.price != null ? entry.price!.toStringAsFixed(0) : '',
    );

    final result = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${entry.plate} - Ücret Belirle',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Hazır ücretlerden birine dokunun:',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 14),
              // Büyük, tek dokunuşla seçilebilir hazır ücret butonları.
              // Küçük chip'lerin tıklanması zor olduğu için (özellikle
              // dükkanda hızlı kullanımda) her biri tam genişlikte ve
              // büyük punto ile gösterilir.
              ...presets.map((p) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SizedBox(
                    width: double.infinity,
                    height: 64,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, p.price),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo.withValues(alpha: 0.08),
                        foregroundColor: Colors.indigo,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            p.label,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${p.price.toStringAsFixed(0)} ₺',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 6),
              const Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      'ya da özel ücret',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: customCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Özel Ücret (₺)',
                        prefixIcon: Icon(Icons.payments_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 110,
                    child: ElevatedButton(
                      onPressed: () {
                        final value = double.tryParse(
                          customCtrl.text.trim().replaceAll(',', '.'),
                        );
                        if (value == null || value <= 0) return;
                        Navigator.pop(ctx, value);
                      },
                      child: const Text('Kaydet'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    if (result == null) return;
    await _db.setEntryPrice(entry.id!, result);
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

    // Sadakat/kampanya hesaplaması artık TELEFON NUMARASI bazlı: bir kişinin
    // birden fazla plakası olabileceği için ziyaret sayısı o numaranın tüm
    // plakalardaki toplam yıkama sayısına göre hesaplanır (ör. "her 6
    // yıkamada 1 ücretsiz").
    final visitCount =
        await _db.getVisitCountForEntry(plate: entry.plate, phone: phone);

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
          final estimateEnabled =
              SettingsService.instance.current.smartWaitEstimateEnabled;
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
              itemCount: queue.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final entry = queue[index];
                // Bu aracın önünde hala "yıkanıyor" durumunda kaç araç
                // olduğu (⏱️ Akıllı Bekleme Tahmini için).
                final aheadCount = queue
                    .sublist(0, index)
                    .where((e) => e.status == QueueStatus.inQueue)
                    .length;
                DateTime? estimatedReadyAt;
                if (estimateEnabled && entry.status == QueueStatus.inQueue) {
                  estimatedReadyAt = DateTime.now().add(
                    Duration(
                      minutes:
                          (_avgWashMinutes * (aheadCount + 1)).round(),
                    ),
                  );
                }
                return _QueueCard(
                  entry: entry,
                  estimatedReadyAt: estimatedReadyAt,
                  onMarkReady: () => _markReady(entry),
                  onNotifyWhatsapp: () => _notifyAndDeliver(entry, useWhatsApp: true),
                  onNotifySms: () => _notifyAndDeliver(entry, useWhatsApp: false),
                  onSetPrice: () => _setPrice(entry),
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
  final VoidCallback onSetPrice;

  /// DENEYSEL "⏱️ Akıllı Bekleme Tahmini": açıksa ve araç hala kuyruktaysa
  /// dolu, aksi halde null. HomeScreen tarafından hesaplanır.
  final DateTime? estimatedReadyAt;

  const _QueueCard({
    required this.entry,
    required this.onMarkReady,
    required this.onNotifyWhatsapp,
    required this.onNotifySms,
    required this.onSetPrice,
    this.estimatedReadyAt,
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
                  // ⏱️ Akıllı Bekleme Tahmini (deneysel): kuyrukta önündeki
                  // araç sayısı ve geçmiş ortalama yıkama süresine göre
                  // tahmini hazır olma saati.
                  if (estimatedReadyAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.timer_outlined,
                              size: 13, color: Colors.black54),
                          const SizedBox(width: 4),
                          Text(
                            'Tahmini hazır: ${DateFormat('HH:mm').format(estimatedReadyAt!)}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Colors.black54,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // "Ücret Belirle" butonu: fiyat girilene kadar büyük ve
                // belirgin; fiyat girilince aynı yerde seçilen ücreti
                // gösteren bir butona dönüşür (tekrar dokunarak
                // değiştirilebilir).
                SizedBox(
                  width: 140,
                  height: 44,
                  child: entry.price == null
                      ? ElevatedButton.icon(
                          onPressed: onSetPrice,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.zero,
                            textStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          icon: const Icon(Icons.price_change_outlined, size: 18),
                          label: const Text('Ücret Belirle'),
                        )
                      : OutlinedButton.icon(
                          onPressed: onSetPrice,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.indigo,
                            side: const BorderSide(color: Colors.indigo),
                            padding: EdgeInsets.zero,
                            textStyle: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          label: Text('${entry.price!.toStringAsFixed(0)} ₺'),
                        ),
                ),
                const SizedBox(height: 6),
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