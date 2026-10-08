import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/keeper_reminder.dart';

class KeeperReminderService {
  KeeperReminderService._();

  static const String _storageKey = 'keeper_reminders_v1';
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static bool _initialised = false;

  static Future<void> initialise() async {
    if (_initialised) return;

    tz_data.initializeTimeZones();
    try {
      final String zoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zoneName));
    } catch (_) {
      // tz.local remains usable; the notification plugin will still schedule
      // the reminder even if a device reports an unknown timezone name.
    }

    const InitializationSettings settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _notifications.initialize(settings);
    _initialised = true;
  }

  static Future<bool> requestPermission() async {
    await initialise();
    final AndroidFlutterLocalNotificationsPlugin? android = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final bool? granted = await android?.requestNotificationsPermission();
    return granted ?? true;
  }

  static Future<List<KeeperReminder>> load() async {
    final SharedPreferences preferences =
        await SharedPreferences.getInstance();
    final List<String> stored = preferences.getStringList(_storageKey) ?? [];
    final List<KeeperReminder> reminders = <KeeperReminder>[];

    for (final String item in stored) {
      try {
        reminders.add(
          KeeperReminder.fromJson(
            Map<String, dynamic>.from(jsonDecode(item) as Map),
          ),
        );
      } catch (_) {
        // Ignore a damaged local entry without losing the other reminders.
      }
    }

    reminders.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return reminders;
  }

  static Future<void> saveAll(List<KeeperReminder> reminders) async {
    final SharedPreferences preferences =
        await SharedPreferences.getInstance();
    await preferences.setStringList(
      _storageKey,
      reminders.map((item) => jsonEncode(item.toJson())).toList(),
    );
  }

  static Future<void> schedule(KeeperReminder reminder) async {
    await initialise();
    if (!reminder.scheduledAt.isAfter(DateTime.now())) {
      throw ArgumentError('Reminder time must be in the future.');
    }

    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          reminder.isAlarm ? 'keeper_alarms' : 'keeper_reminders',
          reminder.isAlarm ? 'Keeper alarms' : 'Keeper reminders',
          channelDescription: reminder.isAlarm
              ? 'Alarm alerts created in Keeper'
              : 'Helpful reminders created in Keeper',
          importance: Importance.max,
          priority: Priority.high,
          category: reminder.isAlarm
              ? AndroidNotificationCategory.alarm
              : AndroidNotificationCategory.reminder,
          playSound: true,
          enableVibration: true,
          visibility: NotificationVisibility.public,
          icon: '@mipmap/ic_launcher',
        );

    await _notifications.zonedSchedule(
      reminder.notificationId,
      reminder.isAlarm ? '⏰ ${reminder.title}' : reminder.title,
      reminder.note.trim().isEmpty
          ? 'Keeper asked me to remind you now.'
          : reminder.note.trim(),
      tz.TZDateTime.from(reminder.scheduledAt, tz.local),
      NotificationDetails(
        android: androidDetails,
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: reminder.id,
    );
  }

  static Future<void> cancel(KeeperReminder reminder) async {
    await initialise();
    await _notifications.cancel(reminder.notificationId);
  }
}
