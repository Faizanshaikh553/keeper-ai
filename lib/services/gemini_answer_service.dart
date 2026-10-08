import 'dart:async';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_auth/firebase_auth.dart';

class GeminiKnowledgeFile {
  final String fileName;
  final String category;
  final String extractedText;
  final String mimeType;
  final Uint8List? bytes;

  const GeminiKnowledgeFile({
    required this.fileName,
    required this.category,
    required this.extractedText,
    required this.mimeType,
    this.bytes,
  });

  bool get hasReadableText => extractedText.trim().isNotEmpty;

  bool get hasFileBytes => bytes != null && bytes!.isNotEmpty;

  bool get isSupportedMultimodalFile {
    return mimeType == 'image/jpeg' ||
        mimeType == 'image/png' ||
        mimeType == 'image/webp' ||
        mimeType == 'application/pdf' ||
        mimeType == 'text/plain';
  }
}

class GeminiAnswerService {
  GeminiAnswerService._();

  static const int _maximumFilesPerRequest = 2;
  static const int _maximumContextCharacters = 6500;
  static const int _maximumInlineRequestBytes = 6 * 1024 * 1024;
  static const Duration _requestTimeout = Duration(seconds: 20);
  static const int _maxAttempts = 2;
  static const String _primaryModelName = 'gemini-3.5-flash';
  static GenerativeModel? _cachedModel;

  static Future<GenerativeModel> _createModel() async {
    final GenerativeModel? cached = _cachedModel;
    if (cached != null) return cached;

    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Firebase Authentication session is unavailable.');
    }

    // Firebase AI Logic handles the authenticated session. Avoid fetching an ID
    // token on every question because that adds avoidable network latency.
    final FirebaseAI ai = FirebaseAI.googleAI();
    final GenerativeModel model = ai.generativeModel(
      model: _primaryModelName,
      generationConfig: GenerationConfig(
        temperature: 0.15,
        maxOutputTokens: 1400,
      ),
    );

