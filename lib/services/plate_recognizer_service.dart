import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

/// `Plate_detect.onnx` ile plakayi kirpip `google_mlkit_text_recognition` ile
/// harf/rakam egitimi olmadan metin okuyan cihaz-ici servis.
class OnnxOcrPlateRecognizerService implements PlateRecognizerService {
  static const String _assetModelPath = 'assets/models/Plate_detect.onnx';
  static const int _inputSize = 640;
  static const double _confThreshold = 0.25;

  OrtSession? _session;
  TextRecognizer? _textRecognizer;
  bool _modelReady = false;

  @override
  Future<void> init() async {
    _textRecognizer ??= TextRecognizer(script: TextRecognitionScript.latin);

    try {
      OrtEnv.instance.init();
      final tempDir = await getTemporaryDirectory();
      final modelFile = File(p.join(tempDir.path, 'Plate_detect.onnx'));

      final byteData = await rootBundle.load(_assetModelPath);
      await modelFile.writeAsBytes(
        byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        ),
        flush: true,
      );

      final sessionOptions = OrtSessionOptions();
      _session = OrtSession.fromFile(modelFile, sessionOptions);
      sessionOptions.release();
      _modelReady = true;
      debugPrint('PLAKAO ONNX: model yuklendi (${modelFile.path})');
    } catch (e) {
      _modelReady = false;
      debugPrint('PLAKAO ONNX HATA: $e');
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
      double bestScore = 0.0;

      if (_modelReady && _session != null) {
        final cropBox = _detectBestPlateBox(decoded);
        if (cropBox != null) {
          bestScore = cropBox.score;
          final cropped = _cropAndEnlarge(decoded, cropBox);
          final tempDir = await getTemporaryDirectory();
          final cropPath = p.join(
            tempDir.path,
            'plate_crop_${DateTime.now().millisecondsSinceEpoch}.jpg',
          );
          final outFile = File(cropPath);
          await outFile.writeAsBytes(img.encodeJpg(cropped, quality: 95));
          targetFile = outFile;
          debugPrint(
            'PLAKAO ONNX: plaka kirpildi (score=${bestScore.toStringAsFixed(3)}, '
            'box=[${cropBox.left.toInt()}, ${cropBox.top.toInt()}, '
            '${cropBox.right.toInt()}, ${cropBox.bottom.toInt()}])',
          );
        } else {
          debugPrint('PLAKAO ONNX: plaka kutusu bulunamadi, tam gorsel kullaniliyor.');
        }
      } else {
        debugPrint('PLAKAO ONNX: model hazir degil, tam gorsel kullaniliyor.');
      }

      final recognizer = _textRecognizer;
      if (recognizer == null) {
        return PlateRecognitionResult(
          plateGuess: '',
          confidence: bestScore,
        );
      }

      final inputImage = InputImage.fromFilePath(targetFile.path);
      final recognized = await recognizer.processImage(inputImage);

      final cleaned = _extractPlateText(recognized.text);
      final finalConf = cleaned.isNotEmpty
          ? (bestScore > 0 ? bestScore : 0.75)
          : 0.0;

      debugPrint('PLAKAO OCR: ham="${recognized.text.replaceAll('\n', ' ')}" -> temiz="$cleaned"');

      return PlateRecognitionResult(
        plateGuess: cleaned,
        confidence: finalConf,
      );
    } catch (e) {
      debugPrint('PLAKAO RECOGNIZE HATA: $e');
      return const PlateRecognitionResult(plateGuess: '', confidence: 0.0);
    }
  }

  _DetectedBox? _detectBestPlateBox(img.Image source) {
    final session = _session;
    if (session == null) return null;

    final resized = img.copyResize(
      source,
      width: _inputSize,
      height: _inputSize,
      interpolation: img.Interpolation.cubic,
    );

    // NCHW float32 tensor [1, 3, 640, 640]
    const planeSize = _inputSize * _inputSize;
    final tensorData = Float32List(3 * planeSize);

    for (int y = 0; y < _inputSize; y++) {
      for (int x = 0; x < _inputSize; x++) {
        final px = resized.getPixel(x, y);
        final idx = y * _inputSize + x;
        tensorData[idx] = px.r / 255.0;
        tensorData[planeSize + idx] = px.g / 255.0;
        tensorData[2 * planeSize + idx] = px.b / 255.0;
      }
    }

    final inputOrt = OrtValueTensor.createTensorWithDataList(
      tensorData,
      const [1, 3, _inputSize, _inputSize],
    );

    final inputName =
        session.inputNames.isNotEmpty ? session.inputNames.first : 'images';

    final runOptions = OrtRunOptions();
    final List<OrtValue?> outputs;
    try {
      outputs = session.run(runOptions, {inputName: inputOrt});
    } finally {
      inputOrt.release();
      runOptions.release();
    }

    if (outputs.isEmpty || outputs.first == null) {
      for (final out in outputs) {
        out?.release();
      }
      return null;
    }

    final rawValue = outputs.first!.value;
    for (final out in outputs) {
      out?.release();
    }

    // YOLOv8/YOLOv11 cikti sekli genellikle [1, 5, 8400] veya [1, 8400, 5]
    if (rawValue is! List || rawValue.isEmpty) return null;
    final batch0 = rawValue[0];
    if (batch0 is! List || batch0.isEmpty) return null;

    _DetectedBox? best;
    double maxSeenScore = 0.0;
    final wScale = source.width / _inputSize;
    final hScale = source.height / _inputSize;

    const numBoxes = 8400;
    if (batch0.length >= 5 && batch0[0] is List) {
      final cxList = batch0[0] as List;
      final cyList = batch0[1] as List;
      final wList = batch0[2] as List;
      final hList = batch0[3] as List;
      final confList = batch0[4] as List;

      final count = math.min(confList.length, numBoxes);
      for (int i = 0; i < count; i++) {
        final score = (confList[i] as num).toDouble();
        if (score > maxSeenScore) maxSeenScore = score;
        if (score < _confThreshold) continue;
        if (best == null || score > best.score) {
          final cx = (cxList[i] as num).toDouble() * wScale;
          final cy = (cyList[i] as num).toDouble() * hScale;
          final bw = (wList[i] as num).toDouble() * wScale;
          final bh = (hList[i] as num).toDouble() * hScale;
          best = _DetectedBox(
            left: (cx - bw / 2).clamp(0.0, source.width.toDouble()),
            top: (cy - bh / 2).clamp(0.0, source.height.toDouble()),
            right: (cx + bw / 2).clamp(0.0, source.width.toDouble()),
            bottom: (cy + bh / 2).clamp(0.0, source.height.toDouble()),
            score: score,
          );
        }
      }
    } else if (batch0[0] is List && (batch0[0] as List).length >= 5) {
      for (final row in batch0) {
        if (row is! List || row.length < 5) continue;
        final score = (row[4] as num).toDouble();
        if (score > maxSeenScore) maxSeenScore = score;
        if (score < _confThreshold) continue;
        if (best == null || score > best.score) {
          final cx = (row[0] as num).toDouble() * wScale;
          final cy = (row[1] as num).toDouble() * hScale;
          final bw = (row[2] as num).toDouble() * wScale;
          final bh = (row[3] as num).toDouble() * hScale;
          best = _DetectedBox(
            left: (cx - bw / 2).clamp(0.0, source.width.toDouble()),
            top: (cy - bh / 2).clamp(0.0, source.height.toDouble()),
            right: (cx + bw / 2).clamp(0.0, source.width.toDouble()),
            bottom: (cy + bh / 2).clamp(0.0, source.height.toDouble()),
            score: score,
          );
        }
      }
    }

    debugPrint('PLAKAO ONNX maxSeenScore: ${maxSeenScore.toStringAsFixed(4)} (threshold=$_confThreshold)');
    return best;
  }

  img.Image _cropAndEnlarge(img.Image source, _DetectedBox box) {
    final bw = math.max(1.0, box.right - box.left);
    final bh = math.max(1.0, box.bottom - box.top);

    // Sol mavi TR seridindeki hatayi azaltmak icin soldan hafif iceri pay,
    // sag/alt/ust kenarlarda kucuk guvenlik payi birakir.
    final x1 = (box.left + bw * 0.04).floor().clamp(0, source.width - 1);
    final y1 = (box.top - bh * 0.08).floor().clamp(0, source.height - 1);
    final x2 = (box.right + bw * 0.04).ceil().clamp(x1 + 1, source.width);
    final y2 = (box.bottom + bh * 0.08).ceil().clamp(y1 + 1, source.height);

    final cropped = img.copyCrop(
      source,
      x: x1,
      y: y1,
      width: math.max(1, x2 - x1),
      height: math.max(1, y2 - y1),
    );

    // Okuma netligi icin genisligi 600px civarina buyut.
    if (cropped.width < 600) {
      final scale = 600 / cropped.width;
      return img.copyResize(
        cropped,
        width: 600,
        height: math.max(1, (cropped.height * scale).round()),
        interpolation: img.Interpolation.cubic,
      );
    }
    return cropped;
  }

  String _extractPlateText(String rawText) {
    final upper = rawText.toUpperCase();
    final candidates = upper.split(RegExp(r'[\n\r]+'));
    final plateRegex = RegExp(r'\b(0[1-9]|[1-7][0-9]|8[01])\s*[A-Z]{1,3}\s*[0-9]{2,4}\b');

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
    _session?.release();
    _textRecognizer?.close();
  }
}

class _DetectedBox {
  final double left;
  final double top;
  final double right;
  final double bottom;
  final double score;

  const _DetectedBox({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.score,
  });
}