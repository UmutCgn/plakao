import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/plate_format.dart';

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

/// Model bağlı değilken veya test sırasında kullanılan güvenli servis.
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

/// TFLite plaka tespiti (`Plate_detect_float32.tflite`) + ML Kit OCR servisi.
class TFLitePlateRecognizerService implements PlateRecognizerService {
  static const String _modelAssetPath =
      'assets/models/Plate_detect_float32.tflite';
  static const int _inputSize = 640;

  Interpreter? _detector;
  bool _detectorReady = false;

  final TextRecognizer _fallbackOcr =
      TextRecognizer(script: TextRecognitionScript.latin);

  /// Ayarlar ekranındaki "Plaka Güven Eşiği" slider'ından gelir.
  final double confidenceThreshold;

  /// Ayarlar ekranındaki "Sıkı Format Kontrolü" anahtarından gelir.
  /// true: sadece "İL HARF SAYI" formatına uyan sonuçlar kabul edilir.
  /// false: gevşek temizlenmiş ham metin plaka alanına yazılır (test için).
  final bool strictFormat;

  TFLitePlateRecognizerService({
    this.confidenceThreshold = 0.25,
    this.strictFormat = true,
  });

  @override
  Future<void> init() async {
    try {
      final options = InterpreterOptions()..threads = 2;
      _detector = await Interpreter.fromAsset(_modelAssetPath, options: options);
      _detectorReady = true;
      debugPrint(
        'PLAKAO TFLITE: yüklendi | in=${_detector!.getInputTensor(0).shape} '
        '| out=${_detector!.getOutputTensor(0).shape}',
      );
    } catch (e) {
      _detectorReady = false;
      debugPrint('PLAKAO TFLITE init uyarısı (ML Kit fallback aktif): $e');
    }
  }

  @override
  Future<PlateRecognitionResult> recognize(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        return const PlateRecognitionResult(plateGuess: '', confidence: 0.0);
      }

      File targetFile = imageFile;
      double? detScore;

      if (_detectorReady && _detector != null) {
        final box = _runDetector(decoded);
        if (box != null) {
          detScore = box.score;
          final cropped = _cropWithMargin(decoded, box, marginRatio: 0.08);
          final upscaled = img.copyResize(
            cropped,
            width: cropped.width * 3,
            interpolation: img.Interpolation.cubic,
          );

          final tempDir = await getTemporaryDirectory();
          final cropPath = p.join(
            tempDir.path,
            'plate_crop_${DateTime.now().millisecondsSinceEpoch}.jpg',
          );
          final outFile = File(cropPath);
          await outFile.writeAsBytes(img.encodeJpg(upscaled, quality: 95));
          targetFile = outFile;
        }
      }

      final input = InputImage.fromFilePath(targetFile.path);
      final recognized = await _fallbackOcr.processImage(input);

      debugPrint(
        'PLAKAO OCR ham metin: "${recognized.text.replaceAll('\n', ' ')}" '
        '${detScore != null ? "| detScore=${detScore.toStringAsFixed(2)}" : "| fallback"}',
      );

