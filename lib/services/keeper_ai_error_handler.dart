class KeeperAiErrorHandler {
  String handleError(Object error) {
    final message = error.toString();

    if (message.contains("timeout")) {
      return "AI took too long to respond.";
    }

    if (message.contains("network")) {
      return "Please check your internet connection.";
    }

    if (message.contains("permission")) {
      return "Permission denied.";
    }

    return "Something went wrong. Please try again.";
  }
}
