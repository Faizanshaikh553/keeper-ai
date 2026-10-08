import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class OcrTextService {
  const OcrTextService._();

  static Future<String> extractTextFromImagePath(String imagePath) async {
    final File source = File(imagePath);
    if (!await source.exists()) {
      throw StateError('Image file was not found.');
    }

    final List<_OcrCandidate> candidates = <_OcrCandidate>[];
    final List<File> temporaryFiles = <File>[];

    try {
      final String originalText = await _recognize(imagePath);
      candidates.add(_OcrCandidate(originalText, _qualityScore(originalText)));

      // Weak scans and identity cards whose number was missed get two extra
      // OCR passes: an enlarged copy and a high-contrast grayscale copy.
      // This is especially useful for Aadhaar/PAN photos taken in low light.
      final bool identityNumberWasMissed =
          _looksLikeIdentityDocument(originalText) &&
          !_hasAadhaarNumber(originalText);
      if (_qualityScore(originalText) < 260 || identityNumberWasMissed) {
        final Uint8List sourceBytes = await source.readAsBytes();
        final img.Image? decoded = img.decodeImage(sourceBytes);

        if (decoded != null) {
          final Directory temporaryDirectory = await getTemporaryDirectory();
          final int stamp = DateTime.now().microsecondsSinceEpoch;

          final int targetWidth = decoded.width < 1800
              ? (decoded.width * 1.8).round().clamp(decoded.width, 2200).toInt()
              : decoded.width;
          final img.Image enlarged = img.copyResize(
            decoded,
            width: targetWidth,
            interpolation: img.Interpolation.cubic,
          );

          final File enlargedFile = File(
            '${temporaryDirectory.path}/keeper_ocr_${stamp}_large.jpg',
          );
          await enlargedFile.writeAsBytes(
            img.encodeJpg(enlarged, quality: 96),
            flush: true,
          );
          temporaryFiles.add(enlargedFile);

          final String enlargedText = await _recognize(enlargedFile.path);
          candidates.add(
            _OcrCandidate(enlargedText, _qualityScore(enlargedText)),
          );

          final img.Image grayscale = img.grayscale(enlarged);
          final img.Image contrasted = img.adjustColor(
            grayscale,
            contrast: 1.45,
          );

          final File contrastFile = File(
            '${temporaryDirectory.path}/keeper_ocr_${stamp}_contrast.jpg',
          );
          await contrastFile.writeAsBytes(
            img.encodeJpg(contrasted, quality: 98),
            flush: true,
          );
          temporaryFiles.add(contrastFile);

          final String contrastText = await _recognize(contrastFile.path);
          candidates.add(
            _OcrCandidate(contrastText, _qualityScore(contrastText)),
          );
        }
      }

      candidates.sort((a, b) => b.score.compareTo(a.score));
      return _enrichIdentityText(
        _cleanText(candidates.isEmpty ? '' : candidates.first.text),
      );
    } finally {
      for (final File file in temporaryFiles) {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {
          // Temporary cleanup must never block upload.
        }
      }
    }
  }

  static Future<String> _recognize(String imagePath) async {
    final InputImage inputImage = InputImage.fromFilePath(imagePath);
    final TextRecognizer recognizer = TextRecognizer(
      script: TextRecognitionScript.latin,
    );

    try {
      final RecognizedText recognized = await recognizer.processImage(
        inputImage,
      );
      return _cleanText(recognized.text);
    } finally {
      await recognizer.close();
    }
  }

  static double _qualityScore(String text) {
    final String cleaned = _cleanText(text);
    if (cleaned.isEmpty) return 0;

    final int lettersAndNumbers = RegExp(
      r'[A-Za-z0-9]',
    ).allMatches(cleaned).length;
    final int words = RegExp(r'\b[A-Za-z0-9]{2,}\b').allMatches(cleaned).length;
    final int lines = cleaned
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .length;
    final int suspicious = RegExp(r'[�□]').allMatches(cleaned).length;

    final int aadhaarBonus = _hasAadhaarNumber(cleaned) ? 180 : 0;
    final int identityBonus = _looksLikeIdentityDocument(cleaned) ? 35 : 0;

    return lettersAndNumbers +
        (words * 2.5) +
        (lines * 1.5) +
        aadhaarBonus +
        identityBonus -
        (suspicious * 8);
  }

  static bool _looksLikeIdentityDocument(String text) {
    final String value = text.toLowerCase();
    return value.contains('aadhaar') ||
        value.contains('aadhar') ||
        value.contains('uidai') ||
        value.contains('government of india') ||
        value.contains('unique identification');
  }

  static RegExpMatch? _aadhaarMatch(String text) {
    return RegExp(
      r'\b([0-9]{4})[\s-]*([0-9]{4})[\s-]*([0-9]{4})\b',
    ).firstMatch(text);
  }

  static bool _hasAadhaarNumber(String text) => _aadhaarMatch(text) != null;

  static String _enrichIdentityText(String text) {
    if (text.isEmpty) return text;

    final RegExpMatch? match = _aadhaarMatch(text);
    if (match == null) return text;

    final String normalizedNumber =
        '${match.group(1)} ${match.group(2)} ${match.group(3)}';
    if (text.contains('Detected Aadhaar number:')) return text;

    return '$text\n\nDetected Aadhaar number: $normalizedNumber';
  }

  static String _cleanText(String text) {
    return text
        .replaceAll('\u0000', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r' *\n *'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}

class _OcrCandidate {
  final String text;
  final double score;

  const _OcrCandidate(this.text, this.score);
}
