class DocumentAnalysisService {
  bool isDocumentEmpty(String text) {
    return text.trim().isEmpty;
  }

  int getWordCount(String text) {
    return text.split(" ").length;
  }

  int getCharacterCount(String text) {
    return text.length;
  }

  bool containsImportantInformation(String text) {
    return text.length > 50;
  }

  String generateSummary(String text) {
    if (text.length <= 200) {
      return text;
    }

    return "${text.substring(0, 200)}...";
  }
}
