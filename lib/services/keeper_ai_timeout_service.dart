import 'dart:async';

class KeeperAiTimeoutService {
  static const Duration defaultTimeout = Duration(seconds: 20);

  Future<T> executeWithTimeout<T>(Future<T> future) async {
    return await future.timeout(
      defaultTimeout,
      onTimeout: () {
        throw TimeoutException("AI response timeout. Please try again.");
      },
    );
  }

  bool isTimeoutError(Object error) {
    return error is TimeoutException;
  }
}
