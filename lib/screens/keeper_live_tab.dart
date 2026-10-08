import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../services/gemini_answer_service.dart';
import '../services/keeper_ai_usage_service.dart';
import '../services/keeper_live_overlay_bridge.dart';
import '../services/ocr_text_service.dart';
import 'universal_search_screen.dart';

class KeeperLiveTab extends StatefulWidget {
  const KeeperLiveTab({super.key});

  @override
  State<KeeperLiveTab> createState() => _KeeperLiveTabState();
}

class _KeeperLiveTabState extends State<KeeperLiveTab> {
  final SpeechToText _speech = SpeechToText();
  final TextEditingController _controller = TextEditingController();

  bool _listening = false;
  bool _thinking = false;
  bool _startingLive = false;
  bool _liveRunning = false;
  String _answer = '';

  @override
  void initState() {
    super.initState();
    KeeperLiveOverlayBridge.setCaptureHandler(_answerCapturedScreen);
    _restoreLiveState();
  }

  Future<void> _restoreLiveState() async {
    final bool running = await KeeperLiveOverlayBridge.isRunning();
    if (mounted) setState(() => _liveRunning = running);
  }

  @override
  void dispose() {
    _speech.stop();
    _controller.dispose();
    KeeperLiveOverlayBridge.setCaptureHandler(null);
    super.dispose();
  }

  Future<void> _toggleLive() async {
    if (_startingLive) return;
    if (_liveRunning) {
      await KeeperLiveOverlayBridge.stop();
      if (mounted) setState(() => _liveRunning = false);
      return;
    }

    setState(() => _startingLive = true);
    final bool started = await KeeperLiveOverlayBridge.start();
    if (!mounted) return;
    setState(() {
      _startingLive = false;
      _liveRunning = started;
    });
    if (started) {
      _showMessage(
        'Keeper Live started. Go to any app and tap the floating K.',
      );
    } else {
      _showMessage(
        'Allow “display over other apps” and screen sharing to start Keeper Live.',
      );
    }
  }

  Future<void> _answerCapturedScreen(String path, String question) async {
    if (!mounted || _thinking) {
      await KeeperLiveOverlayBridge.showStatus(
        'Keeper is already answering. Please wait.',
      );
      return;
    }

    final KeeperAiUsageResult usage =
        await KeeperAiUsageService.reserveRequest();
    if (!usage.allowed) {
      await KeeperLiveOverlayBridge.showAnswer(
        'Aaj ki ${usage.limit} AI requests ki free limit complete ho gayi hai.',
      );
      return;
    }

    setState(() {
      _thinking = true;
      _answer = '';
    });
    await KeeperLiveOverlayBridge.showStatus(
      'Keeper is reading and understanding…',
    );

    try {
      final File file = File(path);
      final bytes = await file.readAsBytes();
      String recognizedText = '';
      try {
        recognizedText = await OcrTextService.extractTextFromImagePath(path);
      } catch (_) {
        // Gemini can still understand the captured image directly.
      }

      final String answer = await GeminiAnswerService.generateAnswer(
        question: question.trim().isEmpty
            ? 'Read this screen and give the most useful next action.'
            : question.trim(),
        knowledge: <GeminiKnowledgeFile>[
          GeminiKnowledgeFile(
            fileName: 'Keeper Live screen.png',
            category: 'Live Screen',
            extractedText: recognizedText.trim(),
            mimeType: 'image/png',
            bytes: bytes.length <= 8 * 1024 * 1024 ? bytes : null,
          ),
        ],
        allowGeneralKnowledgeFallback: true,
      );
      if (!mounted) return;
      setState(() {
        _answer = answer;
        _thinking = false;
      });
      await KeeperLiveOverlayBridge.showAnswer(answer);
    } catch (_) {
      if (mounted) setState(() => _thinking = false);
      await KeeperLiveOverlayBridge.showAnswer(
        'Keeper could not understand this screen. Check internet and tap Read screen again.',
      );
    }
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }

    final bool available = await _speech.initialize(
      onStatus: (String status) {
        if (!mounted) return;
        if (status == 'done' || status == 'notListening') {
          setState(() => _listening = false);
        }
      },
      onError: (_) {
        if (mounted) setState(() => _listening = false);
      },
    );
    if (!available) {
      _showMessage('Microphone permission is needed for Live Voice.');
      return;
    }

