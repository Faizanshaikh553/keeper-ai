import 'package:flutter/material.dart';

class VaultSettingsScreen extends StatefulWidget {
  const VaultSettingsScreen({super.key});

  @override
  State<VaultSettingsScreen> createState() => _VaultSettingsScreenState();
}

class _VaultSettingsScreenState extends State<VaultSettingsScreen> {
  bool fingerprintEnabled = false;
  bool faceUnlockEnabled = false;
  bool secureModeEnabled = true;

  String autoLockTime = "5 Minutes";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Vault Settings")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Security Section
          const Text(
            "Security",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 10),

          SwitchListTile(
            title: const Text("Enable Fingerprint Lock"),
            value: fingerprintEnabled,
            onChanged: (value) {
              setState(() {
                fingerprintEnabled = value;
              });
            },
          ),

          SwitchListTile(
            title: const Text("Enable Face Unlock"),
            value: faceUnlockEnabled,
            onChanged: (value) {
              setState(() {
                faceUnlockEnabled = value;
              });
            },
          ),

          SwitchListTile(
            title: const Text("Secure Mode"),
            subtitle: const Text("Extra security for your Personal Vault."),
            value: secureModeEnabled,
            onChanged: (value) {
              setState(() {
                secureModeEnabled = value;
              });
            },
          ),

          const Divider(),

          // Vault PIN
          ListTile(
            leading: const Icon(Icons.password),
            title: const Text("Change Vault PIN"),
            subtitle: const Text("Update your Vault PIN anytime."),
            onTap: () {},
          ),

          const Divider(),

          // Auto Lock
          ListTile(
            leading: const Icon(Icons.lock_clock),
            title: const Text("Auto Lock Duration"),
            subtitle: Text(autoLockTime),
            onTap: () {
              _showAutoLockDialog();
            },
          ),

          const Divider(),

          // Future Features
          const SizedBox(height: 10),

          const Text(
            "Future Features",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 10),

          const ListTile(
            leading: Icon(Icons.visibility_off),
            title: Text("Hide App Preview"),
            subtitle: Text("Coming Soon"),
          ),

          const ListTile(
            leading: Icon(Icons.screenshot_monitor),
            title: Text("Screenshot Protection"),
            subtitle: Text("Coming Soon"),
          ),

          const ListTile(
            leading: Icon(Icons.backup),
            title: Text("Vault Backup"),
            subtitle: Text("Coming Soon"),
          ),

          const ListTile(
            leading: Icon(Icons.file_download),
            title: Text("Export Vault"),
            subtitle: Text("Coming Soon"),
          ),

          const Divider(),

          // Danger Zone
          const SizedBox(height: 10),

          const Text(
            "Danger Zone",
            style: TextStyle(
              color: Colors.red,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 10),

          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {},
            child: const Text("Clear Personal Vault"),
          ),

          const SizedBox(height: 10),

          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {},
            child: const Text("Reset Vault Settings"),
          ),
        ],
      ),
    );
  }

  void _showAutoLockDialog() {
    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text("Auto Lock Duration"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _autoLockOption("30 Seconds"),
              _autoLockOption("1 Minute"),
              _autoLockOption("5 Minutes"),
              _autoLockOption("10 Minutes"),
              _autoLockOption("15 Minutes"),
            ],
          ),
        );
      },
    );
  }

  Widget _autoLockOption(String value) {
    return ListTile(
      title: Text(value),
      onTap: () {
        setState(() {
          autoLockTime = value;
        });

        Navigator.pop(context);
      },
    );
  }
}
