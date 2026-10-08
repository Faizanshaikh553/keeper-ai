import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/keeper_reminder.dart';
import '../services/keeper_reminder_service.dart';

class KeeperReminderTab extends StatefulWidget {
  const KeeperReminderTab({super.key});

  @override
  State<KeeperReminderTab> createState() => _KeeperReminderTabState();
}

class _KeeperReminderTabState extends State<KeeperReminderTab> {
  final Uuid _uuid = const Uuid();
  List<KeeperReminder> _reminders = <KeeperReminder>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await KeeperReminderService.initialise();
    final List<KeeperReminder> reminders =
        await KeeperReminderService.load();
    if (!mounted) return;
    setState(() {
      _reminders = reminders;
      _loading = false;
    });
  }

  String _twoDigits(int value) => value.toString().padLeft(2, '0');

  String _formatDateTime(DateTime value) {
    final int hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final String period = value.hour >= 12 ? 'PM' : 'AM';
    return '${_twoDigits(value.day)}/${_twoDigits(value.month)}/${value.year}  '
        '$hour:${_twoDigits(value.minute)} $period';
  }

  Future<void> _delete(KeeperReminder reminder) async {
    await KeeperReminderService.cancel(reminder);
    final List<KeeperReminder> updated = List<KeeperReminder>.from(_reminders)
      ..removeWhere((item) => item.id == reminder.id);
    await KeeperReminderService.saveAll(updated);
    if (!mounted) return;
    setState(() => _reminders = updated);
  }

  Future<void> _showAddReminder() async {
    final TextEditingController titleController = TextEditingController();
    final TextEditingController noteController = TextEditingController();
    DateTime selected = DateTime.now().add(const Duration(minutes: 10));
    bool isAlarm = false;

    final KeeperReminder? reminder = await showModalBottomSheet<KeeperReminder>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121725),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            Future<void> chooseDate() async {
              final DateTime? value = await showDatePicker(
                context: context,
                initialDate: selected,
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 3650)),
              );
              if (value == null) return;
              setSheetState(() {
                selected = DateTime(
                  value.year,
                  value.month,
                  value.day,
                  selected.hour,
                  selected.minute,
                );
              });
            }

            Future<void> chooseTime() async {
              final TimeOfDay? value = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(selected),
              );
              if (value == null) return;
              setSheetState(() {
                selected = DateTime(
                  selected.year,
                  selected.month,
                  selected.day,
                  value.hour,
                  value.minute,
                );
              });
            }

            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  14,
                  20,
                  20 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFF3A4052),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Create with Keeper',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'A notification appears around the chosen time. Android may adjust it slightly to save battery.',
                        style: TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: titleController,
                        autofocus: true,
                        style: const TextStyle(color: Colors.white),
                        decoration: _inputDecoration(
                          'What should Keeper remind you about?',
                          Icons.edit_note_rounded,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: noteController,
                        minLines: 2,
                        maxLines: 4,
                        style: const TextStyle(color: Colors.white),
                        decoration: _inputDecoration(
                          'Optional note',
                          Icons.notes_rounded,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _PickerButton(
                              icon: Icons.calendar_month_rounded,
                              label:
                                  '${_twoDigits(selected.day)}/${_twoDigits(selected.month)}/${selected.year}',
                              onTap: chooseDate,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _PickerButton(
                              icon: Icons.schedule_rounded,
                              label: TimeOfDay.fromDateTime(
                                selected,
                              ).format(context),
                              onTap: chooseTime,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _PresetChip(
                            label: 'In 10 min',
                            onTap: () => setSheetState(
                              () => selected = DateTime.now().add(
                                const Duration(minutes: 10),
                              ),
                            ),
                          ),
                          _PresetChip(
                            label: 'In 1 hour',
                            onTap: () => setSheetState(
                              () => selected = DateTime.now().add(
                                const Duration(hours: 1),
                              ),
                            ),
                          ),
                          _PresetChip(
                            label: 'Tomorrow 9 AM',
                            onTap: () {
                              final DateTime tomorrow = DateTime.now().add(
                                const Duration(days: 1),
                              );
                              setSheetState(
                                () => selected = DateTime(
                                  tomorrow.year,
                                  tomorrow.month,
                                  tomorrow.day,
                                  9,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile.adaptive(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                        ),
                        activeTrackColor: const Color(0xFF766DFF),
                        value: isAlarm,
                        onChanged: (value) =>
                            setSheetState(() => isAlarm = value),
                        title: const Text(
                          'Alarm-style alert',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: const Text(
                          'Uses a louder, high-priority Keeper notification.',
                          style: TextStyle(
                            color: Color(0xFF8E91A3),
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF766DFF),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: () {
                            final String title = titleController.text.trim();
                            if (title.isEmpty ||
                                !selected.isAfter(DateTime.now())) {
                              ScaffoldMessenger.of(context)
                                ..hideCurrentSnackBar()
                                ..showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      title.isEmpty
                                          ? 'Please enter a reminder title.'
                                          : 'Please choose a future time.',
                                    ),
                                  ),
                                );
                              return;
                            }

                            final int notificationId =
                                DateTime.now().microsecondsSinceEpoch &
                                0x7fffffff;
                            Navigator.pop(
                              context,
                              KeeperReminder(
                                id: _uuid.v4(),
                                notificationId: notificationId,
                                title: title,
                                note: noteController.text.trim(),
                                scheduledAt: selected,
                                isAlarm: isAlarm,
                              ),
                            );
                          },
                          icon: const Icon(Icons.notifications_active_rounded),
                          label: const Text(
                            'Set reminder',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    titleController.dispose();
    noteController.dispose();
    if (reminder == null || !mounted) return;

    final bool permission = await KeeperReminderService.requestPermission();
    if (!permission) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Notification permission is needed so Keeper can remind you.',
          ),
        ),
      );
      return;
    }

    try {
      await KeeperReminderService.schedule(reminder);
      final List<KeeperReminder> updated = <KeeperReminder>[
        ..._reminders,
        reminder,
      ]..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
      await KeeperReminderService.saveAll(updated);
      if (!mounted) return;
      setState(() => _reminders = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            reminder.isAlarm
                ? 'Keeper alarm scheduled.'
                : 'Keeper reminder scheduled.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not schedule this reminder. Please retry.'),
        ),
      );
    }
  }

  InputDecoration _inputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF6F7586)),
      prefixIcon: Icon(icon, color: const Color(0xFF938CFF)),
      filled: true,
      fillColor: const Color(0xFF171D2B),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF2B3142)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF2B3142)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF766DFF)),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: _showAddReminder,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF766DFF),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.add_alarm_rounded),
              label: const Text(
                'New reminder or alarm',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
        Expanded(
          child: _reminders.isEmpty
              ? const _EmptyReminders()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
                  itemCount: _reminders.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final KeeperReminder reminder = _reminders[index];
                    final bool expired = reminder.scheduledAt.isBefore(
                      DateTime.now(),
                    );
                    return Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: const Color(0xFF151B2A),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFF293247)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: const Color(0xFF27235B),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              reminder.isAlarm
                                  ? Icons.alarm_rounded
                                  : Icons.notifications_active_rounded,
                              color: const Color(0xFFAAA4FF),
                            ),
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  reminder.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: expired
                                        ? const Color(0xFF8E91A3)
                                        : Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  expired
                                      ? 'Completed · ${_formatDateTime(reminder.scheduledAt)}'
                                      : _formatDateTime(reminder.scheduledAt),
                                  style: const TextStyle(
                                    color: Color(0xFF9CA3AF),
                                    fontSize: 12,
                                  ),
                                ),
                                if (reminder.note.trim().isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    reminder.note.trim(),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF7F8698),
                                      fontSize: 11,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: reminder.isAlarm
                                        ? const Color(0xFF48272E)
                                        : const Color(0xFF27235B),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    reminder.isAlarm ? 'ALARM' : 'REMINDER',
                                    style: TextStyle(
                                      color: reminder.isAlarm
                                          ? const Color(0xFFFFA3AA)
                                          : const Color(0xFFB9B4FF),
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Delete reminder',
                            onPressed: () => _delete(reminder),
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              color: Color(0xFF8E91A3),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PresetChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      onPressed: onTap,
      avatar: const Icon(
        Icons.bolt_rounded,
        size: 16,
        color: Color(0xFFAAA4FF),
      ),
      label: Text(label),
      labelStyle: const TextStyle(
        color: Color(0xFFD7D4EA),
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
      ),
      backgroundColor: const Color(0xFF171D2B),
      side: const BorderSide(color: Color(0xFF30374A)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }
}

class _PickerButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PickerButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF171D2B),
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: const Color(0xFF2B3142)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 19, color: const Color(0xFF938CFF)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyReminders extends StatelessWidget {
  const _EmptyReminders();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_none_rounded,
              color: Color(0xFF777E91),
              size: 48,
            ),
            SizedBox(height: 13),
            Text(
              'No reminders yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 7),
            Text(
              'Keeper will notify you around the time you choose, even when the app is not open.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF8E91A3),
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
