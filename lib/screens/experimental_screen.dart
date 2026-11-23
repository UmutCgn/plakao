import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/database_service.dart';
import '../services/settings_service.dart';
import '../services/weather_service.dart';

/// DENEYSEL ÖZELLİK: Akıllı Talep Tahmini.
///
/// Önümüzdeki 3 günün yağmur ihtimaline (Open-Meteo, ücretsiz, API key
/// gerekmez) ve geçmiş haftaların aynı gün ortalamasına bakarak "yarın ne
/// kadar yoğun olur, hangi gün araç yıkamak için daha uygun" şeklinde basit
/// ama pratik bir tahmin sunar. Yağmurlu günlerde yıkama verimi düşük
/// olacağından personel planlaması ve müşteri yönlendirmesi için kullanışlı.
///
/// Ayarlar > "🧪 Akıllı Talep Tahmini" anahtarı AÇIKKEN ana ekranın sağ
/// üstündeki ⋮ menüsünden bu sayfaya erişilir; KAPATILINCA o menü tamamen
/// kaybolur (bkz. home_screen.dart).
class ExperimentalScreen extends StatefulWidget {
  const ExperimentalScreen({super.key});

  @override
  State<ExperimentalScreen> createState() => _ExperimentalScreenState();
}

class _ExperimentalScreenState extends State<ExperimentalScreen> {
  final _db = DatabaseService.instance;
  Future<List<DailyForecast>>? _forecastFuture;
  Map<int, double> _weekdayAverage = {}; // 1=Pzt..7=Paz -> ortalama araç sayısı

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = SettingsService.instance.current;
    setState(() {
      _forecastFuture = WeatherService.instance.fetch3DayForecast(
        lat: settings.shopLat,
        lon: settings.shopLon,
      );
    });
    await _computeWeekdayAverage();
  }

  Future<void> _computeWeekdayAverage() async {
    final entries = await _db.getAllQueueEntries();
    final byDay = <String, int>{};

    for (final e in entries) {
      final key = DateFormat('yyyy-MM-dd').format(e.createdAt);
      byDay[key] = (byDay[key] ?? 0) + 1;
    }

    final buckets = <int, List<int>>{};
    byDay.forEach((key, count) {
      final weekday = DateTime.parse(key).weekday;
      buckets.putIfAbsent(weekday, () => []).add(count);
    });

    final avg = <int, double>{};
    buckets.forEach((weekday, counts) {
      avg[weekday] = counts.reduce((a, b) => a + b) / counts.length;
    });

    if (!mounted) return;
    setState(() => _weekdayAverage = avg);
  }

  String _weekdayName(int w) => const [
        'Pazartesi',
        'Salı',
        'Çarşamba',
        'Perşembe',
        'Cuma',
        'Cumartesi',
        'Pazar',
      ][w - 1];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🧪 Akıllı Talep Tahmini')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: FutureBuilder<List<DailyForecast>>(
          future: _forecastFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const SizedBox(height: 40),
                  const Icon(Icons.cloud_off, size: 48, color: Colors.black38),
                  const SizedBox(height: 12),
                  Text(
                    'Hava durumu alınamadı: ${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'İnternet bağlantınızı kontrol edin. (Ayarlar\'dan dükkan '
                    'konumunu / enlem-boylamı değiştirebilirsiniz.)',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ],
              );
            }

            final days = snapshot.data ?? [];
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Bu özellik deneyseldir; tahminler kesin değildir, sadece '
                  'planlamaya yardımcı bir fikir verir.',
                  style: TextStyle(color: Colors.black54, fontSize: 12),
                ),
                const SizedBox(height: 16),
                ...days.map((d) {
                  final expectedCount = _weekdayAverage[d.date.weekday];
                  final rainy = d.rainProbability >= 50;
                  return Card(
                    child: ListTile(
                      leading: Icon(
                        rainy ? Icons.umbrella : Icons.wb_sunny,
                        color: rainy ? Colors.blueGrey : Colors.orange,
                        size: 32,
                      ),
                      title: Text(
                        '${DateFormat('dd.MM.yyyy').format(d.date)} (${_weekdayName(d.date.weekday)})',
                      ),
                      subtitle: Text(
                        'Yağmur ihtimali: %${d.rainProbability.toStringAsFixed(0)} · '
                        'Maks ${d.maxTempC.toStringAsFixed(0)}°C'
                        '${expectedCount != null ? '\nGeçmişe göre beklenen araç: ~${expectedCount.toStringAsFixed(0)}' : ''}',
                      ),
                      isThreeLine: expectedCount != null,
                      trailing: rainy
                          ? const Text(
                              'Düşük verim\nolabilir',
                              textAlign: TextAlign.end,
                              style: TextStyle(fontSize: 11, color: Colors.redAccent),
                            )
                          : const Text(
                              'Yıkama için\nuygun',
                              textAlign: TextAlign.end,
                              style: TextStyle(fontSize: 11, color: Colors.green),
                            ),
                    ),
                  );
                }),
              ],
            );
          },
        ),
      ),
    );
  }
}
