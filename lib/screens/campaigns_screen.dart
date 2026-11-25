import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/campaign.dart';
import '../services/campaign_service.dart';
import '../services/database_service.dart';

/// Kampanya yönetim ekranı: hazır şablonlardan tek dokunuşla kampanya
/// oluşturma, tarih aralığı / sadakat (ziyaret bazlı) kampanyalar ve
/// TELEFON NUMARASI bazlı kampanya takibi (bir kişinin birden fazla plakası
/// olabileceği için ziyaret sayısı plaka değil telefon numarasına göre
/// toplanır).
class CampaignsScreen extends StatefulWidget {
  const CampaignsScreen({super.key});

  @override
  State<CampaignsScreen> createState() => _CampaignsScreenState();
}

class _CampaignsScreenState extends State<CampaignsScreen> {
  final _svc = CampaignService.instance;
  final _db = DatabaseService.instance;
  bool _loading = true;
  List<PhoneCampaignProgress> _tracking = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await _svc.load();
    final tracking = await _db.getCampaignTrackingList();
    if (!mounted) return;
    setState(() {
      _tracking = tracking;
      _loading = false;
    });
  }

  Future<void> _openEditor({Campaign? existing, CampaignTemplate? template}) async {
    final titleCtrl =
        TextEditingController(text: existing?.title ?? template?.title ?? '');
    final descCtrl = TextEditingController(
      text: existing?.description ?? template?.description ?? '',
    );
    final visitThresholdCtrl = TextEditingController(
      text: (existing?.visitThreshold ?? template?.visitThreshold)?.toString() ?? '',
    );
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
                const Divider(height: 24),
                const Text(
                  'Sadakat / Ziyaret Bazlı (opsiyonel)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Doldurulursa, bir TELEFON NUMARASI (o numaraya kayıtlı tüm '
                  'plakalar birlikte sayılır) tam olarak bu sayıda geldiğinde '
                  '(ör. 6 → her 6. yıkamada) kampanya otomatik devreye girer ve '
                  'mesajlarda "X/Y yıkama" şeklinde ilerleme gösterilir. Boş '
                  'bırakılırsa yukarıdaki tarih aralığı/aktif anahtarıyla '
                  'çalışan klasik kampanya olur.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: visitThresholdCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Her kaç yıkamada bir',
                    hintText: 'Örn: 6',
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

    final parsedThreshold = int.tryParse(visitThresholdCtrl.text.trim());
    final visitThreshold =
        (parsedThreshold != null && parsedThreshold > 0) ? parsedThreshold : null;

    if (existing == null) {
      await _svc.add(Campaign(
        title: titleCtrl.text.trim(),
        description: descCtrl.text.trim(),
        startDate: start,
        endDate: end,
        createdAt: DateTime.now(),
        visitThreshold: visitThreshold,
      ));
    } else {
      await _svc.update(existing.copyWith(
        title: titleCtrl.text.trim(),
        description: descCtrl.text.trim(),
        startDate: start,
        endDate: end,
        clearStartDate: start == null,
        clearEndDate: end == null,
        visitThreshold: visitThreshold,
        clearVisitThreshold: visitThreshold == null,
      ));
    }
    if (mounted) await _load();
  }

  void _showTemplatePicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Hazır Şablonlar',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Birini seçin, düzenleyicide istediğiniz gibi değiştirip kaydedin.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            ...CampaignTemplate.all.map((t) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      t.visitThreshold != null ? Icons.loyalty : Icons.campaign_outlined,
                      color: Colors.indigo,
                    ),
                    title: Text(t.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(t.description),
                    onTap: () {
                      Navigator.pop(ctx);
                      _openEditor(template: t);
                    },
                  ),
                )),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Kampanyalar'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Kampanyalar', icon: Icon(Icons.campaign_outlined)),
              Tab(text: 'Takip', icon: Icon(Icons.timeline)),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _showTemplatePicker,
          icon: const Icon(Icons.add),
          label: const Text('Yeni / Şablon'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _buildCampaignList(),
                  _buildTrackingList(),
                ],
              ),
      ),
    );
  }

  Widget _buildCampaignList() {
    final campaigns = _svc.all;
    if (campaigns.isEmpty) {
      return const Center(
        child: Text('Henüz kampanya yok. + ile hazır şablonlardan ekleyin.'),
      );
    }
    return ListView.separated(
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
                if (c.isVisitBased)
                  Text(
                    '🔁 Her ${c.visitThreshold}. yıkamada bir (telefon bazlı)',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.deepPurple,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else
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
                  return;
                } else if (v == 'delete') {
                  await _svc.remove(c.id!);
                }
                if (mounted) await _load();
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
    );
  }

  Widget _buildTrackingList() {
    final activeCampaign = _svc.activeVisitBasedCampaign;
    if (_tracking.isEmpty) {
      return const Center(child: Text('Henüz takip edilecek müşteri yok.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
      itemCount: _tracking.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              activeCampaign != null
                  ? 'Aktif sadakat kampanyası: "${activeCampaign.title}" · Her ${activeCampaign.visitThreshold} yıkamada 1'
                  : 'Aktif sadakat (ziyaret bazlı) kampanya yok. Takip listesi yine de toplam yıkama '
                      'sayısını gösterir.',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          );
        }
        final p = _tracking[i - 1];
        final threshold = activeCampaign?.visitThreshold;
        final progress = threshold != null
            ? (p.visitCount % threshold == 0 && p.visitCount > 0 ? threshold : p.visitCount % threshold)
            : null;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text(p.plates.join(', '), style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.phone),
                const SizedBox(height: 6),
                if (threshold != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: progress! / threshold,
                          minHeight: 8,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$progress/$threshold yıkama',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  )
                else
                  Text('${p.visitCount} toplam yıkama', style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        );
      },
    );
  }
}
