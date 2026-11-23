import 'dart:convert';
import 'package:http/http.dart' as http;

class DailyForecast {
  final DateTime date;
  final double rainProbability; // 0-100
  final double maxTempC;

  const DailyForecast({
    required this.date,
    required this.rainProbability,
    required this.maxTempC,
  });
}

/// Open-Meteo ücretsiz API'si (API key gerekmez). Deneysel "Akıllı Talep
/// Tahmini" özelliği tarafından kullanılır.
class WeatherService {
  WeatherService._();
  static final WeatherService instance = WeatherService._();

  Future<List<DailyForecast>> fetch3DayForecast({
    required double lat,
    required double lon,
  }) async {
    final uri = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=$lat&longitude=$lon'
      '&daily=precipitation_probability_max,temperature_2m_max'
      '&timezone=auto&forecast_days=3',
    );

    final res = await http.get(uri).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) {
      throw Exception('Hava durumu alınamadı (HTTP ${res.statusCode})');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final daily = data['daily'] as Map<String, dynamic>;
    final dates = (daily['time'] as List).cast<String>();
    final rain = daily['precipitation_probability_max'] as List;
    final temps = daily['temperature_2m_max'] as List;

    return List.generate(dates.length, (i) {
      return DailyForecast(
        date: DateTime.parse(dates[i]),
        rainProbability: (rain[i] as num).toDouble(),
        maxTempC: (temps[i] as num).toDouble(),
      );
    });
  }
}
