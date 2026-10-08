class KeeperAiUsageResult {
  final bool allowed;
  final int used;
  final int limit;

  const KeeperAiUsageResult({
    required this.allowed,
    required this.used,
    required this.limit,
  });

  int get remaining => limit - used;
}

class KeeperAiUsageService {
  KeeperAiUsageService._();

  // Keeper must not block the user with a client-side daily limit.
  // Real provider quota/rate limiting is handled by the AI provider.
  static const int personalDailyLimit = 999999;

  static Future<KeeperAiUsageResult> reserveRequest() async {
    // Keep the existing return type so no chatbot/UI code needs changing.
    return const KeeperAiUsageResult(
      allowed: true,
      used: 0,
      limit: personalDailyLimit,
    );
  }
}