class KeeperAiContextService {
  String buildContext(List<String> memory, String question) {
    final context = memory.join("\n");

    return '''
Previous Context:

$context

User Question:

$question

''';
  }
}
