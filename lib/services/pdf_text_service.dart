import 'dart:io';
import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

class PdfTextService {
  const PdfTextService._();

  static Future<String> extractTextFromPath(String filePath) async {
    final File file = File(filePath);

    if (!await file.exists()) {
      throw Exception('PDF file not found.');
    }

    final Uint8List bytes = await file.readAsBytes();

    if (bytes.isEmpty) {
      throw Exception('PDF file is empty.');
    }

    PdfDocument? document;

    try {
      document = PdfDocument(inputBytes: bytes);

      final String extractedText = PdfTextExtractor(
        document,
      ).extractText().trim();

      if (extractedText.isEmpty) {
        return '';
      }

      return _cleanText(extractedText);
    } catch (error) {
      throw Exception('Unable to read PDF text: $error');
    } finally {
      document?.dispose();
    }
  }

  static String _cleanText(String text) {
    return text
        .replaceAll('\u0000', '')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}
