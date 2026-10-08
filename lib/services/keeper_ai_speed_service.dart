class KeeperAiSpeedService {
  String optimizePrompt(String prompt) {
    return prompt.trim();
  }

  bool shouldUseFastResponse(String prompt) {
    return prompt.length < 100;
  }
}