    setState(() => _listening = true);
    await _speech.listen(
      onResult: _onSpeechResult,
      listenOptions: SpeechListenOptions(
        partialResults: true,
        listenMode: ListenMode.dictation,
      ),
    );
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (!mounted) return;
    setState(() {
      _controller.text = result.recognizedWords;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
      if (result.finalResult) _listening = false;
    });
  }

  Future<void> _askWithoutScreen() async {
    final String question = _controller.text.trim();
    if (question.isEmpty || _thinking) {
      _showMessage('Type or speak a question first.');
      return;
    }
    final KeeperAiUsageResult usage =
        await KeeperAiUsageService.reserveRequest();
    if (!usage.allowed) {
      _showMessage(
        'Aaj ki ${usage.limit} AI requests ki free limit complete ho gayi hai.',
      );
      return;
    }

    setState(() {
      _thinking = true;
      _answer = '';
    });
    try {
      final String answer = await GeminiAnswerService.generateAnswer(
        question: question,
        knowledge: const <GeminiKnowledgeFile>[],
        allowGeneralKnowledgeFallback: true,
      );
      if (!mounted) return;
      setState(() {
        _answer = answer;
        _thinking = false;
      });
    } catch (_) {
      if (mounted) setState(() => _thinking = false);
      _showMessage('Keeper could not complete this request. Please retry.');
    }
  }

  Future<void> _copyAnswer() async {
    await Clipboard.setData(ClipboardData(text: _answer));
    _showMessage('Answer copied.');
  }

  Future<void> _shareAnswer() async {
    await SharePlus.instance.share(
      ShareParams(text: _answer, subject: 'Keeper Live answer'),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
      children: [
        Container(
          padding: const EdgeInsets.all(19),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF282267), Color(0xFF12192B)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF454087)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 47,
                    height: 47,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0E1423),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(
                      Icons.screen_share_rounded,
                      color: Color(0xFFB9B4FF),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Keeper Live Screen',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Works over websites and other apps',
                          style: TextStyle(
                            color: Color(0xFFB6B4C7),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _liveRunning
                          ? const Color(0xFF50D890)
                          : const Color(0xFF747B8D),
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'Start Live, open any app or website, then tap the floating K. Keeper captures only when you tap “Read screen” and shows the answer in the floating panel.',
                style: TextStyle(
                  color: Color(0xFFC3C0D5),
                  fontSize: 13,
                  height: 1.48,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: _startingLive ? null : _toggleLive,
                  style: FilledButton.styleFrom(
                    backgroundColor: _liveRunning
                        ? const Color(0xFF44242C)
                        : const Color(0xFF766DFF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: _startingLive
                      ? const SizedBox(
                          width: 19,
                          height: 19,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          _liveRunning
                              ? Icons.stop_circle_rounded
                              : Icons.play_circle_fill_rounded,
                        ),
                  label: Text(
                    _startingLive
                        ? 'Opening permissions…'
                        : _liveRunning
                        ? 'Stop Keeper Live'
                        : 'Start Live over other apps',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const Row(
          children: [
            Expanded(
              child: _LiveCapability(
                icon: Icons.touch_app_rounded,
                title: 'Tap to read',
                subtitle: 'No constant screenshots',
              ),
            ),
            SizedBox(width: 9),
            Expanded(
              child: _LiveCapability(
                icon: Icons.chat_bubble_outline_rounded,
                title: 'Floating answer',
                subtitle: 'Stay in the same app',
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Ask without screen',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const UniversalSearchScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.manage_search_rounded, size: 18),
              label: const Text('Find document'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          minLines: 2,
          maxLines: 4,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: _listening
                ? 'Listening…'
                : 'Type or speak to Keeper…',
            hintStyle: const TextStyle(color: Color(0xFF737B8E)),
            filled: true,
            fillColor: const Color(0xFF151B2A),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(17),
              borderSide: BorderSide.none,
            ),
            suffixIcon: IconButton(
              onPressed: _thinking ? null : _toggleListening,
              icon: Icon(
                _listening ? Icons.stop_circle_rounded : Icons.mic_rounded,
                color: _listening
                    ? const Color(0xFFFF7E87)
                    : const Color(0xFFAAA4FF),
              ),
            ),
          ),
        ),
        const SizedBox(height: 9),
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            onPressed: _thinking ? null : _askWithoutScreen,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF252B45),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            icon: _thinking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.bolt_rounded),
            label: Text(
              _thinking ? 'Keeper is thinking…' : 'Ask Keeper now',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        if (_answer.isNotEmpty) ...[
          const SizedBox(height: 13),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: const Color(0xFF151B2A),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF293247)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Keeper answer',
                        style: TextStyle(
                          color: Color(0xFFB9B4FF),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _copyAnswer,
                      icon: const Icon(Icons.copy_rounded, size: 19),
                    ),
                    IconButton(
                      onPressed: _shareAnswer,
                      icon: const Icon(Icons.share_outlined, size: 19),
                    ),
                  ],
                ),
                SelectableText(
                  _answer,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _LiveCapability extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _LiveCapability({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF141A29),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF293247)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFAAA4FF), size: 22),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF858B9C),
                    fontSize: 9.8,
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