    _cachedModel = model;
    return model;
  }

  static Future<String> generateAnswer({
    required String question,
    required List<GeminiKnowledgeFile> knowledge,
    List<String> conversationContext = const <String>[],
    List<String> memoryContext = const <String>[],
    bool allowGeneralKnowledgeFallback = false,
  }) async {
    final String cleanedQuestion = question.trim();

    if (cleanedQuestion.isEmpty) {
      return 'Please enter a question.';
    }

    final List<GeminiKnowledgeFile> selectedFiles = knowledge
        .take(_maximumFilesPerRequest)
        .toList();

    final List<Part> parts = <Part>[
      TextPart(
        _buildPrompt(
          question: cleanedQuestion,
          knowledge: selectedFiles,
          conversationContext: conversationContext,
          memoryContext: memoryContext,
          allowGeneralKnowledgeFallback: allowGeneralKnowledgeFallback,
        ),
      ),
    ];

    int totalAttachedBytes = 0;

    for (final GeminiKnowledgeFile file in selectedFiles) {
      if (!file.hasFileBytes || !file.isSupportedMultimodalFile) {
        continue;
      }

      final int fileSize = file.bytes!.length;

      if (totalAttachedBytes + fileSize > _maximumInlineRequestBytes) {
        continue;
      }

      parts.add(InlineDataPart(file.mimeType, file.bytes!));

      totalAttachedBytes += fileSize;
    }

    try {
      final GenerativeModel model = await _createModel();
      Object? lastError;

      for (int attempt = 1; attempt <= _maxAttempts; attempt++) {
        try {
          final GenerateContentResponse response = await model
              .generateContent([Content.multi(parts)])
              .timeout(_requestTimeout);

          final String answer = response.text?.trim() ?? '';
          if (answer.isNotEmpty) {
            return _cleanFinalAnswer(answer);
          }

          lastError = StateError('Empty Gemini response');
        } catch (error, stackTrace) {
          lastError = error;
          developer.log(
            'Gemini attempt $attempt/$_maxAttempts failed: $error',
            name: 'KEEPER_AI',
            error: error,
            stackTrace: stackTrace,
          );

          if (attempt < _maxAttempts && _isTransientError(error)) {
            await Future<void>.delayed(const Duration(milliseconds: 350));
            continue;
          }
          rethrow;
        }
      }

      throw lastError ?? StateError('Keeper AI returned an empty response.');
    } on FirebaseAuthException catch (error, stackTrace) {
      developer.log(
        'FirebaseAuthException: ${error.code} ${error.message}',
        name: 'KEEPER_AI',
        error: error,
        stackTrace: stackTrace,
      );
      return _friendlyAuthError(error);
    } on FirebaseAIException catch (error, stackTrace) {
      developer.log(
        'FirebaseAIException: ${error.message}',
        name: 'KEEPER_AI',
        error: error,
        stackTrace: stackTrace,
      );
      return _friendlyFirebaseError(error.message.toLowerCase());
    } on FirebaseException catch (error, stackTrace) {
      developer.log(
        'FirebaseException: ${error.code} ${error.message}',
        name: 'KEEPER_AI',
        error: error,
        stackTrace: stackTrace,
      );
      return _friendlyFirebaseError(
        '${error.code} ${error.message ?? ''}'.toLowerCase(),
      );
    } on TimeoutException catch (error, stackTrace) {
      developer.log(
        'Keeper AI timeout: $error',
        name: 'KEEPER_AI',
        error: error,
        stackTrace: stackTrace,
      );
      return 'Keeper AI is taking longer than usual right now. Please try again.';
    } catch (error, stackTrace) {
      developer.log(
        'Keeper AI request failed: $error',
        name: 'KEEPER_AI',
        error: error,
        stackTrace: stackTrace,
      );
      return _friendlyUnknownError(error);
    }

  }

  static bool _isTransientError(Object error) {
    final String message = error.toString().toLowerCase();
    return error is TimeoutException ||
        message.contains('timeout') ||
        message.contains('network') ||
        message.contains('socket') ||
        message.contains('connection') ||
        message.contains('unavailable') ||
        message.contains('overloaded') ||
        message.contains('503') ||
        message.contains('500') ||
        message.contains('429') ||
        message.contains('resource exhausted');
  }

  static String _cleanFinalAnswer(String value) {
    String cleaned = value
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();

    if (cleaned.isEmpty) return cleaned;

    // Some model responses occasionally repeat the complete answer twice.
    // Remove only near-exact repeated halves so legitimate repeated words remain.
    final List<String> paragraphs = cleaned
        .split(RegExp(r'\n\s*\n'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();

    if (paragraphs.length >= 2 && paragraphs.length.isEven) {
      final int half = paragraphs.length ~/ 2;
      final String firstHalf = _normaliseForComparison(
        paragraphs.take(half).join('\n\n'),
      );
      final String secondHalf = _normaliseForComparison(
        paragraphs.skip(half).join('\n\n'),
      );

      if (firstHalf.isNotEmpty && firstHalf == secondHalf) {
        cleaned = paragraphs.take(half).join('\n\n').trim();
      }
    }

    final List<String> deduplicated = <String>[];
    String previous = '';

    for (final String paragraph in cleaned.split(RegExp(r'\n\s*\n'))) {
      final String current = paragraph.trim();
      if (current.isEmpty) continue;

      final String fingerprint = _normaliseForComparison(current);
      if (fingerprint.isNotEmpty && fingerprint == previous) {
        continue;
      }

      deduplicated.add(current);
      previous = fingerprint;
    }

    return deduplicated.join('\n\n').trim();
  }

  static String _normaliseForComparison(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u0900-\u097f]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }


  static String _friendlyAuthError(FirebaseAuthException error) {
    if (error.code == 'network-request-failed') {
      return 'Keeper AI could not verify your session because the network is unavailable. Please retry.';
    }

    return 'Keeper could not verify this login session. Please sign in again.';
  }

  static String _friendlyFirebaseError(String message) {
    if (message.contains('app check')) {
      return 'Keeper AI app verification failed. Install the latest official Play testing build and retry.';
    }

    if (message.contains('unauthenticated') ||
        message.contains('authentication') ||
        message.contains('401')) {
      return 'Keeper AI could not verify your login. Sign out, sign in again, and retry.';
    }

    if (message.contains('permission') || message.contains('403')) {
      return 'Keeper AI access was rejected by Firebase verification. Please retry from the latest Play testing build.';
    }

    if (message.contains('quota') ||
        message.contains('429') ||
        message.contains('resource exhausted')) {
      return 'Keeper AI usage limit is temporarily reached. Please retry after a short time.';
    }

    if (message.contains('404') ||
        message.contains('model') ||
        message.contains('unsupported')) {
      return 'Keeper AI is updating its model connection. Please retry once.';
    }

    if (message.contains('500') ||
        message.contains('503') ||
        message.contains('internal') ||
        message.contains('overloaded') ||
        message.contains('unavailable')) {
      return 'Keeper AI service is temporarily busy. Please retry once.';
    }

    return 'Keeper AI request was rejected by Firebase. Please check Firebase AI Logic settings.';
  }

  static String _friendlyUnknownError(Object? error) {
    final String message = error?.toString().toLowerCase() ?? '';

    if (message.contains('app check') ||
        message.contains('permission') ||
        message.contains('403')) {
      return 'Keeper AI app verification failed. Install the latest official Play testing build and retry.';
    }

    if (message.contains('unauthenticated') ||
        message.contains('authentication') ||
        message.contains('401') ||
        message.contains('token is unavailable')) {
      return 'Keeper could not verify this login session. Please sign in again.';
    }

    if (message.contains('404') ||
        message.contains('model') ||
        message.contains('unsupported')) {
      return 'Keeper AI is updating its model connection. Please retry once.';
    }

    if (message.contains('quota') ||
        message.contains('429') ||
        message.contains('resource exhausted')) {
      return 'Keeper AI usage is temporarily busy. Please retry after a short time.';
    }

    if (message.contains('socket') ||
        message.contains('network') ||
        message.contains('connection')) {
      return 'Keeper AI could not reach Firebase. Please retry once.';
    }

    if (message.contains('timeout')) {
      return 'Keeper AI is taking longer than usual right now. Please retry once.';
    }

    return 'Keeper AI could not complete this request. Please retry once.';
  }

  static String _buildPrompt({
    required String question,
    required List<GeminiKnowledgeFile> knowledge,
    required List<String> conversationContext,
    required List<String> memoryContext,
    required bool allowGeneralKnowledgeFallback,
  }) {
    final StringBuffer context = StringBuffer();

    for (int index = 0; index < knowledge.length; index++) {
      final GeminiKnowledgeFile file = knowledge[index];

      context.writeln('DOCUMENT ${index + 1}');
      context.writeln('File name: ${file.fileName}');
      context.writeln('Category: ${file.category}');
      context.writeln('MIME type: ${file.mimeType}');

      if (file.hasFileBytes) {
        context.writeln(
          'The original file is attached. Inspect its visible layout, '
          'handwriting, tables, questions, columns and diagrams.',
        );
      }

      if (file.hasReadableText) {
        context.writeln('Extracted text:');
        context.writeln(
          _limitText(file.extractedText, _maximumContextCharacters),
        );
      }

      context.writeln('---');
    }

    final String recentConversation = conversationContext.isEmpty
        ? 'No previous conversation context.'
        : conversationContext.take(8).join('\n');

    final String savedMemory = memoryContext.isEmpty
        ? 'No relevant saved memories.'
        : memoryContext.take(8).join('\n');

    final String documentRule;

    if (knowledge.isEmpty || allowGeneralKnowledgeFallback) {
      documentRule = '''
You may use reliable general knowledge when the uploaded documents do not contain the answer.
Never claim that general knowledge came from an uploaded document.
''';
    } else {
      documentRule = '''
Answer only from the uploaded knowledge and relevant saved memory. If the answer is not present in either, clearly say so.
''';
    }

    return '''
You are Keeper AI, a fast and capable universal knowledge assistant.

Understand natural English, Hinglish, informal language, spelling mistakes,
short questions and long multi-part messages.

Language behavior:
- Reply in English when the user writes English.
- Reply in natural Roman-script Hinglish when the user writes Hinglish.
- When the user mixes both, reply in the same comfortable mixed style.
- Never switch to Devanagari unless the user requests it.

Answer behavior:
- First understand the user's actual intent.
- For long messages, answer every important requested part.
- Give a direct and useful answer.
- Use short headings and numbered points when helpful.
- Never expose API details, JSON or internal errors.
- Never invent facts from documents.
- Preserve exact names, numbers, dates, marks and question text.
- Do not add a Sources section; Keeper displays sources separately.
- Decide the answer length yourself: be concise for simple questions, and give a
  fuller structured explanation when the question genuinely needs detail.
- For current/general-world questions, answer from your reliable general knowledge
  when no Keeper document context is relevant. Do not say you cannot answer merely
  because there is no uploaded document.
- Never repeat the answer, summary, heading or the same paragraph twice.
- When using numbered points or bullet points, leave one blank line between points.
- Write mathematical formulas as valid LaTeX on their own line between \\[ and \\].
- Keep the explanation outside the formula line so Keeper can render it cleanly.

$documentRule

RECENT CONVERSATION:
$recentConversation

RELEVANT SAVED MEMORY:
$savedMemory

Memory rules:
- Saved memory is user-provided context, not an uploaded document.
- Use it only when relevant to the current question.
- Never claim a memory was found in a document.
- Do not reveal unrelated memories.

USER QUESTION:
$question

UPLOADED KNOWLEDGE:
${context.toString()}
''';
  }

  static String _limitText(String value, int maximumCharacters) {
    final String cleaned = value
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();

    if (cleaned.length <= maximumCharacters) {
      return cleaned;
    }

    return '${cleaned.substring(0, maximumCharacters)}...';
  }
}
