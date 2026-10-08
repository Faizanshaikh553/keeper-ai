class AiKeyPointsService {
  List<String> extractKeyPoints(String text) {
    return text
        .split(".")
        .where((line) => line.trim().isNotEmpty)
        .take(10)
        .toList();
  }
}
