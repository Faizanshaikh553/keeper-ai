class AiSummaryService {
  String generateSummary(String text) {
    if (text.length < 500) {
      return text;
    }

    return "${text.substring(0, 500)}...";
  }
}
