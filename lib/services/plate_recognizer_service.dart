import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class PlateRecognitionResult {
  final String plateGuess;
  final double confidence;

  const PlateRecognitionResult({
    required this.plateGuess,
    required this.confidence,
  });
}

abstract class PlateRecognizerService {
  Future<void> init();
  Future<PlateRecognitionResult> recognize(File imageFile);
  void dispose();
}

/// Model bagli degilken veya test sirasinda kullanilan guvenli servis.
class MockPlateRecognizerService implements PlateRecognizerService {
  @override
  Future<void> init() async {}

  @override
  Future<PlateRecognitionResult> recognize(File imageFile) async {
    await Future.delayed(const Duration(milliseconds: 250));
    return const PlateRecognitionResult(plateGuess: '', confidence: 0.0);
  }

  @override
  void dispose() {}
}

/// `google_mlkit_text_recognition` ile cihaz-ici plaka metni okuyan servis.
class MlKitPlateRecognizerService implements PlateRecognizerService {
  TextRecognizer? _textRecognizer;

  @override
  Future<void> init() async {
    _textRecognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
  }

  @override
  Future<PlateRecognitionResult> recognize(File imageFile) async {
    try {
      _textRecognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
      final recognizer = _textRecognizer!;

      final inputImage = InputImage.fromFilePath(imageFile.path);
      final recognized = await recognizer.processImage(inputImage);

      final cleaned = _extractPlateText(recognized.text);
      final confidence = cleaned.isNotEmpty ? 0.75 : 0.0;

      debugPrint(
        'PLAKAO MLKIT: ham="${recognized.text.replaceAll('\n', ' ')}" -> temiz="$cleaned"',
      );

      return PlateRecognitionResult(
        plateGuess: cleaned,
        confidence: confidence,
      );
    } catch (e) {
      debugPrint('PLAKAO MLKIT HATA: $e');
      return const PlateRecognitionResult(plateGuess: '', confidence: 0.0);
    }
  }

  String _extractPlateText(String rawText) {
    final upper = rawText.toUpperCase();
    final candidates = upper.split(RegExp(r'[\n\r]+'));
    final plateRegex = RegExp(
      r'\b(0[1-9]|[1-7][0-9]|8[01])\s*[A-Z]{1,3}\s*[0-9]{2,4}\b',
    );

    for (final line in candidates) {
      final match = plateRegex.firstMatch(line);
      if (match != null) {
        return match.group(0)!.replaceAll(RegExp(r'[^A-Z0-9]'), '');
      }
    }

    final compactMatch = plateRegex.firstMatch(
      upper.replaceAll(RegExp(r'[^A-Z0-9]'), ''),
    );
    if (compactMatch != null) {
      return compactMatch.group(0)!;
    }

    return upper.replaceAll(RegExp(r'[^A-Z0-9]'), '').trim();
  }

  @override
  void dispose() {
    _textRecognizer?.close();
    _textRecognizer = null;
  }
}