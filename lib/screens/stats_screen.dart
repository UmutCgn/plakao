import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/vehicle.dart';
import '../services/database_service.dart';
import '../services/settings_service.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final _db = DatabaseService.instance;
  final _campaignController = TextEditingController();

  bool _loading = true;
  List<QueueEntry> _allEntries = const [];

  @override
  void initState() {
    super.initState();
    _campaignController.text = SettingsService.instance.current.activeCampaign;
    _loadData();
  }

  @override
  void dispose() {
    _campaignController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final entries = await _db.getAllQueueEntries();

    if (!mounted) return;
    setState(() {
      _allEntries = entries;
      _loading = false;
    });
  }

  Iterable<QueueEntry> get _washedEntries => _allEntries.where(
        (e) =>
            e.status == QueueStatus.ready ||
            e.status == QueueStatus.delivered,
      );

  int get _todayWashedCount {
    final now = DateTime.now();
    return _washedEntries.where((e) {
      final d = e.createdAt;
      return d.year == now.year && d.month == now.month && d.day == now.day;
    }).length;
  }

  int get _weekWashedCount {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final sevenDaysAgo = startOfToday.subtract(const Duration(days: 6));
    return _washedEntries
        .where((e) => !e.createdAt.isBefore(sevenDaysAgo))
        .length;
  }

  int get _monthWashedCount {
    final now = DateTime.now();
    return _washedEntries
        .where((e) => e.createdAt.year == now.year && e.createdAt.month == now.month)
        .length;
  }

  List<({String label, int count})> get _last7DaysBreakdown {
    final now = DateTime.now();
    return List.generate(7, (idx) {
      final day = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: 6 - idx));
      final count = _washedEntries.where((e) {
        final d = e.createdAt;
        return d.year == day.year && d.month == day.month && d.day == day.day;
      }).length;
      return (
        label: DateFormat('dd.MM').format(day),
        count: count,
      );
    });
  }

  Future<void> _addOrActivateCampaign() async {
    final text = _campaignController.text.trim();
    if (text.isEmpty) return;

    final current = SettingsService.instance.current;
    final updatedList = [
      text,
      ...current.campaigns.where((c) => c.toLowerCase() != text.toLowerCase()),
    ];

    await SettingsService.instance.save(
      current.copyWith(
        activeCampaign: text,
        campaigns: updatedList,
      ),
    );

    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Kampanya kaydedildi ve aktif yapıldı.')),
    );
  }

  Future<void> _setActiveCampaign(String campaign) async {
    final current = SettingsService.instance.current;
    _campaignController.text = campaign;
    await SettingsService.instance.save(
      current.copyWith(activeCampaign: campaign),
    );
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _clearActiveCampaign() async {
    final current = SettingsService.instance.current;
    _campaignController.clear();
    await SettingsService.instance.save(
      current.copyWith(activeCampaign: ''),
    );
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _removeCampaign(String campaign) async {
    final current = SettingsService.instance.current;
    final filtered = current.campaigns.where((c) => c != campaign).toList();
    final nextActive =
        current.activeCampaign == campaign ? '' : current.activeCampaign;
    if (nextActive.isEmpty) {
      _campaignController.clear();
    }
    await SettingsService.instance.save(
      current.copyWith(
        campaigns: filtered,
        activeCampaign: nextActive,
      ),
    );
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService.instance.current;
    final days = _last7DaysBreakdown;
    final maxDayCount = days.fold<int>(1, (m, d) => d.count > m ? d.count : m);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Raporlar ve Kampanyalar'),
        actions: [
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
            tooltip: 'Yenile',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Yıkanan Araç Sayıları',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _MetricCard(
                        title: 'Bugün',
                        value: '$_todayWashedCount',
                        color: Colors.indigo,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MetricCard(
                        title: 'Son 7 Gün',
                        value: '$_weekWashedCount',
                        color: Colors.teal,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MetricCard(
                        title: 'Bu Ay',
                        value: '$_monthWashedCount',
                        color: Colors.deepOrange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'Haftalık Rapor (Son 7 Gün)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 10),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: days.map((d) {
                        final ratio = d.count / maxDayCount;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 54,
                                child: Text(
                                  d.label,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: LinearProgressIndicator(
                                    value: ratio,
                                    minHeight: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              SizedBox(
                                width: 28,
                                child: Text(
                                  '${d.count}',
                                  textAlign: TextAlign.end,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.calendar_month),
                    title: const Text('Aylık Yıkanan Araç Raporu'),
                    subtitle: Text(
                      '${DateFormat('yyyy-MM').format(DateTime.now())} döneminde toplam $_monthWashedCount araç yıkandı.',
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Kampanya Yönetimi',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    if (settings.activeCampaign.isNotEmpty)
                      TextButton(
                        onPressed: _clearActiveCampaign,
                        child: const Text('Aktif Kampanyayı Kaldır'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _campaignController,
                  decoration: const InputDecoration(
                    labelText: 'Kampanya Metni',
                    hintText: 'Örn: 5. yıkamada iç-dış yıkama %50 indirim!',
                    prefixIcon: Icon(Icons.local_offer_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: _addOrActivateCampaign,
                  icon: const Icon(Icons.campaign),
                  label: const Text('Kampanya Ekle ve Aktif Yap'),
                ),
                if (settings.activeCampaign.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Card(
                    color: Colors.green.withValues(alpha: 0.10),
                    child: ListTile(
                      leading: const Icon(Icons.check_circle, color: Colors.green),
                      title: const Text('Aktif Kampanya'),
                      subtitle: Text(settings.activeCampaign),
                    ),
                  ),
                ],
                if (settings.campaigns.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ...settings.campaigns.map(
                    (c) => Card(
                      child: ListTile(
                        title: Text(c),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                settings.activeCampaign == c
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                              ),
                              tooltip: 'Aktif Yap',
                              onPressed: () => _setActiveCampaign(c),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Sil',
                              onPressed: () => _removeCampaign(c),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}