class KnowledgeRelevanceService {
  bool containsAnswer(String query, String text) {
    return text.toLowerCase().contains(query.toLowerCase());
  }
}
