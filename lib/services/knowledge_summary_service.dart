class KnowledgeSummaryService {
  String generateSummary(String text) {
    if (text.length < 300) {
      return text;
    }

    return "${text.substring(0, 300)}...";
  }
}
