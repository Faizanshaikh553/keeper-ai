class ImageUnderstandingService {
  bool containsText(String extractedText) {
    return extractedText.trim().isNotEmpty;
  }

  String analyzeImageText(String extractedText) {
    if (extractedText.isEmpty) {
      return "No text detected.";
    }

    return extractedText;
  }

  bool isComplexImage(String extractedText) {
    return extractedText.length > 100;
  }
}
