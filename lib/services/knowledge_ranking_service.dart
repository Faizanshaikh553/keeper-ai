class KnowledgeRankingService {
  double calculateScore(String query, String documentText) {
    final queryWords = query.toLowerCase().split(" ");

    double score = 0;

    for (var word in queryWords) {
      if (documentText.toLowerCase().contains(word)) {
        score += 10;
      }
    }

    return score;
  }

  bool isRelevant(double score) {
    return score > 10;
  }
}
