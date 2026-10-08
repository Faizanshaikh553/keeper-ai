import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'ocr_text_service.dart';
import 'pdf_text_service.dart';

class TextExtractionResult {
  final String text;
  final String status;

  const TextExtractionResult({required this.text, required this.status});
}

class TextExtractorService {
  const TextExtractorService._();

  static const int _maximumStoredCharacters = 2 * 1000 * 1000;

  static Future<TextExtractionResult> extract({
    required String filePath,
    required String extension,
  }) async {
    final String normalizedExtension = extension
        .trim()
        .toLowerCase()
        .replaceFirst('.', '');

    switch (normalizedExtension) {
      case 'pdf':
        return _extractPdf(filePath);
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'webp':
        return _extractImage(filePath);
      case 'txt':
      case 'text':
      case 'log':
      case 'csv':
      case 'md':
        return _extractTextFile(filePath);
      case 'doc':
      case 'docx':
        return const TextExtractionResult(
          text: '',
          status: 'waiting_for_docx_processor',
        );
      default:
        return const TextExtractionResult(text: '', status: 'unsupported');
    }
  }

  static Future<TextExtractionResult> _extractPdf(String filePath) async {
    try {
      final String text = _cleanText(
        await PdfTextService.extractTextFromPath(filePath),
      );
      if (text.isEmpty) {
        return const TextExtractionResult(text: '', status: 'needs_ocr');
      }
      return TextExtractionResult(text: _limit(text), status: 'completed');
    } catch (_) {
      return const TextExtractionResult(text: '', status: 'failed');
    }
  }

  static Future<TextExtractionResult> _extractImage(String filePath) async {
    try {
      final String text = _cleanText(
        await OcrTextService.extractTextFromImagePath(filePath),
      );
      if (text.isEmpty) {
        return const TextExtractionResult(text: '', status: 'no_text_found');
      }
      return TextExtractionResult(text: _limit(text), status: 'completed');
    } catch (_) {
      return const TextExtractionResult(text: '', status: 'failed');
    }
  }

  static Future<TextExtractionResult> _extractTextFile(String filePath) async {
    try {
      final File file = File(filePath);
      if (!await file.exists()) {
        return const TextExtractionResult(text: '', status: 'failed');
      }

      final Uint8List bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        return const TextExtractionResult(text: '', status: 'empty');
      }

      if (_looksBinary(bytes)) {
        return const TextExtractionResult(
          text: '',
          status: 'unsupported_binary',
        );
      }

      final String decoded = _decodeText(bytes);
      final String cleaned = _cleanText(decoded);
      if (cleaned.isEmpty) {
        return const TextExtractionResult(text: '', status: 'empty');
      }

      return TextExtractionResult(text: _limit(cleaned), status: 'completed');
    } catch (_) {
      return const TextExtractionResult(text: '', status: 'failed');
    }
  }

  static String _decodeText(Uint8List bytes) {
    Uint8List value = bytes;

    if (value.length >= 3 &&
        value[0] == 0xEF &&
        value[1] == 0xBB &&
        value[2] == 0xBF) {
      value = Uint8List.sublistView(value, 3);
    }

    if (value.length >= 2 && value[0] == 0xFF && value[1] == 0xFE) {
      final List<int> codeUnits = <int>[];
      for (int index = 2; index + 1 < value.length; index += 2) {
        codeUnits.add(value[index] | (value[index + 1] << 8));
      }
      return String.fromCharCodes(codeUnits);
    }

    if (value.length >= 2 && value[0] == 0xFE && value[1] == 0xFF) {
      final List<int> codeUnits = <int>[];
      for (int index = 2; index + 1 < value.length; index += 2) {
        codeUnits.add((value[index] << 8) | value[index + 1]);
      }
      return String.fromCharCodes(codeUnits);
    }

    try {
      return utf8.decode(value, allowMalformed: false);
    } catch (_) {
      final String malformedUtf8 = utf8.decode(value, allowMalformed: true);
      final int replacements = '�'.allMatches(malformedUtf8).length;
      if (replacements <= maxOf(2, malformedUtf8.length ~/ 500)) {
        return malformedUtf8;
      }
      return latin1.decode(value, allowInvalid: true);
    }
  }

  static bool _looksBinary(Uint8List bytes) {
    if (bytes.length >= 2 &&
        ((bytes[0] == 0xFF && bytes[1] == 0xFE) ||
            (bytes[0] == 0xFE && bytes[1] == 0xFF))) {
      return false;
    }

    final int sampleLength = bytes.length < 4096 ? bytes.length : 4096;
    int suspicious = 0;

    for (int index = 0; index < sampleLength; index++) {
      final int byte = bytes[index];
      if (byte == 0) return true;
      final bool control = byte < 9 || (byte > 13 && byte < 32);
      if (control) suspicious++;
    }

    return suspicious > sampleLength * 0.08;
  }

  static int maxOf(int first, int second) => first > second ? first : second;

  static String _cleanText(String value) {
    return value
        .replaceAll('\u0000', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r' *\n *'), '\n')
        .replaceAll(RegExp(r'\n{4,}'), '\n\n\n')
        .trim();
  }

  static String _limit(String value) {
    if (value.length <= _maximumStoredCharacters) return value;
    return value.substring(0, _maximumStoredCharacters);
  }
}
