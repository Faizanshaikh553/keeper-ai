class KeeperReminder {
  final String id;
  final int notificationId;
  final String title;
  final String note;
  final DateTime scheduledAt;
  final bool isAlarm;

  const KeeperReminder({
    required this.id,
    required this.notificationId,
    required this.title,
    required this.note,
    required this.scheduledAt,
    required this.isAlarm,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'notificationId': notificationId,
    'title': title,
    'note': note,
    'scheduledAt': scheduledAt.toIso8601String(),
    'isAlarm': isAlarm,
  };

  factory KeeperReminder.fromJson(Map<String, dynamic> json) {
    return KeeperReminder(
      id: json['id']?.toString() ?? '',
      notificationId: (json['notificationId'] as num?)?.toInt() ?? 0,
      title: json['title']?.toString() ?? 'Keeper reminder',
      note: json['note']?.toString() ?? '',
      scheduledAt:
          DateTime.tryParse(json['scheduledAt']?.toString() ?? '') ??
          DateTime.now(),
      isAlarm: json['isAlarm'] == true,
    );
  }
}
