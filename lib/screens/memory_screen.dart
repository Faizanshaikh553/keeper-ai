import 'package:flutter/material.dart';

import '../models/memory_model.dart';
import '../services/memory_service.dart';

class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key});

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  KeeperMemorySpace _selectedSpace = KeeperMemorySpace.personal;
  bool _isLoading = true;
  bool _isWorking = false;
  List<KeeperMemory> _memories = const <KeeperMemory>[];

  @override
  void initState() {
    super.initState();
    _loadMemories();
  }

  Future<void> _loadMemories() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final List<KeeperMemory> memories =
          await KeeperMemoryService.loadMemories(space: _selectedSpace);

      if (!mounted) return;
      setState(() {
        _memories = memories;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showMessage(error.toString().replaceFirst('Bad state: ', ''));
    }
  }

  Future<void> _switchSpace(KeeperMemorySpace space) async {
    if (_selectedSpace == space || _isWorking) return;
    setState(() {
      _selectedSpace = space;
      _memories = const <KeeperMemory>[];
    });
    await _loadMemories();
  }

  Future<void> _addMemory() async {
    final TextEditingController controller = TextEditingController();

    final String? content = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF141A29),
          title: const Text(
            'Save a memory',
            style: TextStyle(color: Colors.white),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 3,
            maxLines: 7,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Example: My preferred answer language is Hinglish.',
              hintStyle: const TextStyle(color: Color(0xFF747B8F)),
              filled: true,
              fillColor: const Color(0xFF0E1320),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final String value = controller.text.trim();
                if (value.isNotEmpty) Navigator.pop(dialogContext, value);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    controller.dispose();
    if (content == null || content.trim().isEmpty) return;

    setState(() => _isWorking = true);
    try {
      await KeeperMemoryService.saveMemory(
        content: content,
        space: _selectedSpace,
      );
      await _loadMemories();
      _showMessage('Memory saved.');
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _deleteMemory(KeeperMemory memory) async {
    final bool confirmed = await _confirm(
      title: 'Delete memory?',
      message: memory.content,
      confirmLabel: 'Delete',
    );
    if (!confirmed) return;

    setState(() => _isWorking = true);
    try {
      await KeeperMemoryService.deleteMemory(memory);
      if (!mounted) return;
      setState(() {
        _memories = _memories.where((item) => item.id != memory.id).toList();
      });
      _showMessage('Memory deleted.');
    } catch (error) {
      _showMessage(error.toString());
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _deleteAll() async {
    if (_memories.isEmpty) return;

    final bool confirmed = await _confirm(
      title: 'Delete all memories?',
      message:
          'This will permanently delete all ${_selectedSpace.name} memories.',
      confirmLabel: 'Delete all',
    );
    if (!confirmed) return;

    setState(() => _isWorking = true);
    try {
      final int count = await KeeperMemoryService.deleteAll(
        space: _selectedSpace,
      );
      if (!mounted) return;
      setState(() => _memories = const <KeeperMemory>[]);
      _showMessage('$count memories deleted.');
    } catch (error) {
      _showMessage(error.toString());
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              backgroundColor: const Color(0xFF141A29),
              title: Text(title, style: const TextStyle(color: Colors.white)),
              content: Text(
                message,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFB4BAC9)),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE25D68),
                  ),
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(confirmLabel),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatDate(DateTime date) {
    final DateTime local = date.toLocal();
    final String day = local.day.toString().padLeft(2, '0');
    final String month = local.month.toString().padLeft(2, '0');
    return '$day/$month/${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D18),
      appBar: AppBar(
        backgroundColor: const Color(0xFF090D18),
        foregroundColor: Colors.white,
        title: const Text(
          'Keeper Memory',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Delete all',
            onPressed: _isWorking || _memories.isEmpty ? null : _deleteAll,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isWorking ? null : _addMemory,
        backgroundColor: const Color(0xFF766DFF),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add memory'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Keeper saves only what you explicitly ask it to remember.',
                    style: TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _SpaceButton(
                          label: 'Personal',
                          icon: Icons.person_outline_rounded,
                          selected:
                              _selectedSpace == KeeperMemorySpace.personal,
                          onTap: () => _switchSpace(KeeperMemorySpace.personal),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _SpaceButton(
                          label: 'Organization',
                          icon: Icons.groups_2_outlined,
                          selected:
                              _selectedSpace == KeeperMemorySpace.organization,
                          onTap: () =>
                              _switchSpace(KeeperMemorySpace.organization),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF8C83FF),
                      ),
                    )
                  : _memories.isEmpty
                  ? _EmptyMemoryState(space: _selectedSpace)
                  : RefreshIndicator(
                      onRefresh: _loadMemories,
                      color: const Color(0xFF766DFF),
                      backgroundColor: const Color(0xFF151B2A),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(18, 4, 18, 110),
                        itemCount: _memories.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 11),
                        itemBuilder: (context, index) {
                          final KeeperMemory memory = _memories[index];
                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF141A29),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: const Color(0xFF272E40),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF292653),
                                    borderRadius: BorderRadius.circular(13),
                                  ),
                                  child: const Icon(
                                    Icons.psychology_alt_rounded,
                                    color: Color(0xFFB3ADFF),
                                  ),
                                ),
                                const SizedBox(width: 13),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        memory.title,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        memory.content,
                                        style: const TextStyle(
                                          color: Color(0xFFB7BDCB),
                                          fontSize: 13,
                                          height: 1.45,
                                        ),
                                      ),
                                      const SizedBox(height: 9),
                                      Text(
                                        'Updated ${_formatDate(memory.updatedAt)}',
                                        style: const TextStyle(
                                          color: Color(0xFF737B8E),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Delete',
                                  onPressed: _isWorking
                                      ? null
                                      : () => _deleteMemory(memory),
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: Color(0xFFE07B83),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpaceButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _SpaceButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFF292653) : const Color(0xFF141A29),
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: selected
                  ? const Color(0xFF766DFF)
                  : const Color(0xFF292F40),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 19,
                color: selected ? const Color(0xFFBBB6FF) : Colors.white70,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white70,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
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

class _EmptyMemoryState extends StatelessWidget {
  final KeeperMemorySpace space;

  const _EmptyMemoryState({required this.space});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.psychology_alt_outlined,
              color: Color(0xFF716B9B),
              size: 58,
            ),
            const SizedBox(height: 15),
            Text(
              'No ${space.name} memories yet',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'In chat, say “Remember this...” or add a memory here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF8B92A5), height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}
