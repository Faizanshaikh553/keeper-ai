class KnowledgeContextService {
  String buildContext(List<String> documents) {
    return documents.join("\n\n");
  }
}
