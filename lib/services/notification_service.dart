import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// "Araç Bekleme Süresi Uyarısı" için tek noktadan yerel bildirim yönetimi.
///
/// NOT: Bu servis flutter_local_notifications paketini kullanır. Projeye
/// eklemek için:
///   1) pubspec.yaml -> dependencies altına:
///        flutter_local_notifications: ^18.0.1
///   2) Android: android/app/src/main/AndroidManifest.xml içine (henüz
///      yoksa) bildirim izni ve varsayılan ikon ayarı eklenmeli (Android 13+
///      için POST_NOTIFICATIONS izni gereklidir, aşağıdaki init() bunu
///      çalışma zamanında zaten ister).
///   3) iOS: Bildirimlere izin isteği init() içinde otomatik yapılır.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    try {
      await _plugin.initialize(initSettings);

      // Android 13+ (API 33+) için çalışma zamanı bildirim izni.
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.requestNotificationsPermission();

      final iosImpl = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      await iosImpl?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (_) {
      // Bildirim altyapısı kurulamazsa (ör. henüz pubspec/manifest
      // ayarlanmadıysa) sessizce yut; uygulamanın geri kalanı çalışmaya
      // devam etsin.
      _initialized = false;
    }
  }

  /// Belirli bir süreden uzun bekleyen araç için uyarı bildirimi gösterir.
  /// [entryId] bildirim id'si olarak kullanılır, böylece aynı araç için
  /// ikinci kez çağrılırsa önceki bildirimin üzerine yazar (spam yapmaz).
  Future<void> showWaitWarning({
    required int entryId,
    required String plate,
    required int waitedMinutes,
  }) async {
    if (!_initialized) await init();

    const androidDetails = AndroidNotificationDetails(
      'queue_wait_warning',
      'Araç Bekleme Uyarısı',
      channelDescription:
          'Kuyrukta belirlenen süreden uzun bekleyen araçlar için uyarı.',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    try {
      await _plugin.show(
        entryId,
        'Araç Uzun Süredir Bekliyor',
        '$plate plakalı araç $waitedMinutes dakikadır kuyrukta bekliyor.',
        details,
      );
    } catch (_) {
      // Bildirim gösterilemezse (izin yok, altyapı eksik vb.) sessiz geç;
      // uygulama akışı bundan etkilenmemeli.
    }
  }
}