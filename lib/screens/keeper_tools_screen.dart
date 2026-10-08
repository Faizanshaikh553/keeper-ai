import 'package:flutter/material.dart';

import 'keeper_lens_tab.dart';
import 'keeper_reminder_tab.dart';

class KeeperToolsScreen extends StatefulWidget {
  final int initialTab;

  const KeeperToolsScreen({super.key, this.initialTab = 0});

  @override
  State<KeeperToolsScreen> createState() => _KeeperToolsScreenState();
}

class _KeeperToolsScreenState extends State<KeeperToolsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 2).toInt(),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080D18),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101522),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Keeper Tools',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF766DFF),
          indicatorSize: TabBarIndicatorSize.tab,
          labelColor: Colors.white,
          unselectedLabelColor: const Color(0xFF7F8292),
          labelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
          tabs: const [
            Tab(icon: Icon(Icons.alarm_rounded), text: 'Reminder'),
            Tab(icon: Icon(Icons.center_focus_strong_rounded), text: 'Lens'),
            Tab(icon: Icon(Icons.graphic_eq_rounded), text: 'Live'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          KeeperReminderTab(),
          KeeperLensTab(),
          const Center(child: Text('Keeper Live is temporarily unavailable in this release.')),
        ],
      ),
    );
  }
}
