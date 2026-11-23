import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/campaign.dart';
import '../services/campaign_service.dart';

/// Yeni, gerçek kampanya yönetim ekranı: başlık + açıklama + opsiyonel
/// tarih aralığı. Eski sistemde tek bir düz metin alanı vardı ve
/// (shop_config.dart'taki escape bug'ı yüzünden) mesajlara hiç düzgün
/// yansımıyordu. Artık:
///   - Birden fazla kampanya kayıtlı tutulabilir (geçmiş kampanyalar
///     silinmeden tekrar aktif edilebilir)
///   - Tarih aralığı verilirse süresi dolan kampanya OTOMATİK olarak
///     mesajlara eklenmeyi bırakır (manuel "aktif" işaretli kalsa bile)
///   - Aynı anda sadece bir kampanya aktif olabilir
class CampaignsScreen extends StatefulWidget {
  const CampaignsScreen({super.key});

  @override
  State<CampaignsScreen> createState() => _CampaignsScreenState();
}

class _CampaignsScreenState extends State<CampaignsScreen> {
  final _svc = CampaignService.instance;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await _svc.load();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _openEditor({Campaign? existing}) async {
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    DateTime? start = existing?.startDate;
    DateTime? end = existing?.endDate;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Yeni Kampanya' : 'Kampanyayı Düzenle'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Başlık'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Açıklama (mesajlarda görünecek metin)',
                    hintText: 'Örn: 5. yıkamada %50 indirim',
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: start ?? DateTime.now(),
                            firstDate: DateTime.now().subtract(const Duration(days: 365)),
                            lastDate: DateTime.now().add(const Duration(days: 730)),
                          );
                          if (picked != null) setDialogState(() => start = picked);
                        },
                        child: Text(
                          start == null
                              ? 'Başlangıç (opsiyonel)'
                              : DateFormat('dd.MM.yyyy').format(start!),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: end ?? DateTime.now(),
                            firstDate: DateTime.now().subtract(const Duration(days: 365)),
                            lastDate: DateTime.now().add(const Duration(days: 730)),
                          );
                          if (picked != null) setDialogState(() => end = picked);
                        },
                        child: Text(
                          end == null ? 'Bitiş (opsiyonel)' : DateFormat('dd.MM.yyyy').format(end!),
                        ),
                      ),
                    ),
                  ],
                ),
                if (start != null || end != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => setDialogState(() {
                        start = null;
                        end = null;
                      }),
                      child: const Text('Tarihleri Temizle (Süresiz)'),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
            ElevatedButton(
              onPressed: () {
                if (titleCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );

    if (saved != true) return;

    if (existing == null) {
      await _svc.add(Campaign(
        title: titleCtrl.text.trim(),
        description: descCtrl.text.trim(),
        startDate: start,
        endDate: end,
        createdAt: DateTime.now(),
      ));
    } else {
      await _svc.update(existing.copyWith(
        title: titleCtrl.text.trim(),
        description: descCtrl.text.trim(),
        startDate: start,
        endDate: end,
        clearStartDate: start == null,
        clearEndDate: end == null,
      ));
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final campaigns = _svc.all;

    return Scaffold(
      appBar: AppBar(title: const Text('Kampanyalar')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : campaigns.isEmpty
              ? const Center(child: Text('Henüz kampanya yok. + ile ekleyin.'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                  itemCount: campaigns.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final c = campaigns[i];
                    final expired = !c.isCurrentlyValid;
                    return Card(
                      color: c.isEffective ? Colors.green.withValues(alpha: 0.08) : null,
                      child: ListTile(
                        title: Text(
                          c.title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            decoration: expired ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.description),
                            const SizedBox(height: 4),
                            Text(
                              c.startDate == null && c.endDate == null
                                  ? 'Süresiz'
                                  : '${c.startDate != null ? DateFormat('dd.MM.yyyy').format(c.startDate!) : '...'} '
                                      '→ ${c.endDate != null ? DateFormat('dd.MM.yyyy').format(c.endDate!) : '...'}',
                              style: const TextStyle(fontSize: 12, color: Colors.black54),
                            ),
                            if (c.isEffective)
                              const Text(
                                '✅ Şu an mesajlara ekleniyor',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            else if (c.active && expired)
                              const Text(
                                '⚠️ Aktif ama süresi doldu',
                                style: TextStyle(fontSize: 12, color: Colors.orange),
                              ),
                          ],
                        ),
                        isThreeLine: true,
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) async {
                            if (v == 'activate') {
                              await _svc.setActive(c.id!);
                            } else if (v == 'deactivate') {
                              await _svc.deactivateAll();
                            } else if (v == 'edit') {
                              await _openEditor(existing: c);
                            } else if (v == 'delete') {
                              await _svc.remove(c.id!);
                            }
                            if (mounted) setState(() {});
                          },
                          itemBuilder: (context) => [
                            if (!c.active)
                              const PopupMenuItem(value: 'activate', child: Text('Aktif Yap')),
                            if (c.active)
                              const PopupMenuItem(value: 'deactivate', child: Text('Pasif Yap')),
                            const PopupMenuItem(value: 'edit', child: Text('Düzenle')),
                            const PopupMenuItem(value: 'delete', child: Text('Sil')),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
