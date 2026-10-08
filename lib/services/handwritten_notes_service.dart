class HandwrittenNotesService {
  bool looksLikeHandwrittenText(String text) {
    return text.isNotEmpty;
  }

  String cleanText(String text) {
    return text.trim();
  }

  String generateNotesSummary(String text) {
    if (text.length < 150) {
      return text;
    }

    return "${text.substring(0, 150)}...";
  }
}
