import 'package:flutter/material.dart';

import '../services/keeper_live_overlay_bridge.dart';

class KeeperLensTab extends StatefulWidget {
  const KeeperLensTab({super.key});

  @override
  State<KeeperLensTab> createState() => _KeeperLensTabState();
}

class _KeeperLensTabState extends State<KeeperLensTab> {
  bool _opening = false;

  Future<void> _openLens() async {
    if (_opening) return;
    setState(() => _opening = true);
    final bool opened = await KeeperLiveOverlayBridge.openGoogleLens();
    if (!mounted) return;
    setState(() => _opening = false);
    if (!opened) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Google Lens could not open. Update or install the Google app.',
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool compact = constraints.maxHeight < 560;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(18, compact ? 14 : 22, 18, 28),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(compact ? 18 : 22),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF29236A), Color(0xFF11182A)],
                  ),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: const Color(0xFF46408A)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x26766DFF),
                      blurRadius: 28,
                      offset: Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      width: compact ? 76 : 92,
                      height: compact ? 76 : 92,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D1220),
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(color: const Color(0xFF6259C9)),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          const Icon(
                            Icons.center_focus_strong_rounded,
                            color: Colors.white,
                            size: 52,
                          ),
                          Positioned(
                            right: 13,
                            bottom: 13,
                            child: Container(
                              width: 14,
                              height: 14,
                              decoration: const BoxDecoration(
                                color: Color(0xFF52D38B),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: compact ? 14 : 20),
                    const Text(
                      'Google Lens, directly from Keeper',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Open the real Google Lens to search what you see, translate, identify objects, solve questions and copy text properly.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFFB7B8C8),
                        height: 1.48,
                        fontSize: 13,
                      ),
                    ),
                    SizedBox(height: compact ? 16 : 23),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton.icon(
                        onPressed: _opening ? null : _openLens,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF766DFF),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(17),
                          ),
                        ),
                        icon: _opening
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.open_in_new_rounded),
                        label: Text(
                          _opening ? 'Opening Google Lens…' : 'Open Google Lens',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Row(
                children: [
                  Expanded(
                    child: _LensAbility(
                      icon: Icons.camera_alt_rounded,
                      title: 'Camera',
                      subtitle: 'Point and search',
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: _LensAbility(
                      icon: Icons.photo_library_rounded,
                      title: 'Gallery',
                      subtitle: 'Choose any image',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Row(
                children: [
                  Expanded(
                    child: _LensAbility(
                      icon: Icons.translate_rounded,
                      title: 'Translate',
                      subtitle: 'Read any language',
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: _LensAbility(
                      icon: Icons.content_copy_rounded,
                      title: 'Copy text',
                      subtitle: 'Use Google Lens OCR',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Camera, gallery and text selection happen inside Google Lens, so Keeper does not create a slow duplicate scanner.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF747B8D),
                  fontSize: 11.5,
                  height: 1.4,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LensAbility extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _LensAbility({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 86),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFF141A29),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF293247)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF27235B),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFFB6B0FF), size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF83899A),
                    fontSize: 10.5,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
