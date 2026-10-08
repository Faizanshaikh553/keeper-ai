class QuestionPaperService {
  bool isQuestionPaper(String text) {
    final lower = text.toLowerCase();

    return lower.contains("question") ||
        lower.contains("marks") ||
        lower.contains("section") ||
        lower.contains("unit");
  }

  List<String> extractQuestions(String text) {
    return text.split("\n").where((line) => line.trim().isNotEmpty).toList();
  }

  int estimateTotalQuestions(String text) {
    return extractQuestions(text).length;
  }
}
