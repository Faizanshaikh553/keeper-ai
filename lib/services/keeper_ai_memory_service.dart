class KeeperAiMemoryService {
  static final List<String> _conversationMemory = [];

  // Save message to memory
  void saveMessage(String message) {
    _conversationMemory.add(message);

    // Keep only latest 50 messages
    if (_conversationMemory.length > 50) {
      _conversationMemory.removeAt(0);
    }
  }

  // Get all memory
  List<String> getMemory() {
    return _conversationMemory;
  }

  // Get recent memory
  List<String> getRecentMemory({int limit = 10}) {
    if (_conversationMemory.isEmpty) {
      return [];
    }

    return _conversationMemory.length <= limit
        ? _conversationMemory
        : _conversationMemory.sublist(_conversationMemory.length - limit);
  }

  // Clear memory
  void clearMemory() {
    _conversationMemory.clear();
  }
}
