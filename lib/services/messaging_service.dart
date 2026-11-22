import 'package:url_launcher/url_launcher.dart';

/// WhatsApp (wa.me) ve SMS (sms:) uzerinden hazir mesaj gonderme islemlerini
/// tek noktadan yonetir.
class MessagingService {
  /// Turkiye numaralarini (05xx..., 5xx..., +905xx...) 905xxxxxxxxx formatina
  /// normalize eder.
  static String normalizePhone(String phone) {
    var digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('00')) {
      digits = digits.substring(2);
    }
    if (digits.startsWith('0') && digits.length == 11) {
      digits = '90\${digits.substring(1)}';
    } else if (digits.length == 10 && digits.startsWith('5')) {
      digits = '90\$digits';
    }
    return digits;
  }

  static bool isValidPhone(String phone) {
    final normalized = normalizePhone(phone);
    return normalized.length >= 10;
  }

  static Uri buildWhatsAppUri(String phone, String message) {
    final clean = normalizePhone(phone);
    return Uri.parse(
      'https://wa.me/$clean?text=${Uri.encodeComponent(message)}',
    );
  }

  static Uri buildSmsUri(String phone, String message) {
    final clean = normalizePhone(phone);
    return Uri.parse('sms:$clean?body=${Uri.encodeComponent(message)}');
  }

  static Future<bool> sendWhatsApp(String phone, String message) async {
    final uri = buildWhatsAppUri(phone, message);
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  static Future<bool> sendSms(String phone, String message) async {
    final uri = buildSmsUri(phone, message);
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// Once WhatsApp'i dener; basarisiz olursa otomatik SMS'e duser.
  static Future<bool> sendWhatsAppOrSms(String phone, String message) async {
    final wpOk = await sendWhatsApp(phone, message);
    if (wpOk) return true;
    return sendSms(phone, message);
  }
}