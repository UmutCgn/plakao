import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/vehicle.dart';
import '../services/database_service.dart';
import '../services/messaging_service.dart';

/// Rehber: daha önce gelmiş tüm müşterilerin plaka + telefon + ziyaret
/// bilgilerini listeler ("daha önce yıkanan plakaların noları"), hızlı
/// WhatsApp/SMS imkânı sunar.
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
  }

  void _applyFilter() {
    final q = _searchCtrl.text.trim().toUpperCase();
    setState(() {
      _filtered = q.isEmpty
          ? _all
          : _all
              .where((c) =>
                  c.customer.plate.contains(q) || c.customer.phone.contains(q))
              .toList();
    });
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
                  labelText: 'Plaka veya telefon ara',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _filtered.isEmpty
                      ? const Center(child: Text('Kayıtlı müşteri bulunamadı.'))
                      : ListView.separated(
                          itemCount: _filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final info = _filtered[i];
                            return ListTile(
                              title: Text(
                                info.customer.plate,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.1,
                                ),
                              ),
                              subtitle: Text(
                                '${info.customer.phone}\n'
                                '${info.visitCount}. ziyaret · Son: ${DateFormat('dd.MM.yyyy').format(info.lastVisit)}',
                              ),
                              isThreeLine: true,
                              trailing: Row(
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
