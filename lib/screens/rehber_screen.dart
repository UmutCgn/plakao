import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/vehicle.dart';
import '../services/database_service.dart';
import '../services/messaging_service.dart';

/// Rehber: daha önce gelmiş tüm müşterilerin plaka + telefon + ziyaret
/// bilgilerini kart halinde listeler. Her kartta "Düzenle" butonu ile isim
/// girme, telefon değiştirme ve kaydı silme gibi işlemler tek bir yerden
/// yapılabilir.
class RehberScreen extends StatefulWidget {
  const RehberScreen({super.key});

  @override
  State<RehberScreen> createState() => _RehberScreenState();
}

class _RehberScreenState extends State<RehberScreen> {
  final _db = DatabaseService.instance;
  List<CustomerVisitInfo> _all = [];
  List<CustomerVisitInfo> _filtered = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await _db.getCustomerDirectory();
    if (!mounted) return;
    setState(() {
      _all = data;
      _filtered = data;
      _loading = false;
    });
    _applyFilter();
  }

  void _applyFilter() {
    final q = _searchCtrl.text.trim().toUpperCase();
    setState(() {
      _filtered = q.isEmpty
          ? _all
          : _all
              .where((c) =>
                  c.customer.plate.contains(q) ||
                  c.customer.phone.contains(q) ||
                  (c.customer.name?.toUpperCase().contains(q) ?? false))
              .toList();
    });
  }

  Future<void> _openEditSheet(CustomerVisitInfo info) async {
    final nameCtrl = TextEditingController(text: info.customer.name ?? '');
    final phoneCtrl = TextEditingController(text: info.customer.phone);

    final action = await showModalBottomSheet<String>(
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
                info.customer.plate,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Müşteri Adı (opsiyonel)',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Telefon Numarası',
                  prefixIcon: Icon(Icons.phone),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(ctx, 'delete'),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Sil'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(ctx, 'save'),
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Kaydet'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    if (action == 'save') {
      final newPhone = phoneCtrl.text.trim();
      if (newPhone.isNotEmpty && MessagingService.isValidPhone(newPhone)) {
        await _db.updateCustomerPhone(info.customer.plate, newPhone);
      }
      await _db.updateCustomerName(info.customer.plate, nameCtrl.text.trim());
      await _load();
    } else if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Kaydı Sil'),
          content: Text(
            '${info.customer.plate} rehberden silinsin mi? (Geçmiş yıkama '
            'istatistikleri etkilenmez.)',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Sil'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await _db.deleteCustomer(info.customer.plate);
        await _load();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rehber')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Plaka, isim veya telefon ara',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _filtered.isEmpty
                      ? const Center(child: Text('Kayıtlı müşteri bulunamadı.'))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                          itemCount: _filtered.length,
                          itemBuilder: (context, i) {
                            final info = _filtered[i];
                            final name = info.customer.name;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                info.customer.plate,
                                                style: const TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: 1.1,
                                                ),
                                              ),
                                              if (name != null) ...[
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    name,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      color: Colors.black54,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(info.customer.phone),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${info.visitCount}. ziyaret · Son: ${DateFormat('dd.MM.yyyy').format(info.lastVisit)}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.black54,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.chat, color: Colors.green),
                                              tooltip: 'WhatsApp',
                                              onPressed: () => MessagingService.sendWhatsApp(
                                                info.customer.phone,
                                                'Merhaba! ${info.customer.plate} plakalı aracınızla ilgili size ulaşıyoruz.',
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.sms_outlined),
                                              tooltip: 'SMS',
                                              onPressed: () => MessagingService.sendSms(
                                                info.customer.phone,
                                                'Merhaba! ${info.customer.plate} plakalı aracınızla ilgili size ulaşıyoruz.',
                                              ),
                                            ),
                                          ],
                                        ),
                                        OutlinedButton.icon(
                                          onPressed: () => _openEditSheet(info),
                                          style: OutlinedButton.styleFrom(
                                            minimumSize: const Size(0, 36),
                                            padding: const EdgeInsets.symmetric(horizontal: 12),
                                          ),
                                          icon: const Icon(Icons.edit_outlined, size: 16),
                                          label: const Text('Düzenle', style: TextStyle(fontSize: 13)),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