      final formatted = _extractBestPlate(recognized.text);
      return _finalize(formatted, detScore);
    } catch (e) {
      debugPrint('PlateRecognizer HATA: $e');
      return const PlateRecognitionResult(plateGuess: '', confidence: 0.0);
    }
  }

  _PlateBox? _runDetector(img.Image source) {
    final detector = _detector;
    if (detector == null) return null;

    final inShape = detector.getInputTensor(0).shape;
    final outShape = detector.getOutputTensor(0).shape;

    final resized = img.copyResize(
      source,
      width: _inputSize,
      height: _inputSize,
      interpolation: img.Interpolation.cubic,
    );

    final isNchw = inShape.length == 4 && inShape[1] == 3;
    final Object inputTensor;

    if (isNchw) {
      inputTensor = List.generate(
        1,
        (_) => List.generate(
          3,
          (c) => List.generate(
            _inputSize,
            (y) => List.generate(_inputSize, (x) {
              final px = resized.getPixel(x, y);
              final v = c == 0 ? px.r : (c == 1 ? px.g : px.b);
              return v / 255.0;
            }),
          ),
        ),
      );
    } else {
      // [1, 640, 640, 3] NHWC
      inputTensor = List.generate(
        1,
        (_) => List.generate(
          _inputSize,
          (y) => List.generate(_inputSize, (x) {
            final px = resized.getPixel(x, y);
            return [px.r / 255.0, px.g / 255.0, px.b / 255.0];
          }),
        ),
      );
    }

    final d1 = outShape.length > 1 ? outShape[1] : 5;
    final d2 = outShape.length > 2 ? outShape[2] : 8400;
    final outputTensor = List.generate(
      1,
      (_) => List.generate(d1, (_) => List.filled(d2, 0.0)),
    );

    detector.run(inputTensor, outputTensor);

    final batch0 = outputTensor[0];
    _PlateBox? best;
    final wScale = source.width / _inputSize;
    final hScale = source.height / _inputSize;

    // [1, 5, 8400] veya [1, 8400, 5] formatlari
    if (d1 >= 5 && d2 > d1) {
      for (int i = 0; i < d2; i++) {
        final score = (batch0[4][i] as num).toDouble();
        if (score < confidenceThreshold) continue;
        if (best == null || score > best.score) {
          final cx = (batch0[0][i] as num).toDouble() * wScale;
          final cy = (batch0[1][i] as num).toDouble() * hScale;
          final bw = (batch0[2][i] as num).toDouble() * wScale;
          final bh = (batch0[3][i] as num).toDouble() * hScale;
          best = _PlateBox(
            left: (cx - bw / 2).clamp(0.0, source.width.toDouble()),
            top: (cy - bh / 2).clamp(0.0, source.height.toDouble()),
            right: (cx + bw / 2).clamp(0.0, source.width.toDouble()),
            bottom: (cy + bh / 2).clamp(0.0, source.height.toDouble()),
            score: score,
          );
        }
      }
    } else if (d2 >= 5) {
      for (int i = 0; i < d1; i++) {
        final score = (batch0[i][4] as num).toDouble();
        if (score < confidenceThreshold) continue;
        if (best == null || score > best.score) {
          final cx = (batch0[i][0] as num).toDouble() * wScale;
          final cy = (batch0[i][1] as num).toDouble() * hScale;
          final bw = (batch0[i][2] as num).toDouble() * wScale;
          final bh = (batch0[i][3] as num).toDouble() * hScale;
          best = _PlateBox(
            left: (cx - bw / 2).clamp(0.0, source.width.toDouble()),
            top: (cy - bh / 2).clamp(0.0, source.height.toDouble()),
            right: (cx + bw / 2).clamp(0.0, source.width.toDouble()),
            bottom: (cy + bh / 2).clamp(0.0, source.height.toDouble()),
            score: score,
          );
        }
      }
    }

    return best;
  }

  img.Image _cropWithMargin(
    img.Image source,
    _PlateBox box, {
    double marginRatio = 0.08,
  }) {
    final bw = math.max(1.0, box.right - box.left);
    final bh = math.max(1.0, box.bottom - box.top);

    final x1 = (box.left - bw * marginRatio).floor().clamp(0, source.width - 1);
    final y1 = (box.top - bh * marginRatio).floor().clamp(0, source.height - 1);
    final x2 = (box.right + bw * marginRatio).ceil().clamp(x1 + 1, source.width);
    final y2 =
        (box.bottom + bh * marginRatio).ceil().clamp(y1 + 1, source.height);

    return img.copyCrop(
      source,
      x: x1,
      y: y1,
      width: math.max(1, x2 - x1),
      height: math.max(1, y2 - y1),
    );
  }

  String? _extractBestPlate(String rawText) {
    final upper = rawText.toUpperCase();
    final lines = upper.split(RegExp(r'[\n\r]+'));

    if (strictFormat) {
      for (final line in lines) {
        final formatted = TrPlateFormat.tryFormat(line);
        if (formatted != null) return formatted;
      }
      // Satır kırılması plakayı bölmüş olabilir, tüm metni birleştirip dene.
      return TrPlateFormat.tryFormat(lines.join());
    }

    // Sıkı format kapalı: sadece temizlenmiş ham metni döndür.
    final cleaned = TrPlateFormat.looseClean(upper.replaceAll('\n', ''));
    return cleaned.isNotEmpty ? cleaned : null;
  }

  PlateRecognitionResult _finalize(String? formatted, double? detScore) {
    if (formatted == null || formatted.isEmpty) {
      return const PlateRecognitionResult(plateGuess: '', confidence: 0.0);
    }
    return PlateRecognitionResult(
      plateGuess: formatted,
      confidence: detScore ?? 0.65,
    );
  }

  @override
  void dispose() {
    _detector?.close();
    _detector = null;
    _fallbackOcr.close();
  }
}

class _PlateBox {
  final double left;
  final double top;
  final double right;
  final double bottom;
  final double score;

  const _PlateBox({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.score,
  });
}

/// `google_mlkit_text_recognition` ile cihaz-içi tam-kare OCR (galeri
/// akışında ya da TFLite tamamen devre dışıyken yedek olarak kullanılabilir).
class MlKitPlateRecognizerService implements PlateRecognizerService {
  TextRecognizer? _textRecognizer;
  final bool strictFormat;

  MlKitPlateRecognizerService({this.strictFormat = true});

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
      final confidence = cleaned.isNotEmpty ? 0.65 : 0.0;

      return PlateRecognitionResult(plateGuess: cleaned, confidence: confidence);
    } catch (e) {
      debugPrint('PLAKAO MLKIT HATA: $e');
      return const PlateRecognitionResult(plateGuess: '', confidence: 0.0);
    }
  }

  String _extractPlateText(String rawText) {
    final upper = rawText.toUpperCase();
    final lines = upper.split(RegExp(r'[\n\r]+'));

    if (strictFormat) {
      for (final line in lines) {
        final formatted = TrPlateFormat.tryFormat(line);
        if (formatted != null) return formatted;
      }
      final joined = TrPlateFormat.tryFormat(lines.join());
      if (joined != null) return joined;
      return '';
    }
    return TrPlateFormat.looseClean(upper.replaceAll('\n', ''));
  }

  @override
  void dispose() {
    _textRecognizer?.close();
    _textRecognizer = null;
  }
}