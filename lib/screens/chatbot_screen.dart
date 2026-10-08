import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:http/http.dart' as http;
import '../services/gemini_answer_service.dart';
import '../services/keeper_ai_usage_service.dart';
import '../services/keeper_knowledge_engine.dart';
import '../services/local_answer_service.dart';
import '../services/text_extractor_service.dart';
import '../models/memory_model.dart';
import '../services/memory_service.dart';
import 'memory_screen.dart';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'document_viewer_screen.dart';
import 'chat_history_screen.dart';

enum KnowledgeScope { personal, organization, all }

class ChatSource {
  final String fileName;
  final String category;
  final String fileUrl;
  final String snippet;
  final double score;

  final String sourceType;
  final int? pageNumber;
  final String highlightedText;
  final String thumbnailUrl;

  const ChatSource({
    required this.fileName,
    required this.category,
    required this.fileUrl,
    required this.snippet,
    required this.score,
    this.sourceType = 'document',
    this.pageNumber,
    this.highlightedText = '',
    this.thumbnailUrl = '',
  });

  bool get isImage {
    final String value = '$fileName $fileUrl'.toLowerCase();

    return value.contains('.jpg') ||
        value.contains('.jpeg') ||
        value.contains('.png') ||
        value.contains('.webp');
  }

  bool get isPdf {
    final String value = '$fileName $fileUrl'.toLowerCase();
    return value.contains('.pdf');
  }

  String get typeLabel {
    if (isImage) return 'Image';
    if (isPdf) return 'PDF';
    return sourceType;
  }

  String get previewUrl {
    if (thumbnailUrl.trim().isNotEmpty) {
      return thumbnailUrl;
    }

    if (isImage) {
      return fileUrl;
    }

    return '';
  }
}

class ChatAttachment {
  final String name;
  final String path;
  final String mimeType;

  const ChatAttachment({
    required this.name,
    required this.path,
    required this.mimeType,
  });

  bool get isImage => mimeType.startsWith('image/');
  bool get isPdf => mimeType == 'application/pdf';
}

class ChatMessage {
  final String id;
  final String text;
  final bool isUser;
  final DateTime createdAt;
  final List<ChatSource> sources;
  final bool isError;
  final List<ChatAttachment> attachments;

  const ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.createdAt,
    this.sources = const [],
    this.isError = false,
    this.attachments = const [],
  });
}

class _RankedDocument {
  final Map<String, dynamic> document;
  final double score;
  final String snippet;

  const _RankedDocument({
    required this.document,
    required this.score,
    required this.snippet,
  });
}

class ChatbotScreen extends StatefulWidget {
  final String? initialChatId;

  const ChatbotScreen({super.key, this.initialChatId});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  static final Map<String, List<Map<String, dynamic>>>
  _personalKnowledgeMemoryCache = {};
  static final Map<String, List<Map<String, dynamic>>>
  _organizationKnowledgeMemoryCache = {};
  static final Map<String, String> _organizationIdMemoryCache = {};
  static final Map<String, ChatMessage> _answerMemoryCache = {};
  final TextEditingController _messageController = TextEditingController();

  final ScrollController _scrollController = ScrollController();

  final FocusNode _messageFocusNode = FocusNode();

  final ImagePicker _imagePicker = ImagePicker();

  final List<ChatAttachment> _selectedAttachments = [];
  bool _isPickingAttachment = false;
  bool _isSendLocked = false;

  final List<ChatMessage> _messages = [];

  String? _activeChatId;
  String _activeChatTitle = 'New Chat';
  bool _isLoadingSavedChat = false;

  List<Map<String, dynamic>> _personalDocuments = [];
  List<Map<String, dynamic>> _organizationDocuments = [];

  KnowledgeScope _selectedScope = KnowledgeScope.personal;

  // Document sync is intentionally non-blocking; chat must stay usable while
  // Supabase knowledge refreshes in the background.
  bool _isLoadingKnowledge = false;
  Future<void>? _knowledgeLoadFuture;
  DateTime? _lastKnowledgeSync;
  String? _knowledgeLoadError;
  bool _isThinking = false;
  bool _isSavingAttachments = false;
  int _savedAttachmentCount = 0;
  int _totalAttachmentsToSave = 0;

  @override
  void initState() {
    super.initState();

    _activeChatId = widget.initialChatId;

    if (_activeChatId != null && _activeChatId!.isNotEmpty) {
      _loadSavedChat(_activeChatId!);
    } else {
      _addWelcomeMessage();
    }

    _restoreCachedKnowledgeAndRefresh();
  }

  void _addWelcomeMessage() {
    _messages
      ..clear()
      ..add(
        ChatMessage(
          id: _createId(),
          text:
              'Hi! I am Keeper AI.\n\nAsk me anything about your uploaded documents. I will search your knowledge, find relevant information and show the source documents.',
          isUser: false,
          createdAt: DateTime.now(),
        ),
      );
  }

  Map<String, dynamic> _serializeSource(ChatSource source) {
    return {
      'fileName': source.fileName,
      'category': source.category,
      'fileUrl': source.fileUrl,
      'snippet': source.snippet,
      'score': source.score,
      'sourceType': source.sourceType,
      'pageNumber': source.pageNumber,
      'highlightedText': source.highlightedText,
      'thumbnailUrl': source.thumbnailUrl,
    };
  }

  Map<String, dynamic> _serializeMessage(ChatMessage message) {
    return {
      'id': message.id,
      'text': message.text,
      'isUser': message.isUser,
      'createdAt': Timestamp.fromDate(message.createdAt),
      'isError': message.isError,
      'sources': message.sources.map(_serializeSource).toList(),
      'attachments': message.attachments
          .map(
            (attachment) => {
              'name': attachment.name,
              'mimeType': attachment.mimeType,
            },
          )
          .toList(),
    };
  }

  ChatSource _deserializeSource(Map<String, dynamic> data) {
    return ChatSource(
      fileName: data['fileName']?.toString() ?? 'Unnamed document',
      category: data['category']?.toString() ?? 'Other',
      fileUrl: data['fileUrl']?.toString() ?? '',
      snippet: data['snippet']?.toString() ?? '',
      score: (data['score'] as num?)?.toDouble() ?? 0,
      sourceType: data['sourceType']?.toString() ?? 'document',
      pageNumber: data['pageNumber'] as int?,
      highlightedText: data['highlightedText']?.toString() ?? '',
      thumbnailUrl: data['thumbnailUrl']?.toString() ?? '',
    );
  }

  ChatMessage _deserializeMessage(Map<String, dynamic> data) {
    final List<ChatSource> sources =
        (data['sources'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((item) => _deserializeSource(Map<String, dynamic>.from(item)))
            .toList();

    final dynamic createdAtValue = data['createdAt'];

    final DateTime createdAt = createdAtValue is Timestamp
        ? createdAtValue.toDate()
        : DateTime.tryParse(createdAtValue?.toString() ?? '') ?? DateTime.now();

    return ChatMessage(
      id: data['id']?.toString() ?? _createId(),
      text: data['text']?.toString() ?? '',
      isUser: data['isUser'] as bool? ?? false,
      createdAt: createdAt,
      sources: sources,
      isError: data['isError'] as bool? ?? false,
    );
  }

  String _chatTitleFromQuestion(String question) {
    final String cleaned = question.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (cleaned.isEmpty) return 'New Chat';
    if (cleaned.length <= 45) return cleaned;

    return '${cleaned.substring(0, 45)}...';
  }

  Future<void> _reportAiMessage(ChatMessage message) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showMessage('Please sign in again to report this answer.');
      return;
    }

    final String? reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        backgroundColor: const Color(0xFF141A29),
        title: const Text(
          'Report this AI answer',
          style: TextStyle(color: Colors.white),
        ),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'harmful_or_offensive'),
            child: const Text(
              'Harmful or offensive',
              style: TextStyle(color: Colors.white),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'inaccurate'),
            child: const Text(
              'Inaccurate or misleading',
              style: TextStyle(color: Colors.white),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'other'),
            child: const Text('Other', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (reason == null) return;

    try {
      final String answer = _cleanAssistantAnswer(message.text);
      await FirebaseFirestore.instance.collection('ai_content_reports').add({
        'userId': user.uid,
        'messageId': message.id,
        'chatId': _activeChatId,
        'reason': reason,
        'answerPreview': answer.length > 2000
            ? answer.substring(0, 2000)
            : answer,
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      _showMessage('Thanks. This AI answer has been reported.');
    } catch (_) {
      if (!mounted) return;
      _showMessage('Could not send the report. Please try again.');
    }
  }

  Future<void> _ensureActiveChat(String firstQuestion) async {
    if (_activeChatId != null && _activeChatId!.isNotEmpty) return;

    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final DocumentReference<Map<String, dynamic>> reference = FirebaseFirestore
        .instance
        .collection('users')
        .doc(user.uid)
        .collection('keeper_chats')
        .doc();

    _activeChatId = reference.id;
    _activeChatTitle = _chatTitleFromQuestion(firstQuestion);

    await reference.set({
      'title': _activeChatTitle,
      'scope': _selectedScope.name,
      'isPinned': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'messageCount': 0,
      'lastMessage': '',
      'messages': <Map<String, dynamic>>[],
    });
  }

  Future<void> _persistCurrentChat() async {
    final User? user = FirebaseAuth.instance.currentUser;
    final String? chatId = _activeChatId;

    if (user == null || chatId == null || chatId.isEmpty) return;

    final String lastMessage = _messages.isEmpty
        ? ''
        : _messages.last.text.replaceAll(RegExp(r'\s+'), ' ').trim();

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('keeper_chats')
          .doc(chatId)
          .set({
            'title': _activeChatTitle,
            'scope': _selectedScope.name,
            'updatedAt': FieldValue.serverTimestamp(),
            'messageCount': _messages.length,
            'lastMessage': lastMessage.length > 100
                ? '${lastMessage.substring(0, 100)}...'
                : lastMessage,
            'messages': _messages.map(_serializeMessage).toList(),
          }, SetOptions(merge: true));
    } catch (_) {
      // Chat persistence should never block the AI experience.
    }
  }

  Future<void> _loadSavedChat(String chatId) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isLoadingSavedChat = true;
    });

    try {
      final DocumentSnapshot<Map<String, dynamic>> snapshot =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('keeper_chats')
              .doc(chatId)
              .get();

      final Map<String, dynamic>? data = snapshot.data();

      if (data == null) {
        _startNewChat();
        return;
      }

      final List<ChatMessage> loadedMessages =
          (data['messages'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map(
                (item) => _deserializeMessage(Map<String, dynamic>.from(item)),
              )
              .toList();

      if (!mounted) return;

      setState(() {
        _activeChatId = chatId;
        _activeChatTitle = data['title']?.toString() ?? 'Saved Chat';
        _messages
          ..clear()
          ..addAll(loadedMessages);

        if (_messages.isEmpty) {
          _addWelcomeMessage();
        }

        final String savedScope = data['scope']?.toString() ?? 'personal';

        _selectedScope = KnowledgeScope.values.firstWhere(
          (scope) => scope.name == savedScope,
          orElse: () => KnowledgeScope.personal,
        );

        _isLoadingSavedChat = false;
      });

      _scrollToBottom();
      unawaited(_persistCurrentChat());
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isLoadingSavedChat = false;
      });

      _showMessage('Unable to open this saved chat.');
    }
  }

  void _startNewChat() {
    if (!mounted) return;

    setState(() {
      _activeChatId = null;
      _activeChatTitle = 'New Chat';
      _selectedAttachments.clear();
      _isThinking = false;
      _addWelcomeMessage();
    });
  }

  Future<void> _openChatHistory() async {
    final String? selectedChatId = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const ChatHistoryScreen()),
    );

    if (!mounted || selectedChatId == null) return;

    if (selectedChatId == '__new__') {
      _startNewChat();
      return;
    }

    await _loadSavedChat(selectedChatId);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _messageFocusNode.dispose();
    super.dispose();
  }

  String _createId() {
    return '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(99999)}';
  }

  String _messageFingerprint(ChatMessage message) {
    return message.text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  bool _appendMessageIfNotDuplicate(ChatMessage message) {
    if (!message.isUser) {
      final String fingerprint = _messageFingerprint(message);

      for (final ChatMessage existing in _messages.reversed.take(4)) {
        if (existing.isUser) continue;

        final bool sameText = _messageFingerprint(existing) == fingerprint;
        final bool closeInTime =
            message.createdAt.difference(existing.createdAt).abs() <
            const Duration(seconds: 8);

        if (sameText && closeInTime) {
          return false;
        }
      }
    }

    _messages.add(message);
    return true;
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _restoreCachedKnowledgeAndRefresh() {
    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _isLoadingKnowledge = false;
      unawaited(_loadKnowledge(showLoading: false));
      return;
    }

    final List<Map<String, dynamic>> cachedPersonal =
        _personalKnowledgeMemoryCache[user.uid] ?? const [];
    final String? cachedOrganizationId = _organizationIdMemoryCache[user.uid];
    final List<Map<String, dynamic>> cachedOrganization =
        cachedOrganizationId == null
        ? const []
        : (_organizationKnowledgeMemoryCache[cachedOrganizationId] ?? const []);

    final bool hasCachedKnowledge =
        cachedPersonal.isNotEmpty || cachedOrganization.isNotEmpty;

    if (hasCachedKnowledge) {
      _personalDocuments = List<Map<String, dynamic>>.from(cachedPersonal);
      _organizationDocuments = List<Map<String, dynamic>>.from(
        cachedOrganization,
      );
      _isLoadingKnowledge = false;
    }

    // Never block the chat composer on a remote knowledge refresh. A document
    // question will explicitly wait for _loadKnowledge when needed.
    unawaited(_loadKnowledge(showLoading: false));
  }

  Future<String?> _loadUserOrganizationId(String userId) async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> userDocument =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .get()
              .timeout(const Duration(seconds: 3));

      final Map<String, dynamic>? data = userDocument.data();

      if (data == null) {
        return null;
      }

      final dynamic organizationValue =
          data['organization_id'] ??
          data['organizationId'] ??
          data['current_organization_id'] ??
          data['currentOrganizationId'];

      final String organizationId = organizationValue?.toString().trim() ?? '';

      if (organizationId.isEmpty) {
        return null;
      }

      return organizationId;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadKnowledge({bool showLoading = true}) {
    final Future<void>? existing = _knowledgeLoadFuture;
    if (existing != null) return existing;

    final Future<void> future = _loadKnowledgeImpl(showLoading: showLoading);
    _knowledgeLoadFuture = future.whenComplete(() {
      _knowledgeLoadFuture = null;
    });
    return _knowledgeLoadFuture!;
  }

  Future<void> _loadKnowledgeImpl({bool showLoading = true}) async {
    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (!mounted) return;
      setState(() {
        _isLoadingKnowledge = false;
        _knowledgeLoadError = 'No signed-in user.';
      });
      return;
    }

    if (showLoading && mounted) {
      setState(() => _isLoadingKnowledge = true);
    } else {
      _isLoadingKnowledge = true;
    }

    final supabase.SupabaseClient client = supabase.Supabase.instance.client;

    // Keep the currently visible/cached documents until a new personal fetch
    // succeeds. A temporary network timeout must never wipe working knowledge.
    List<Map<String, dynamic>>? loadedPersonal;
    List<Map<String, dynamic>> loadedOrganization = _organizationDocuments;

    Object? personalError;

    // Personal and organization documents were previously fetched one after
    // another (up to 25s + 12s back to back). On a slow connection that
    // stacked into a very long wait that felt like the app had frozen.
    // Running both fetches concurrently keeps the worst case close to the
    // slower of the two instead of the sum of both.
    Future<void> loadPersonal() async {
      try {
        // IMPORTANT: This is intentionally the same simple fetch shape used
        // by the Documents area: select() + user_id. Do not add an explicit
        // column list or a space filter to the database query.
        final dynamic response = await client
            .from('documents')
            .select()
            .eq('user_id', user.uid)
            .timeout(const Duration(seconds: 25));

        final List<dynamic> rows = response is List
            ? List<dynamic>.from(response)
            : <dynamic>[];

        final List<Map<String, dynamic>> parsed = rows
            .whereType<Map>()
            .map((item) => _normalizeLoadedDocument(
                  Map<String, dynamic>.from(item),
                ))
            .toList();

        _sortDocumentsNewestFirst(parsed);
        loadedPersonal = parsed;
        _personalKnowledgeMemoryCache[user.uid] =
            List<Map<String, dynamic>>.from(parsed);
      } catch (error, stackTrace) {
        personalError = error;
        developer.log(
          'Keeper personal document load failed',
          error: error,
          stackTrace: stackTrace,
          name: 'ChatbotScreen',
        );

        // If the database briefly fails but we already have a memory cache,
        // preserve it instead of reporting zero documents.
        final cached = _personalKnowledgeMemoryCache[user.uid];
        if (cached != null && cached.isNotEmpty) {
          loadedPersonal = List<Map<String, dynamic>>.from(cached);
        }
      }
    }

    // Organization loading is optional and must never affect personal docs.
    Future<void> loadOrganization() async {
      try {
        String? organizationId = _organizationIdMemoryCache[user.uid];
        organizationId ??= await _loadUserOrganizationId(user.uid);

        if (organizationId != null && organizationId.isNotEmpty) {
          _organizationIdMemoryCache[user.uid] = organizationId;

          final dynamic response = await client
              .from('documents')
              .select()
              .eq('organization_id', organizationId)
              .timeout(const Duration(seconds: 12));

          final List<dynamic> rows = response is List
              ? List<dynamic>.from(response)
              : <dynamic>[];

          final List<Map<String, dynamic>> parsed = rows
              .whereType<Map>()
              .map((item) => _normalizeLoadedDocument(
                    Map<String, dynamic>.from(item),
                  ))
              .toList();

          _sortDocumentsNewestFirst(parsed);
          loadedOrganization = parsed;
          _organizationKnowledgeMemoryCache[organizationId] =
              List<Map<String, dynamic>>.from(parsed);
        }
      } catch (error, stackTrace) {
        developer.log(
          'Keeper organization document load failed',
          error: error,
          stackTrace: stackTrace,
          name: 'ChatbotScreen',
        );
      }
    }

    await Future.wait(<Future<void>>[loadPersonal(), loadOrganization()]);

    if (!mounted) return;

    final List<Map<String, dynamic>> finalPersonal =
        loadedPersonal ?? _personalDocuments;

    setState(() {
      _personalDocuments = finalPersonal;
      _organizationDocuments = loadedOrganization;
      _isLoadingKnowledge = false;
      _lastKnowledgeSync = DateTime.now();

      // Only show an error when there is genuinely no personal knowledge
      // available after preserving cache/current data.
      _knowledgeLoadError =
          finalPersonal.isEmpty && personalError != null
              ? personalError.toString()
              : null;
    });

    if (loadedPersonal != null) {
      KeeperKnowledgeEngine.clearCache();
    }
  }

  void _sortDocumentsNewestFirst(List<Map<String, dynamic>> documents) {
    documents.sort((first, second) {
      final DateTime firstDate =
          DateTime.tryParse(first['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final DateTime secondDate =
          DateTime.tryParse(second['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return secondDate.compareTo(firstDate);
    });
  }

  Map<String, dynamic> _normalizeLoadedDocument(
    Map<String, dynamic> document,
  ) {
    final String currentCategory =
        document['category']?.toString().trim() ?? '';
    final String detectedCategory = _detectedKnowledgeCategory(
      selectedCategory: currentCategory.isEmpty ? 'Other' : currentCategory,
      fileName: document['file_name']?.toString() ?? '',
      extractedText: document['extracted_text']?.toString() ?? '',
    );

    if (detectedCategory != currentCategory) {
      document['category'] = detectedCategory;
    }
    return document;
  }

  String _detectedKnowledgeCategory({
    required String selectedCategory,
    required String fileName,
    required String extractedText,
  }) {
    if (selectedCategory.trim().toLowerCase() != 'other') {
      return selectedCategory;
    }

    final String searchable = '$fileName\n$extractedText'.toLowerCase();
    final bool hasAadhaarNumber = RegExp(
      r'\b[0-9]{4}[\s-]*[0-9]{4}[\s-]*[0-9]{4}\b',
    ).hasMatch(searchable);

    if (searchable.contains('aadhaar') ||
        searchable.contains('aadhar') ||
        searchable.contains('uidai') ||
        searchable.contains('unique identification') ||
        (searchable.contains('government of india') && hasAadhaarNumber)) {
      return 'Aadhaar';
    }
    if (RegExp(r'\b[a-z]{5}[0-9]{4}[a-z]\b').hasMatch(searchable) ||
        searchable.contains('income tax department')) {
      return 'PAN Card';
    }
    if (searchable.contains('marksheet') ||
        searchable.contains('statement of marks') ||
        searchable.contains('grade card')) {
      return 'Marksheet';
    }
    if (searchable.contains('curriculum vitae') ||
        searchable.contains('resume')) {
      return 'Resume';
    }
    if (searchable.contains('certificate')) return 'Certificate';
    return selectedCategory;
  }

  bool get _knowledgeIsStale {
    final DateTime? lastSync = _lastKnowledgeSync;
    if (lastSync == null) return true;
    return DateTime.now().difference(lastSync) > const Duration(minutes: 2);
  }

  List<Map<String, dynamic>> _documentsForScope() {
    switch (_selectedScope) {
      case KnowledgeScope.personal:
        return _personalDocuments;

      case KnowledgeScope.organization:
        return _organizationDocuments;

      case KnowledgeScope.all:
        return [..._personalDocuments, ..._organizationDocuments];
    }
  }

  String _cleanText(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  List<_RankedDocument> _searchKnowledge(String query) {
    final List<Map<String, dynamic>> documents = _documentsForScope();
    if (documents.isEmpty) return const <_RankedDocument>[];

    final bool asksForList = KeeperKnowledgeEngine.analyzeQuestion(
      query,
    ).asksForDocumentList;

    final List<KeeperRankedDocument> engineResults =
        KeeperKnowledgeEngine.search(
          question: query,
          documents: documents,
          limit: asksForList ? min(documents.length, 100) : 12,
        );

    final List<_RankedDocument> results = engineResults.map((result) {
      return _RankedDocument(
        document: result.document.raw,
        score: result.score,
        snippet: result.snippet,
      );
    }).toList();

    // Safety net for OCR text, IDs, filenames and exact numbers. The semantic
    // engine can miss these when OCR spacing is imperfect.
    final Set<String> queryTerms = _documentSearchTerms(query);
    final Set<String> seen = results
        .map((item) => _documentIdentity(item.document))
        .toSet();

    final List<_RankedDocument> lexical = <_RankedDocument>[];
    for (final Map<String, dynamic> document in documents) {
      final String rawText = document['extracted_text']?.toString() ?? '';
      final String searchableText = rawText.length <= 30000
          ? rawText
          : '${rawText.substring(0, 22000)} ${rawText.substring(rawText.length - 8000)}';
      final String haystack = [
        document['file_name']?.toString() ?? '',
        document['category']?.toString() ?? '',
        searchableText,
      ].join(' ').toLowerCase();

      if (haystack.trim().isEmpty) continue;
      int matches = 0;
      for (final String term in queryTerms) {
        if (haystack.contains(term)) matches++;
      }

      if (matches == 0) continue;
      final double score = 25.0 + (matches * 8.0);
      lexical.add(
        _RankedDocument(
          document: document,
          score: score,
          snippet: _lexicalSnippet(document, queryTerms),
        ),
      );
    }

    lexical.sort((a, b) => b.score.compareTo(a.score));
    for (final _RankedDocument item in lexical) {
      final String id = _documentIdentity(item.document);
      if (!seen.contains(id)) {
        results.add(item);
        seen.add(id);
      }
    }

    results.sort((a, b) => b.score.compareTo(a.score));
    return results;
  }

  Set<String> _documentSearchTerms(String query) {
    const Set<String> ignored = {
      'what', 'when', 'where', 'which', 'who', 'how', 'is', 'are', 'the',
      'my', 'me', 'mera', 'meri', 'mere', 'mujhe', 'hai', 'ka', 'ki', 'ke',
      'kya', 'batao', 'please', 'document', 'documents', 'file', 'files',
      'find', 'search', 'show', 'source', 'number', 'no', 'id', 'tell',
    };

    return _cleanText(query)
        .split(RegExp(r'[^a-z0-9]+'))
        .where((term) => term.length >= 2 && !ignored.contains(term))
        .toSet();
  }

  String _lexicalSnippet(
    Map<String, dynamic> document,
    Set<String> terms,
  ) {
    final String text = document['extracted_text']?.toString() ?? '';
    if (text.trim().isEmpty) return '';
    final String lower = text.toLowerCase();
    for (final String term in terms) {
      final int index = lower.indexOf(term);
      if (index >= 0) {
        final int start = max(0, index - 180);
        final int end = min(text.length, index + 500);
        return text.substring(start, end).trim();
      }
    }
    return text.length > 650 ? text.substring(0, 650) : text;
  }

  Future<void> _openSourceDocument(ChatSource source) async {
    if (source.fileUrl.trim().isEmpty && source.snippet.trim().isEmpty) {
      _showMessage('This source does not have a readable preview.');
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DocumentViewerScreen(
          fileName: source.fileName,
          fileUrl: source.fileUrl,
          extractedText: source.snippet,
        ),
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }

      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  String _detectMimeType({required String fileName, required String fileUrl}) {
    final String value = '$fileName $fileUrl'.toLowerCase();

    if (value.contains('.jpg') || value.contains('.jpeg')) {
      return 'image/jpeg';
    }

    if (value.contains('.png')) {
      return 'image/png';
    }

    if (value.contains('.webp')) {
      return 'image/webp';
    }

    if (value.contains('.pdf')) {
      return 'application/pdf';
    }

    if (value.contains('.txt') ||
        value.contains('.md') ||
        value.contains('.csv') ||
        value.contains('.log')) {
      return 'text/plain';
    }

    return 'application/octet-stream';
  }

  bool _canSendOriginalFileToGemini(String mimeType) {
    return mimeType == 'image/jpeg' ||
        mimeType == 'image/png' ||
        mimeType == 'image/webp' ||
        mimeType == 'application/pdf' ||
        mimeType == 'text/plain';
  }

  String _storagePathFromDocument(Map<String, dynamic> document) {
    final String savedPath =
        document['storage_path']?.toString().trim() ?? '';
    if (savedPath.isNotEmpty) return savedPath;

    final String fileUrl = document['file_url']?.toString().trim() ?? '';
    const String marker = '/Keeper-documents/';
    final int markerIndex = fileUrl.indexOf(marker);
    if (markerIndex < 0) return '';

    final String encodedPath = fileUrl.substring(markerIndex + marker.length);
    return Uri.decodeComponent(encodedPath.split('?').first);
  }

  Future<Uint8List?> _downloadFileBytes({
    required Map<String, dynamic> document,
    required String mimeType,
  }) async {
    const int maximumFileBytes = 8 * 1024 * 1024;

    final String fileUrl = document['file_url']?.toString().trim() ?? '';

    if (!_canSendOriginalFileToGemini(mimeType)) {
      return null;
    }

    if (fileUrl.isNotEmpty) {
      try {
        final Uri? uri = Uri.tryParse(fileUrl);

        if (uri != null && uri.hasScheme) {
          final http.Response response = await http
              .get(uri)
              .timeout(const Duration(seconds: 4));

          if (response.statusCode >= 200 && response.statusCode < 300) {
            final Uint8List bytes = response.bodyBytes;
            if (bytes.isNotEmpty && bytes.length <= maximumFileBytes) {
              return bytes;
            }
          }
        }
      } catch (_) {
        // A private bucket or an expired URL is handled by the storage fallback.
      }
    }

    final String storagePath = _storagePathFromDocument(document);
    if (storagePath.isEmpty) return null;

    try {
      final Uint8List bytes = await supabase.Supabase.instance.client.storage
          .from('Keeper-documents')
          .download(storagePath)
          .timeout(const Duration(seconds: 5));
      if (bytes.isEmpty || bytes.length > maximumFileBytes) return null;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  String _fileExtension(String fileName) {
    final int dotIndex = fileName.lastIndexOf('.');

    if (dotIndex == -1 || dotIndex == fileName.length - 1) {
      return '';
    }

    return fileName.substring(dotIndex + 1).toLowerCase();
  }

  Future<bool?> _chooseAttachmentAction() async {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF121725),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
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
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'How should Keeper use these files?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                const Text(
                  'Ask once, or save them to your knowledge for future search.',
                  style: TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                _buildAttachmentActionTile(
                  icon: Icons.flash_on_rounded,
                  title: 'Ask Only',
                  subtitle:
                      'Use the files for this question only. Nothing is saved.',
                  onTap: () => Navigator.pop(sheetContext, false),
                ),
                const SizedBox(height: 11),
                _buildAttachmentActionTile(
                  icon: Icons.bookmark_add_rounded,
                  title: 'Save & Ask',
                  subtitle:
                      'Save files to Keeper knowledge, then answer your question.',
                  onTap: () => Navigator.pop(sheetContext, true),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAttachmentActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFF1A2030),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFF29264F),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: const Color(0xFFAAA4FF)),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF9298A8),
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF777D8E)),
            ],
          ),
        ),
      ),
    );
  }

  Future<Map<String, String>?> _chooseSaveDestination() async {
    String selectedSpace = _selectedScope == KnowledgeScope.organization
        ? 'organization'
        : 'personal';

    if (_selectedScope == KnowledgeScope.all) {
      selectedSpace = 'personal';
    }

    String selectedCategory = selectedSpace == 'organization'
        ? 'Study Material'
        : 'Other';

    final List<String> personalCategories = [
      'Certificate',
      'Resume',
      'Marksheet',
      'Personal Notes',
      'Bill',
      'Other',
    ];

    final List<String> organizationCategories = [
      'Notice',
      'Exam Timetable',
      'Syllabus',
      'Previous Year Paper',
      'Assignment',
      'Lab Manual',
      'Internship',
      'Project',
      'Study Material',
      'Other',
    ];

    return showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121725),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final List<String> categories = selectedSpace == 'organization'
                ? organizationCategories
                : personalCategories;

            if (!categories.contains(selectedCategory)) {
              selectedCategory = categories.first;
            }

            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  18,
                  12,
                  18,
                  22 + MediaQuery.viewInsetsOf(context).bottom,
                ),
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
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Save to Keeper Knowledge',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            selected: selectedSpace == 'personal',
                            label: const Text('Personal'),
                            onSelected: (_) {
                              setSheetState(() {
                                selectedSpace = 'personal';
                                selectedCategory = personalCategories.first;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ChoiceChip(
                            selected: selectedSpace == 'organization',
                            label: const Text('Organization'),
                            onSelected: (_) {
                              setSheetState(() {
                                selectedSpace = 'organization';
                                selectedCategory = organizationCategories.first;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: selectedCategory,
                      dropdownColor: const Color(0xFF1A2030),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Category',
                        labelStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                        filled: true,
                        fillColor: const Color(0xFF1A2030),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      items: categories
                          .map(
                            (category) => DropdownMenuItem<String>(
                              value: category,
                              child: Text(category),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setSheetState(() {
                          selectedCategory = value;
                        });
                      },
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(sheetContext, {
                            'space': selectedSpace,
                            'category': selectedCategory,
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF766DFF),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'Save & Continue',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<bool> _canUploadToOrganization(
    String organizationId,
    String userId,
  ) async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> organizationDocument =
          await FirebaseFirestore.instance
              .collection('organizations')
              .doc(organizationId)
              .get();

      final Map<String, dynamic> data = organizationDocument.data() ?? {};

      final String permission =
          data['uploadPermission']?.toString() ?? 'everyone';

      if (permission != 'admin_only') {
        return true;
      }

      final String ownerId = data['ownerId']?.toString() ?? '';
      final List<String> adminIds =
          (data['adminIds'] as List<dynamic>? ?? const [])
              .map((item) => item.toString())
              .toList();

      return ownerId == userId || adminIds.contains(userId);
    } catch (_) {
      return false;
    }
  }

  Future<void> _insertKnowledgeRowWithFallback(
    supabase.SupabaseClient client,
    Map<String, dynamic> payload,
  ) async {
    final Map<String, dynamic> currentPayload = Map<String, dynamic>.from(
      payload,
    );

    for (int attempt = 0; attempt < 16; attempt++) {
      try {
        await client.from('documents').insert(currentPayload);
        return;
      } catch (error) {
        final RegExpMatch? match = RegExp(
          r"Could not find the '([^']+)' column",
          caseSensitive: false,
        ).firstMatch(error.toString());
        final String? missingColumn = match?.group(1);

        if (missingColumn == null ||
            !currentPayload.containsKey(missingColumn)) {
          rethrow;
        }
        currentPayload.remove(missingColumn);
      }
    }

    throw StateError('The documents table schema is incompatible.');
  }

  Future<bool> _saveAttachmentsToKnowledge({
    required List<ChatAttachment> attachments,
    required String space,
    required String category,
  }) async {
    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _showMessage('Please sign in again.');
      return false;
    }

    String? organizationId;

    if (space == 'organization') {
      organizationId =
          _organizationIdMemoryCache[user.uid] ??
          await _loadUserOrganizationId(user.uid);

      if (organizationId == null || organizationId.isEmpty) {
        _showMessage('No organization is linked with this account.');
        return false;
      }

      final bool canUpload = await _canUploadToOrganization(
        organizationId,
        user.uid,
      );

      if (!canUpload) {
        _showMessage(
          'Only organization admins can upload documents in this workspace.',
        );
        return false;
      }
    }

    if (mounted) {
      setState(() {
        _isSavingAttachments = true;
        _savedAttachmentCount = 0;
        _totalAttachmentsToSave = attachments.length;
      });
    }

    int successCount = 0;

    try {
      final supabase.SupabaseClient client = supabase.Supabase.instance.client;

      for (int index = 0; index < attachments.length; index++) {
        final ChatAttachment attachment = attachments[index];
        String? uploadedStoragePath;

        try {
          final File localFile = File(attachment.path);

          if (!await localFile.exists()) {
            continue;
          }

          final int fileSize = await localFile.length();

          if (fileSize <= 0 || fileSize > 20 * 1024 * 1024) {
            continue;
          }

          final String extension = _fileExtension(attachment.name);

          final TextExtractionResult extractionResult =
              await TextExtractorService.extract(
                filePath: attachment.path,
                extension: extension,
              );
          final String effectiveCategory = _detectedKnowledgeCategory(
            selectedCategory: category,
            fileName: attachment.name,
            extractedText: extractionResult.text,
          );

          final String safeFileName = attachment.name.replaceAll(
            RegExp(r'[^a-zA-Z0-9._-]'),
            '_',
          );

          final String storageFolder = space == 'personal'
              ? 'personal/${user.uid}'
              : 'organizations/$organizationId';

          uploadedStoragePath =
              '$storageFolder/${DateTime.now().microsecondsSinceEpoch}_${index + 1}_$safeFileName';

          await client.storage
              .from('Keeper-documents')
              .upload(
                uploadedStoragePath,
                localFile,
                fileOptions: const supabase.FileOptions(
                  cacheControl: '3600',
                  upsert: false,
                ),
              );

          final String publicUrl = client.storage
              .from('Keeper-documents')
              .getPublicUrl(uploadedStoragePath);

          await _insertKnowledgeRowWithFallback(client, {
            'user_id': user.uid,
            'file_name': attachment.name,
            'category': effectiveCategory,
            'space': space,
            'visibility': space == 'personal' ? 'private' : 'organization',
            'file_url': publicUrl,
            'storage_path': uploadedStoragePath,
            'organization_id': organizationId,
            'extracted_text': extractionResult.text,
            'processing_status': extractionResult.status,
            'file_extension': extension,
            'mime_type': attachment.mimeType,
            'file_size': fileSize,
          });

          successCount++;
        } catch (_) {
          if (uploadedStoragePath != null) {
            try {
              await supabase.Supabase.instance.client.storage
                  .from('Keeper-documents')
                  .remove([uploadedStoragePath]);
            } catch (_) {
              // Ignore cleanup failure.
            }
          }
        }

        if (mounted) {
          setState(() {
            _savedAttachmentCount = index + 1;
          });
        }
      }

      if (successCount > 0) {
        await _loadKnowledge(showLoading: false);
      }

      if (successCount == attachments.length) {
        _showMessage(
          '$successCount file${successCount == 1 ? '' : 's'} saved to Keeper.',
        );
      } else {
        _showMessage(
          '$successCount saved, ${attachments.length - successCount} failed.',
        );
      }

      return successCount > 0;
    } finally {
      if (mounted) {
        setState(() {
          _isSavingAttachments = false;
          _savedAttachmentCount = 0;
          _totalAttachmentsToSave = 0;
        });
      }
    }
  }

  String _documentIdentity(Map<String, dynamic> document) {
    final String id = document['id']?.toString() ?? '';
    if (id.isNotEmpty) return id;

    return [
      document['file_name']?.toString() ?? '',
      document['created_at']?.toString() ?? '',
      document['file_url']?.toString() ?? '',
    ].join('|');
  }

  Set<String> _sourceTerms(String value) {
    const Set<String> ignoredWords = {
      'about',
      'after',
      'again',
      'also',
      'answer',
      'because',
      'before',
      'being',
      'between',
      'could',
      'document',
      'documents',
      'from',
      'have',
      'into',
      'keeper',
      'more',
      'other',
      'should',
      'source',
      'that',
      'their',
      'there',
      'these',
      'they',
      'this',
      'those',
      'through',
      'uploaded',
      'user',
      'using',
      'very',
      'what',
      'when',
      'where',
      'which',
      'with',
      'would',
      'your',
      'hai',
      'hain',
      'kya',
      'kaise',
      'mein',
      'mera',
      'mere',
      'meri',
      'mujhe',
      'nahi',
      'wala',
      'wali',
      'wale',
      'isko',
      'usko',
    };

    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .split(' ')
        .map((term) => term.trim())
        .where(
          (term) =>
              term.length >= 4 &&
              !ignoredWords.contains(term) &&
              !RegExp(r'^\d+$').hasMatch(term),
        )
        .toSet();
  }

  List<ChatSource> _smartSourcesForAnswer({
    required String answer,
    required String question,
    required List<_RankedDocument> results,
    bool isDocumentList = false,
  }) {
    if (results.isEmpty) return const <ChatSource>[];

    final Set<String> answerTerms = _sourceTerms(answer);
    final Set<String> questionTerms = _sourceTerms(question);
    final Map<String, _RankedDocument> uniqueResults = {};

    // Gemini receives at most three knowledge files. Never display a source
    // that was not among those actual candidates.
    for (final _RankedDocument result in results.take(3)) {
      uniqueResults.putIfAbsent(
        _documentIdentity(result.document),
        () => result,
      );
    }

    final List<
      ({_RankedDocument result, double evidenceScore, int answerMatches})
    >
    scored = [];

    for (final _RankedDocument result in uniqueResults.values) {
      final Map<String, dynamic> document = result.document;
      final String searchableEvidence = [
        document['file_name']?.toString() ?? '',
        document['category']?.toString() ?? '',
        result.snippet,
        document['extracted_text']?.toString() ?? '',
      ].join(' ');

      final Set<String> evidenceTerms = _sourceTerms(searchableEvidence);
      final int answerMatches = answerTerms.intersection(evidenceTerms).length;
      final int questionMatches = questionTerms
          .intersection(evidenceTerms)
          .length;

      final double evidenceScore =
          (answerMatches * 12.0) +
          (questionMatches * 4.0) +
          result.score.clamp(0, 60) * 0.35;

      scored.add((
        result: result,
        evidenceScore: evidenceScore,
        answerMatches: answerMatches,
      ));
    }

    scored.sort((a, b) => b.evidenceScore.compareTo(a.evidenceScore));

    final double bestScore = scored.first.evidenceScore;
    final List<_RankedDocument> selected = [];

    for (final item in scored) {
      final bool hasAnswerEvidence = item.answerMatches >= 2;
      final bool closeToBest =
          bestScore > 0 &&
          item.evidenceScore >= bestScore * 0.75 &&
          item.answerMatches > 0;

      if (isDocumentList || hasAnswerEvidence || (closeToBest && item.answerMatches >= 1)) {
        selected.add(item.result);
      }

      if (selected.length == 3) break;
    }

    // Never attach a random fallback source. If the answer does not have
    // evidence in a candidate document, show no source rather than guessing.
    if (selected.isEmpty) return const <ChatSource>[];

    return selected.map((result) {
      final Map<String, dynamic> document = result.document;

      return ChatSource(
        fileName: document['file_name']?.toString() ?? 'Unnamed document',
        category: document['category']?.toString() ?? 'Other',
        fileUrl: document['file_url']?.toString() ?? '',
        snippet: result.snippet,
        score: result.score,
      );
    }).toList();
  }

  String _answerCacheKey({
    required String question,
    required List<_RankedDocument> results,
  }) {
    final String documentPart = results
        .map((item) => _documentIdentity(item.document))
        .join('||');

    return '${_selectedScope.name}|${_cleanText(question)}|$documentPart';
  }

  ChatMessage? _cachedAnswerFor({
    required String question,
    required List<_RankedDocument> results,
  }) {
    return _answerMemoryCache[_answerCacheKey(
      question: question,
      results: results,
    )];
  }

  void _storeCachedAnswer({
    required String question,
    required List<_RankedDocument> results,
    required ChatMessage message,
  }) {
    if (_answerMemoryCache.length >= 40) {
      _answerMemoryCache.remove(_answerMemoryCache.keys.first);
    }

    _answerMemoryCache[_answerCacheKey(question: question, results: results)] =
        message;
  }

  String _buildDocumentListAnswer(
    String question,
    List<_RankedDocument> results,
  ) {
    final List<_RankedDocument> topResults = results.take(8).toList();
    final String normalizedQuestion = _cleanText(question);
    final bool prefersHinglish = [
      'mere',
      'meri',
      'tumhare',
      'aapke',
      'apke',
      'kon',
      'kaun',
      'kya',
      'hai',
      'hain',
      'paas',
      'pass',
      'dikhao',
      'batao',
    ].any(normalizedQuestion.contains);

    final StringBuffer buffer = StringBuffer();

    if (prefersHinglish) {
      buffer.writeln(
        'Aapke ${_scopeLabel(_selectedScope)} space me ${results.length} '
        'document${results.length == 1 ? '' : 's'} available hain:',
      );
    } else {
      buffer.writeln(
        'I found ${results.length} matching document'
        '${results.length == 1 ? '' : 's'} in '
        '${_scopeLabel(_selectedScope)} knowledge.',
      );
    }
    buffer.writeln();

    for (int index = 0; index < topResults.length; index++) {
      final Map<String, dynamic> document = topResults[index].document;

      final String fileName =
          document['file_name']?.toString() ?? 'Unnamed document';

      final String category = document['category']?.toString() ?? 'Other';

      buffer.writeln('${index + 1}. $fileName');
      buffer.writeln('   Category: $category');
    }

    if (results.length > topResults.length) {
      buffer.writeln();
      buffer.writeln(prefersHinglish
          ? '${results.length - topResults.length} aur matching documents available hain.'
          : '${results.length - topResults.length} more matching documents are available.');
    }

    return buffer.toString().trim();
  }

  List<GeminiKnowledgeFile> _buildTextOnlyKnowledge(
    List<_RankedDocument> results, {
    required String question,
  }) {
    return results
        .take(2)
        .map((result) {
          final Map<String, dynamic> document = result.document;
          final String fullText = document['extracted_text']?.toString() ?? '';

          return GeminiKnowledgeFile(
            fileName: document['file_name']?.toString() ?? 'Unnamed document',
            category: document['category']?.toString() ?? 'Other',
            extractedText: _relevantDocumentContext(
              fullText: fullText,
              question: question,
              maximumCharacters: 6500,
            ),
            mimeType: 'text/plain',
          );
        })
        .where((item) => item.extractedText.trim().isNotEmpty)
        .toList();
  }

  String _relevantDocumentContext({
    required String fullText,
    required String question,
    required int maximumCharacters,
  }) {
    final String cleaned = fullText
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();

    if (cleaned.isEmpty || cleaned.length <= maximumCharacters) {
      return cleaned;
    }

    final List<String> terms = _cleanText(
      question,
    ).split(' ').where((term) => term.length >= 3).toSet().toList();

    final String lower = cleaned.toLowerCase();
    final List<int> matches = <int>[];

    for (final String term in terms) {
      int start = 0;
      while (matches.length < 8) {
        final int index = lower.indexOf(term, start);
        if (index < 0) break;
        matches.add(index);
        start = index + term.length;
      }
    }

    if (matches.isEmpty) {
      return cleaned.substring(0, maximumCharacters);
    }

    matches.sort();
    final StringBuffer buffer = StringBuffer();
    int lastEnd = -1;

    for (final int match in matches) {
      final int start = (match - 900).clamp(0, cleaned.length);
      final int end = (match + 1700).clamp(0, cleaned.length);

      if (start <= lastEnd) continue;

      final String section = cleaned.substring(start, end).trim();
      if (section.isEmpty) continue;

      if (buffer.isNotEmpty) buffer.writeln('\n--- relevant section ---\n');
      buffer.write(section);
      lastEnd = end;

      if (buffer.length >= maximumCharacters) break;
    }

    final String value = buffer.toString().trim();
    if (value.isEmpty) return cleaned.substring(0, maximumCharacters);
    return value.length <= maximumCharacters
        ? value
        : value.substring(0, maximumCharacters);
  }

  List<String> _recentConversationContext({int limit = 8}) {
    final List<ChatMessage> relevant = _messages
        .where((message) => message.text.trim().isNotEmpty && !message.isError)
        .toList();

    // The current question is already sent separately to Gemini. Excluding the
    // latest user message prevents Gemini from receiving the same question twice.
    if (relevant.isNotEmpty && relevant.last.isUser) {
      relevant.removeLast();
    }

    final int start = relevant.length > limit ? relevant.length - limit : 0;

    return relevant
        .sublist(start)
        .map(
          (message) =>
              '${message.isUser ? 'User' : 'Keeper AI'}: ${message.text.trim()}',
        )
        .toList();
  }

  bool _questionExplicitlyNeedsKeeperKnowledge(String question) {
    final String value = question.toLowerCase();

    const List<String> knowledgeWords = [
      'my document',
      'my documents',
      'my file',
      'my files',
      'uploaded document',
      'uploaded file',
      'knowledge',
      'pdf',
      'notes',
      'question paper',
      'marksheet',
      'aadhaar',
      'aadhar',
      'adhar',
      'aadhaarcard',
      'aadharcard',
      'adharcard',
      'uidai',
      'identity card',
      'id card',
      'card number',
      'pan card',
      'certificate',
      'resume',
      'organization document',
      'personal document',
      'is document me',
      'iss document me',
      'meri file',
      'mere document',
      'mere documents',
      'maine upload',
      'upload kiya',
      'open my',
      'download my',
      'uploaded',
      'upload kiya',
      'upload ki',
    ];

    // Find/locate intent - the most common real-world phrasing ("X dhundo",
    // "X kaha hai") was previously not recognised at all, which meant a
    // correctly matched document could still get thrown away later.
    const List<String> findIntentWords = [
      'dhundo', 'dhoondo', 'dhundho', 'dhoondho', 'dhund do', 'dhoond do',
      'dhundna', 'dhoondna', 'khojo', 'khoj do', 'nikalo', 'nikal do',
      'talash', 'find it', 'find my', 'find the', 'search for', 'search my',
      'locate', 'kaha hai', 'kahan hai', 'kaha rakha',
      'kaha save', 'kaha pada', 'kis document me', 'kis file me',
      'konsi file me', 'kaunsi file me', 'wala document', 'wali file',
    ];

    // Common document types people ask about that were missing before,
    // causing genuine document questions to be treated as general chat.
    const List<String> documentNounWords = [
      'receipt', 'bill', 'invoice', 'fee receipt', 'fees receipt',
      'college fee', 'school fee', 'tuition fee', 'admission fee',
      'exam fee', 'fee slip', 'chalan', 'slip',
      'statement', 'timetable', 'attendance', 'scorecard', 'score card',
      'gradecard', 'grade card', 'mark sheet', 'result', 'degree', 'diploma',
      'license', 'licence', 'voter id', 'passport', 'policy', 'sop',
      'contract', 'agreement', 'application form', 'admission form',
      'leave form', 'fill form', 'this form', 'the form', 'whatsapp',
      'screenshot', 'scan',
      'total amount', 'percentage', 'bank statement', 'salary slip',
      'payslip', 'roll number', 'phone number', 'email id',
    ];

    const List<String> multilingualFindIntent = [
      'शोध', 'शोधा', 'दाखवा', 'कागदपत्र', 'कागदपत्रे', 'दस्तऐवज',
      'दस्तऐवज शोध', 'मार्कशीट', 'आधार', 'पॅन कार्ड', 'नोट्स', 'कुठे आहे',
      'माझे कागदपत्र', 'माझी मार्कशीट', 'माझा निकाल', 'माझे प्रमाणपत्र',
      'where is my', 'my marks', 'my result', 'my certificate',
    ];

    final bool direct = knowledgeWords.any(value.contains) ||
        findIntentWords.any(value.contains) ||
        documentNounWords.any(value.contains) ||
        multilingualFindIntent.any(value.contains);
    final bool personalNumberRequest =
        (value.contains('my ') || value.contains('mera') ||
            value.contains('meri') || value.contains('mere')) &&
        (value.contains('number') || value.contains('no') ||
            value.contains('id') || value.contains('details'));

    return direct || personalNumberRequest;
  }

  bool _recentConversationUsedDocuments() {
    for (final ChatMessage message in _messages.reversed.take(6)) {
      if (!message.isUser && message.sources.isNotEmpty) {
        return true;
      }

      if (message.isUser &&
          _questionExplicitlyNeedsKeeperKnowledge(message.text)) {
        return true;
      }
    }

    return false;
  }

  bool _looksLikeDocumentFollowUp(String question) {
    final String value = _cleanText(question);
    return value.contains('this document') ||
        value.contains('that document') ||
        value.contains('is document') ||
        value.contains('iss document') ||
        value.contains('usme') ||
        value.contains('isme') ||
        value.contains('uska') ||
        value.contains('iska') ||
        value.contains('uski') ||
        value.contains('iski') ||
        value.contains('first one') ||
        value.contains('second one');
  }

  bool _hasStrongKnowledgeMatch(
    String question,
    List<_RankedDocument> results,
  ) {
    if (results.isEmpty) return false;

    if (KeeperKnowledgeEngine.analyzeQuestion(question).asksForDocumentList) {
      return true;
    }

    if (_questionExplicitlyNeedsKeeperKnowledge(question)) {
      return true;
    }

    final String value = _cleanText(question);

    const List<String> workspaceContextWords = [
      'exam',
      'timetable',
      'schedule',
      'syllabus',
      'assignment',
      'deadline',
      'notice',
      'marks',
      'marksheet',
      'certificate',
      'resume',
      'project',
      'chapter',
      'subject',
      'question paper',
      'college',
      'class',
      'organization',
      'workspace',
      'uploaded',
      'mentioned',
      'according to',
      'date',
      'hamara',
      'hamari',
      'our',
      'my',
      // Same find-intent + document-noun vocabulary as
      // _questionExplicitlyNeedsKeeperKnowledge, kept in sync so a query
      // that qualifies there also qualifies here.
      'dhundo', 'dhoondo', 'dhundho', 'dhoondho', 'dhundna', 'dhoondna',
      'khojo', 'nikalo', 'find', 'search', 'locate', 'kaha hai', 'kahan hai',
      'kaha rakha', 'kis document me', 'kis file me',
      'receipt', 'bill', 'invoice', 'fee receipt', 'fees receipt',
      'college fee', 'school fee', 'tuition fee', 'chalan', 'slip',
      'statement', 'attendance', 'scorecard', 'gradecard', 'mark sheet',
      'result', 'degree', 'diploma', 'license', 'licence', 'voter id',
      'passport', 'policy', 'sop', 'contract', 'agreement',
      'application form', 'admission form', 'leave form', 'fill form',
      'this form', 'the form',
      'whatsapp', 'screenshot', 'scan', 'total amount', 'percentage',
      'salary slip', 'payslip', 'roll number', 'phone number', 'email id',
    ];

    final bool hasWorkspaceContext = workspaceContextWords.any(value.contains);
    final bool isDocumentFollowUp = _recentConversationUsedDocuments();

    // A genuinely strong ranking-engine match (identity-document match,
    // exact/near-exact filename match, or high keyword coverage) is trusted
    // on its own merit even if the question used wording we don't have in
    // any list above. This is a safety net so retrieval doesn't silently
    // depend on us enumerating every possible phrasing.
    final double bestScore = results.first.score;
    if (bestScore >= 55) {
      return true;
    }

    // Casual/general questions should not accidentally show document sources.
    if (!hasWorkspaceContext && !isDocumentFollowUp) {
      return false;
    }

    return bestScore >= (isDocumentFollowUp ? 12 : 20);
  }

  bool _isCreatorQuestion(String question) {
    final String value = _cleanText(question);

    const List<String> directPhrases = [
      'who created keeper',
      'who made keeper',
      'who built keeper',
      'keeper founder',
      'creator of keeper',
      'developer of keeper',
      'keeper kisne banaya',
      'keeper ko kisne banaya',
      'tumhe kisne banaya',
      'aapko kisne banaya',
      'apko kisne banaya',
      'who created you',
      'who made you',
      'who built you',
      'who is your creator',
      'who is your founder',
      'who is your owner',
      'who owns keeper',
      'keeper owner',
      'owner of keeper',
      'your owners name',
      "your owner's name",
      'tumhara owner kaun hai',
      'aapka owner kaun hai',
      'apka owner kaun hai',
      'faizan kaun hai',
      'faizan kon hai',
      'faijan kaun hai',
      'faijan kon hai',
      'faizan ke bare me',
      'faizan ke baare me',
      'about faizan',
      'who is faizan',
      'who is faijan',
      'tell me about faizan',
    ];

    if (directPhrases.any(value.contains)) {
      return true;
    }

    final bool asksCreator =
        value.contains('created') ||
        value.contains('creator') ||
        value.contains('made') ||
        value.contains('built') ||
        value.contains('founder') ||
        value.contains('developer') ||
        value.contains('owner') ||
        value.contains('owns keeper') ||
        value.contains('kisne banaya') ||
        value.contains('banane wala');

    final bool refersToKeeper =
        value.contains('keeper') ||
        value.contains('you') ||
        value.contains('your') ||
        value.contains('tum') ||
        value.contains('aap') ||
        value.contains('apko');

    return asksCreator && refersToKeeper;
  }

  String _creatorAnswer(String question) {
    final String value = _cleanText(question);

    final bool prefersHinglish =
        value.contains('kisne') ||
        value.contains('kaun') ||
        value.contains('banaya') ||
        value.contains('bare me') ||
        value.contains('baare me') ||
        value.contains('tum') ||
        value.contains('aap') ||
        value.contains('apko');

    final bool asksOnlyForName =
        value.contains('name') ||
        value.contains('naam') ||
        value.contains('owner');

    if (prefersHinglish) {
      if (asksOnlyForName) {
        return 'Keeper AI ke creator, developer aur founder Faizan Rafik Shaikh hain. '
            'Unhone Keeper ko ek universal AI-powered knowledge assistant ke roop me build kiya hai.';
      }
      return 'Keeper AI ko Faizan Rafik Shaikh ne create kiya hai. '
          'Woh ek ambitious, creative aur forward-thinking founder hain, '
          'jinka focus technology ke through real problems ko simple aur useful '
          'solutions me badalna hai. Keeper AI unke strong vision, determination '
          'aur innovation-driven mindset ka result hai.';
    }

    if (asksOnlyForName) {
      return 'Keeper AI was created and developed by Faizan Rafik Shaikh. '
          'He is the founder behind Keeper\'s universal AI-powered knowledge assistant vision.';
    }

    return 'Keeper AI was created by Faizan Rafik Shaikh. '
        'He is an ambitious, creative and forward-thinking founder focused on '
        'turning real problems into simple, useful technology solutions. '
        'Keeper AI reflects his strong vision, determination and '
        'innovation-driven mindset.';
  }

  bool _isCurrentUserNameQuestion(String question) {
    final String value = _cleanText(question);
    const List<String> phrases = [
      'what is my name',
      "what's my name",
      'whats my name',
      'who am i',
      'mera naam kya hai',
      'mera name kya hai',
      'meri name kya hai',
      'main kaun hun',
      'mai kaun hun',
      'main kon hun',
      'mai kon hun',
    ];
    return phrases.any(value.contains);
  }

  Future<String> _currentUserNameAnswer(String question) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return 'I cannot read your profile because you are signed out. Please sign in again.';
    }

    String name = user.displayName?.trim() ?? '';

    if (name.isEmpty) {
      try {
        final DocumentSnapshot<Map<String, dynamic>> profile =
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .get();
        final Map<String, dynamic> data = profile.data() ?? const {};
        name = (data['name'] ??
                    data['fullName'] ??
                    data['full_name'] ??
                    data['displayName'])
                ?.toString()
                .trim() ??
            '';
      } catch (_) {
        // Firebase Authentication details can still answer the question.
      }
    }

    final String value = _cleanText(question);
    final bool prefersHinglish =
        value.contains('naam') ||
        value.contains('kaun') ||
        value.contains('kon') ||
        value.contains('hun');

    if (name.isNotEmpty) {
      return prefersHinglish
          ? 'Aapke Keeper profile ka naam $name hai.'
          : 'Your Keeper profile name is $name.';
    }

    final String email = user.email?.trim() ?? '';
    if (email.isNotEmpty) {
      return prefersHinglish
          ? 'Aap $email se signed in hain, lekin profile name abhi save nahi hai.'
          : 'You are signed in as $email, but your profile name has not been saved yet.';
    }

    return 'Your profile name has not been saved yet.';
  }

  Future<void> _appendImmediateAnswer({
    required String question,
    required String answer,
  }) async {
    await _ensureActiveChat(question);
    if (!mounted) return;

    final DateTime now = DateTime.now();
    setState(() {
      _messages.add(
        ChatMessage(
          id: _createId(),
          text: question,
          isUser: true,
          createdAt: now,
        ),
      );
      _messageController.clear();
      _selectedAttachments.clear();
      _appendMessageIfNotDuplicate(
        ChatMessage(
          id: _createId(),
          text: answer,
          isUser: false,
          createdAt: now.add(const Duration(milliseconds: 1)),
        ),
      );
    });

    _messageFocusNode.unfocus();
    _scrollToBottom();
    unawaited(_persistCurrentChat());
  }

  Future<void> _openKeeperMemory() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const MemoryScreen()));
  }

  KeeperMemorySpace _defaultMemorySpace() {
    return KeeperMemoryService.defaultSpaceForScope(_selectedScope.name);
  }

  Future<List<String>> _memoryContextForQuestion(String question) async {
    try {
      final List<KeeperMemory> memories =
          await KeeperMemoryService.findRelevantMemories(
            question: question,
            scope: _selectedScope.name,
            limit: 6,
          );

      return memories
          .map(
            (memory) =>
                '[${memory.space.name} memory] ${memory.content.trim()}',
          )
          .where((value) => value.trim().isNotEmpty)
          .toList();
    } catch (_) {
      return const <String>[];
    }
  }

  String _memoryListAnswer(
    List<KeeperMemory> memories,
    KeeperMemorySpace space,
  ) {
    if (memories.isEmpty) {
      return 'No ${space.name} memories are saved yet.\n\n'
          'Say “Remember this...” or “Yaad rakho...” to save one.';
    }

    final StringBuffer buffer = StringBuffer(
      'I remember these ${space.name} details:\n\n',
    );

    for (int index = 0; index < memories.take(12).length; index++) {
      buffer.writeln('${index + 1}. ${memories[index].content}');
      if (index < memories.take(12).length - 1) buffer.writeln();
    }

    if (memories.length > 12) {
      buffer.writeln('\n${memories.length - 12} more memories are saved.');
    }

    return buffer.toString().trim();
  }

  Future<bool> _handleMemoryCommand(String question) async {
    final KeeperMemoryCommand command = KeeperMemoryService.parseCommand(
      question,
    );

    if (command.type == KeeperMemoryCommandType.none) return false;

    await _ensureActiveChat(question);
    if (!mounted) return true;

    final DateTime now = DateTime.now();
    setState(() {
      _messages.add(
        ChatMessage(
          id: _createId(),
          text: question,
          isUser: true,
          createdAt: now,
        ),
      );
      _messageController.clear();
      _selectedAttachments.clear();
      _isThinking = true;
    });

    _messageFocusNode.unfocus();
    _scrollToBottom();

    String answer;
    final KeeperMemorySpace space =
        command.requestedSpace ?? _defaultMemorySpace();

    try {
      switch (command.type) {
        case KeeperMemoryCommandType.save:
          if (command.content.trim().isEmpty) {
            answer =
                'Memory save karne ke liye “Remember this...” ke baad '
                'jo baat yaad rakhni hai woh likho.';
          } else {
            final KeeperMemory saved = await KeeperMemoryService.saveMemory(
              content: command.content,
              space: space,
            );
            answer = 'Saved to ${saved.space.name} memory:\n\n${saved.content}';
          }
          break;

        case KeeperMemoryCommandType.list:
          final List<KeeperMemory> memories =
              await KeeperMemoryService.loadMemories(space: space);
          answer = _memoryListAnswer(memories, space);
          break;

        case KeeperMemoryCommandType.forget:
          if (command.content.trim().isEmpty) {
            answer =
                'Kaunsi memory delete karni hai uska short description '
                '“Forget this...” ke baad likho.';
          } else {
            final KeeperMemory? removed =
                await KeeperMemoryService.forgetBestMatch(
                  description: command.content,
                  space: space,
                );
            answer = removed == null
                ? 'Mujhe matching ${space.name} memory nahi mili.'
                : 'Deleted from ${space.name} memory:\n\n${removed.content}';
          }
          break;

        case KeeperMemoryCommandType.forgetAll:
          final int deleted = await KeeperMemoryService.deleteAll(space: space);
          answer = deleted == 0
              ? 'No ${space.name} memories were saved.'
              : 'Deleted all $deleted ${space.name} memories.';
          break;

        case KeeperMemoryCommandType.none:
          return false;
      }
    } catch (error) {
      answer = error
          .toString()
          .replaceFirst('Bad state: ', '')
          .replaceFirst('Invalid argument(s): ', '');
    }

    if (!mounted) return true;
    setState(() {
      _appendMessageIfNotDuplicate(
        ChatMessage(
          id: _createId(),
          text: answer,
          isUser: false,
          createdAt: DateTime.now(),
        ),
      );
      _isThinking = false;
    });

    _scrollToBottom();
    unawaited(_persistCurrentChat());
    return true;
  }

  // Reserve one AI request against the daily quota ONLY at the point an
  // actual Gemini call is about to be made. Previously this was reserved
  // unconditionally at the very start of every send, even for questions
  // that were ultimately answered from the local document-list builder or
  // the answer cache without ever calling Gemini - wasting quota and
  // making the daily limit feel like it ran out far too quickly.
  Future<bool> _reserveAiUsageOrNotify() async {
    final KeeperAiUsageResult usage =
        await KeeperAiUsageService.reserveRequest();

    if (usage.allowed) return true;

    if (!mounted) return false;

    setState(() {
      _appendMessageIfNotDuplicate(
        ChatMessage(
          id: _createId(),
          text:
              'Aaj ki ${usage.limit} AI requests ki free limit complete ho gayi hai. Kal phir use kar sakte ho.',
          isUser: false,
          createdAt: DateTime.now(),
        ),
      );
      _isThinking = false;
    });

    _scrollToBottom();
    unawaited(_persistCurrentChat());
    return false;
  }

  Future<void> _sendMessage() async {
    if (_isSendLocked) {
      return;
    }

    final String typedQuestion = _messageController.text.trim();

    if ((typedQuestion.isEmpty && _selectedAttachments.isEmpty) ||
        _isThinking) {
      return;
    }

    _isSendLocked = true;

    try {
      final String question = typedQuestion.isEmpty
          ? 'Read the selected attachment carefully, explain the important information, and mention anything unclear.'
          : typedQuestion;

      final List<ChatAttachment> sentAttachments = List<ChatAttachment>.from(
        _selectedAttachments,
      );

      bool saveAttachments = false;
      Map<String, String>? saveDestination;

      if (sentAttachments.isNotEmpty) {
        final bool? selectedAction = await _chooseAttachmentAction();

        if (selectedAction == null || !mounted) {
          return;
        }

        saveAttachments = selectedAction;

        if (saveAttachments) {
          saveDestination = await _chooseSaveDestination();

          if (saveDestination == null || !mounted) {
            return;
          }
        }
      }

      if (sentAttachments.isEmpty && await _handleMemoryCommand(question)) {
        return;
      }

      if (sentAttachments.isEmpty && _isCurrentUserNameQuestion(question)) {
        final String answer = await _currentUserNameAnswer(question);
        await _appendImmediateAnswer(question: question, answer: answer);
        return;
      }

      if (sentAttachments.isEmpty && _isCreatorQuestion(question)) {
        await _appendImmediateAnswer(
          question: question,
          answer: _creatorAnswer(question),
        );
        return;
      }

      await _ensureActiveChat(question);

      final ChatMessage userMessage = ChatMessage(
        id: _createId(),
        text: question,
        isUser: true,
        createdAt: DateTime.now(),
        attachments: sentAttachments,
      );

      setState(() {
        _messages.add(userMessage);
        _messageController.clear();
        _selectedAttachments.clear();
        _isThinking = true;
      });

      _messageFocusNode.unfocus();
      _scrollToBottom();
      unawaited(_persistCurrentChat());
      final List<String> memoryContext = await _memoryContextForQuestion(
        question,
      );

      if (saveAttachments && saveDestination != null) {
        final bool saved = await _saveAttachmentsToKnowledge(
          attachments: sentAttachments,
          space: saveDestination['space']!,
          category: saveDestination['category']!,
        );

        if (!saved && mounted) {
          setState(() {
            _isThinking = false;
          });
          return;
        }
      }

      try {
        if (sentAttachments.isNotEmpty) {
          final List<GeminiKnowledgeFile> attachmentKnowledge = [];

          for (final ChatAttachment attachment in sentAttachments.take(3)) {
            try {
              final File file = File(attachment.path);
              if (!await file.exists()) continue;

              final Uint8List bytes = await file.readAsBytes();
              if (bytes.isEmpty || bytes.length > 6 * 1024 * 1024) continue;

              attachmentKnowledge.add(
                GeminiKnowledgeFile(
                  fileName: attachment.name,
                  category: 'Chat attachment',
                  extractedText: '',
                  mimeType: attachment.mimeType,
                  bytes: bytes,
                ),
              );
            } catch (_) {
              // Skip an unreadable attachment and continue with the others.
            }
          }

          if (attachmentKnowledge.isEmpty) {
            if (!mounted) return;
            setState(() {
              _appendMessageIfNotDuplicate(
                ChatMessage(
                  id: _createId(),
                  text:
                      'Keeper could not read the selected attachment. Please select a supported file under 6 MB and try again.',
                  isUser: false,
                  createdAt: DateTime.now(),
                  isError: true,
                ),
              );
              _isThinking = false;
            });
            _scrollToBottom();
            unawaited(_persistCurrentChat());
            return;
          }

          if (!await _reserveAiUsageOrNotify()) return;

          final String attachmentAnswer =
              await GeminiAnswerService.generateAnswer(
                question: question,
                knowledge: attachmentKnowledge,
                conversationContext: _recentConversationContext(),
                memoryContext: memoryContext,
                allowGeneralKnowledgeFallback: true,
              );

          if (!mounted) return;
          setState(() {
            _appendMessageIfNotDuplicate(
              ChatMessage(
                id: _createId(),
                text: attachmentAnswer,
                isUser: false,
                createdAt: DateTime.now(),
              ),
            );
            _isThinking = false;
          });
          _scrollToBottom();
          unawaited(_persistCurrentChat());
          return;
        }

        final KeeperQuestionAnalysis questionAnalysis =
            KeeperKnowledgeEngine.analyzeQuestion(question);
        final bool needsKeeperKnowledge =
            _questionExplicitlyNeedsKeeperKnowledge(question) ||
            questionAnalysis.asksForDocumentList ||
            (_recentConversationUsedDocuments() &&
                _looksLikeDocumentFollowUp(question));

        // Do not hit Supabase for ordinary/general questions. This was a major
        // source of mobile-network lag. Refresh only when the question actually
        // needs Keeper knowledge, and keep a warm in-memory cache otherwise.
        if (needsKeeperKnowledge &&
            (_documentsForScope().isEmpty || _knowledgeIsStale)) {
          await _loadKnowledge(showLoading: false);
        }

        // True general/creative questions bypass document retrieval completely.
        // This is both faster and prevents a coincidental keyword match in a
        // personal document from hijacking a normal conversation.
        if (!needsKeeperKnowledge) {
          if (!await _reserveAiUsageOrNotify()) return;

          final String generalAnswer = await GeminiAnswerService.generateAnswer(
            question: question,
            knowledge: const <GeminiKnowledgeFile>[],
            conversationContext: _recentConversationContext(),
            memoryContext: memoryContext,
            allowGeneralKnowledgeFallback: true,
          );

          if (!mounted) return;
          setState(() {
            _appendMessageIfNotDuplicate(
              ChatMessage(
                id: _createId(),
                text: generalAnswer,
                isUser: false,
                createdAt: DateTime.now(),
              ),
            );
            _isThinking = false;
          });
          _scrollToBottom();
          unawaited(_persistCurrentChat());
          return;
        }

        final List<Map<String, dynamic>> availableDocuments =
            _documentsForScope();

        if (availableDocuments.isEmpty) {
          if (needsKeeperKnowledge) {
            final User? currentUser = FirebaseAuth.instance.currentUser;
            final String accountLabel =
                currentUser?.email?.trim().isNotEmpty == true
                ? ' for ${currentUser!.email}'
                : ' for this signed-in account';
            final String emptyKnowledgeAnswer = _knowledgeLoadError == null
                ? 'I could not find any ${_scopeLabel(_selectedScope)} documents$accountLabel. '
                      'If the file was uploaded using another account or workspace, switch to that account/scope. '
                      'Otherwise upload it to Personal and ask again.'
                : 'Keeper could not load the ${_scopeLabel(_selectedScope)} documents$accountLabel right now. '
                      'Tap the refresh button and retry. If it still fails, the document database access needs checking.';

            if (!mounted) return;
            setState(() {
              _appendMessageIfNotDuplicate(
                ChatMessage(
                  id: _createId(),
                  text: emptyKnowledgeAnswer,
                  isUser: false,
                  createdAt: DateTime.now(),
                  isError: _knowledgeLoadError != null,
                ),
              );
              _isThinking = false;
            });
            _scrollToBottom();
            unawaited(_persistCurrentChat());
            return;
          }

          if (!await _reserveAiUsageOrNotify()) return;

          final String generalAnswer = await GeminiAnswerService.generateAnswer(
            question: question,
            knowledge: const <GeminiKnowledgeFile>[],
            conversationContext: _recentConversationContext(),
            memoryContext: memoryContext,
            allowGeneralKnowledgeFallback: true,
          );

          if (!mounted) return;

          setState(() {
            _appendMessageIfNotDuplicate(
              ChatMessage(
                id: _createId(),
                text: generalAnswer,
                isUser: false,
                createdAt: DateTime.now(),
              ),
            );
            _isThinking = false;
          });

          _scrollToBottom();
          unawaited(_persistCurrentChat());
          return;
        }

        final String normalizedQuestion = _cleanText(question);

        final List<_RankedDocument> results = _searchKnowledge(
          normalizedQuestion,
        );

        if (needsKeeperKnowledge && results.isEmpty) {
          if (!mounted) return;
          setState(() {
            _appendMessageIfNotDuplicate(
              ChatMessage(
                id: _createId(),
                text: 'I could not find a matching document or readable information in your Keeper knowledge. Try the document name, category, or a more specific keyword.',
                isUser: false,
                createdAt: DateTime.now(),
              ),
            );
            _isThinking = false;
          });
          _scrollToBottom();
          unawaited(_persistCurrentChat());
          return;
        }

        if (!_hasStrongKnowledgeMatch(question, results)) {
          if (needsKeeperKnowledge) {
            if (!mounted) return;
            setState(() {
              _appendMessageIfNotDuplicate(
                ChatMessage(
                  id: _createId(),
                  text: 'Relevant document not found in your Keeper knowledge. No unrelated source was used.',
                  isUser: false,
                  createdAt: DateTime.now(),
                ),
              );
              _isThinking = false;
            });
            _scrollToBottom();
            unawaited(_persistCurrentChat());
            return;
          }

          if (!await _reserveAiUsageOrNotify()) return;

          final String generalAnswer = await GeminiAnswerService.generateAnswer(
            question: question,
            knowledge: const <GeminiKnowledgeFile>[],
            conversationContext: _recentConversationContext(),
            memoryContext: memoryContext,
            allowGeneralKnowledgeFallback: true,
          );

          if (!mounted) return;

          setState(() {
            _appendMessageIfNotDuplicate(
              ChatMessage(
                id: _createId(),
                text: generalAnswer,
                isUser: false,
                createdAt: DateTime.now(),
              ),
            );
            _isThinking = false;
          });

          _scrollToBottom();
          unawaited(_persistCurrentChat());
          return;
        }

        // Most questions only need the single strongest source. Sending a
        // second document by default increases prompt size and latency and can
        // introduce unrelated context. Comparisons explicitly use two.
        final int sourceCount = questionAnalysis.asksForComparison ? 2 : 1;
        final List<_RankedDocument> topResults =
            results.take(sourceCount).toList();

        if (questionAnalysis.asksForDocumentList) {
          final String listAnswer = _buildDocumentListAnswer(question, results);
          final List<ChatSource> listSources = _smartSourcesForAnswer(
            answer: listAnswer,
            question: question,
            results: topResults,
            isDocumentList: true,
          );

          final ChatMessage fastMessage = ChatMessage(
            id: _createId(),
            text: listAnswer,
            isUser: false,
            createdAt: DateTime.now(),
            sources: listSources,
          );

          if (!mounted) return;

          setState(() {
            _appendMessageIfNotDuplicate(fastMessage);
            _isThinking = false;
          });

          _scrollToBottom();
          unawaited(_persistCurrentChat());
          return;
        }

        final ChatMessage? cachedMessage = memoryContext.isEmpty
            ? _cachedAnswerFor(question: question, results: topResults)
            : null;

        if (cachedMessage != null) {
          if (!mounted) return;

          setState(() {
            _appendMessageIfNotDuplicate(
              ChatMessage(
                id: _createId(),
                text: cachedMessage.text,
                isUser: false,
                createdAt: DateTime.now(),
                sources: _smartSourcesForAnswer(
                  answer: cachedMessage.text,
                  question: question,
                  results: topResults,
                ),
              ),
            );
            _isThinking = false;
          });

          _scrollToBottom();
          unawaited(_persistCurrentChat());
          return;
        }

        final bool topResultNeedsVisualHelp = topResults.any((result) {
          final String name =
              result.document['file_name']?.toString().toLowerCase() ?? '';
          final String text =
              result.document['extracted_text']?.toString().trim() ?? '';
          final bool isVisualFile =
              name.endsWith('.jpg') ||
              name.endsWith('.jpeg') ||
              name.endsWith('.png') ||
              name.endsWith('.webp') ||
              name.endsWith('.pdf');
          return isVisualFile && text.length < 80;
        });

        final bool needsVisualAnalysis =
            questionAnalysis.needsOriginalFile || topResultNeedsVisualHelp;

        final List<GeminiKnowledgeFile> knowledge = needsVisualAnalysis
            ? <GeminiKnowledgeFile>[]
            : _buildTextOnlyKnowledge(topResults, question: question);

        if (needsVisualAnalysis) {
          // Download the few selected source files together. Previously each
          // file could consume its full network timeout before the next one
          // started, which made visual-document questions feel unnecessarily
          // slow on mobile data.
          final int visualFileCount =
              questionAnalysis.asksForComparison ? 2 : 1;
          final List<GeminiKnowledgeFile?> visualFiles = await Future.wait(
            topResults.take(visualFileCount).map(_buildVisualKnowledgeFile),
          );
          knowledge.addAll(visualFiles.whereType<GeminiKnowledgeFile>());
        }

        if (knowledge.isEmpty) {
          knowledge.addAll(
            _buildTextOnlyKnowledge(topResults, question: question),
          );
        }

        // For simple exact-value questions (PAN/Aadhaar/phone/email/roll
        // number/percentage/amount/date) that don't need visual layout
        // understanding, try to answer directly from the already-extracted
        // text first. This is instant, works offline, and does not spend
        // any of the daily Gemini quota.
        String? answer;
        if (!needsVisualAnalysis) {
          final LocalAnswerResult localResult = LocalAnswerService.generateAnswer(
            question: question,
            relevantTexts: topResults
                .map((result) => result.document['extracted_text']?.toString() ?? '')
                .toList(),
          );

          if (localResult.foundDirectAnswer && localResult.confidence >= 0.85) {
            answer = localResult.answer;
          }
        }

        if (answer == null) {
          if (!await _reserveAiUsageOrNotify()) return;

          answer = await GeminiAnswerService.generateAnswer(
            question: question,
            knowledge: knowledge,
            conversationContext: _recentConversationContext(),
            memoryContext: memoryContext,
            allowGeneralKnowledgeFallback: false,
          );
        }

        if (!mounted) return;

        final List<ChatSource> smartSources = _smartSourcesForAnswer(
          answer: answer,
          question: question,
          results: topResults,
        );

        final ChatMessage answerMessage = ChatMessage(
          id: _createId(),
          text: answer,
          isUser: false,
          createdAt: DateTime.now(),
          sources: smartSources,
        );

        if (memoryContext.isEmpty) {
          _storeCachedAnswer(
            question: question,
            results: topResults,
            message: answerMessage,
          );
        }

        setState(() {
          _appendMessageIfNotDuplicate(answerMessage);
          _isThinking = false;
        });

        _scrollToBottom();
        unawaited(_persistCurrentChat());
      } catch (error, stackTrace) {
        developer.log(
          'Chat request failed before an answer was displayed: $error',
          name: 'KEEPER_CHAT',
          error: error,
          stackTrace: stackTrace,
        );

        if (!mounted) return;

        setState(() {
          _appendMessageIfNotDuplicate(
            ChatMessage(
              id: _createId(),
              text:
                  'Keeper AI could not complete this request right now. Please try again once.',
              isUser: false,
              createdAt: DateTime.now(),
              isError: true,
            ),
          );

          _isThinking = false;
        });

        _scrollToBottom();
        unawaited(_persistCurrentChat());
      }
    } finally {
      _isSendLocked = false;
    }
  }

  String _scopeLabel(KnowledgeScope scope) {
    switch (scope) {
      case KnowledgeScope.personal:
        return 'Personal';

      case KnowledgeScope.organization:
        return 'Organization';

      case KnowledgeScope.all:
        return 'All';
    }
  }

  IconData _scopeIcon(KnowledgeScope scope) {
    switch (scope) {
      case KnowledgeScope.personal:
        return Icons.person_outline_rounded;

      case KnowledgeScope.organization:
        return Icons.apartment_rounded;

      case KnowledgeScope.all:
        return Icons.all_inclusive_rounded;
    }
  }

  String _formatTime(DateTime dateTime) {
    final int hour = dateTime.hour > 12
        ? dateTime.hour - 12
        : dateTime.hour == 0
        ? 12
        : dateTime.hour;

    final String minute = dateTime.minute.toString().padLeft(2, '0');

    final String period = dateTime.hour >= 12 ? 'PM' : 'AM';

    return '$hour:$minute $period';
  }

  void _changeScope(KnowledgeScope scope) {
    if (_isThinking) return;

    setState(() {
      _selectedScope = scope;
    });

    _showMessage('${_scopeLabel(scope)} knowledge selected.');
  }

  Widget _buildScopeSelector() {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: KnowledgeScope.values.map((scope) {
          final bool selected = scope == _selectedScope;

          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: GestureDetector(
              onTap: () {
                _changeScope(scope);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFF766DFF)
                      : const Color(0xFF121725),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selected
                        ? const Color(0xFF766DFF)
                        : const Color(0xFF292F42),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(_scopeIcon(scope), size: 18, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      _scopeLabel(scope),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSourceCard(ChatSource source) {
    final bool hasPreview = source.previewUrl.trim().isNotEmpty;
    final String evidence = source.highlightedText.trim().isNotEmpty
        ? source.highlightedText.trim()
        : source.snippet.trim();

    return InkWell(
      onTap: () => _openSourceDocument(source),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF101522),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF293247)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 82,
                height: 96,
                child: hasPreview
                    ? Image.network(
                        source.previewUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) {
                          return _buildSourcePlaceholder(source);
                        },
                      )
                    : _buildSourcePlaceholder(source),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF262D43),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          source.typeLabel,
                          style: const TextStyle(
                            color: Color(0xFFAAA4FF),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (source.pageNumber != null) ...[
                        const SizedBox(width: 7),
                        Text(
                          'Page ${source.pageNumber}',
                          style: const TextStyle(
                            color: Color(0xFF8F96A8),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    source.fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    source.category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF9B95FF),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (evidence.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Text(
                      evidence,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFB8BECC),
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  const Row(
                    children: [
                      Icon(
                        Icons.open_in_new_rounded,
                        color: Color(0xFFAAA4FF),
                        size: 14,
                      ),
                      SizedBox(width: 5),
                      Text(
                        'View original source',
                        style: TextStyle(
                          color: Color(0xFFAAA4FF),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourcePlaceholder(ChatSource source) {
    IconData icon = Icons.description_rounded;

    if (source.isPdf) {
      icon = Icons.picture_as_pdf_rounded;
    } else if (source.isImage) {
      icon = Icons.image_rounded;
    }

    return ColoredBox(
      color: const Color(0xFF1B2232),
      child: Center(
        child: Icon(icon, size: 34, color: const Color(0xFF918AFF)),
      ),
    );
  }

  String _cleanAssistantAnswer(String value) {
    String cleaned = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    // Keep copied/shared formulas readable outside Keeper. Inside the chat,
    // formula-only lines are rendered as real mathematical notation below.
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'\\frac\{([^{}]+)\}\{([^{}]+)\}'),
      (match) => '(${match.group(1)})/(${match.group(2)})',
    );

    cleaned = cleaned.replaceAllMapped(
      RegExp(r'\*\*(.*?)\*\*', dotAll: true),
      (match) => match.group(1) ?? '',
    );
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'__(.*?)__', dotAll: true),
      (match) => match.group(1) ?? '',
    );
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'`([^`]*)`'),
      (match) => match.group(1) ?? '',
    );
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'\\(?:text|mathrm|operatorname)\{([^}]*)\}'),
      (match) => match.group(1) ?? '',
    );

    cleaned = cleaned
        .replaceAll(r'\(', '')
        .replaceAll(r'\)', '')
        .replaceAll(r'\[', '')
        .replaceAll(r'\]', '')
        .replaceAll(r'\,', ' ')
        .replaceAll(r'\;', ' ')
        .replaceAll(r'\:', ' ')
        .replaceAll(r'\times', '×')
        .replaceAll(r'\cdot', '·')
        .replaceAll(r'\leq', '≤')
        .replaceAll(r'\geq', '≥')
        .replaceAll(r'\neq', '≠')
        .replaceAll(r'\approx', '≈')
        .replaceAll(r'\degree', '°')
        .replaceAll(r'\rho', 'ρ')
        .replaceAll(r'\theta', 'θ')
        .replaceAll(r'\alpha', 'α')
        .replaceAll(r'\beta', 'β')
        .replaceAll(r'\gamma', 'γ')
        .replaceAll(r'\Delta', 'Δ')
        .replaceAll(r'\delta', 'δ')
        .replaceAll(r'\pi', 'π')
        .replaceAll(r'\infty', '∞')
        .replaceAll(r'\sqrt', '√')
        .replaceAll(r'\%', '%')
        .replaceAll(r'\_', '_')
        .replaceAll(r'\&', '&')
        .replaceAll(r'$', '')
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .trim();

    final RegExp numberedPoint = RegExp(r'^\s*(\d+)[.)]\s+(.+)$');
    final RegExp bulletPoint = RegExp(r'^\s*[-*•▪◦]\s+(.+)$');
    final RegExp markdownHeading = RegExp(r'^\s*#{1,6}\s*(.+)$');
    final RegExp plainHeading = RegExp(r'^[A-Za-z][A-Za-z0-9 &/()\-]{1,45}:$');

    final List<String> output = <String>[];

    void addBlankLine() {
      if (output.isNotEmpty && output.last.trim().isNotEmpty) {
        output.add('');
      }
    }

    for (final String rawLine in cleaned.split('\n')) {
      String line = rawLine.trimRight();

      if (line.trim().isEmpty) {
        addBlankLine();
        continue;
      }

      final RegExpMatch? headingMatch = markdownHeading.firstMatch(line);
      if (headingMatch != null) {
        addBlankLine();
        output.add(headingMatch.group(1)!.trim());
        output.add('');
        continue;
      }

      if (plainHeading.hasMatch(line.trim())) {
        addBlankLine();
        output.add(line.trim());
        output.add('');
        continue;
      }

      final RegExpMatch? numberedMatch = numberedPoint.firstMatch(line);
      if (numberedMatch != null) {
        addBlankLine();
        output.add(
          '${numberedMatch.group(1)}. ${numberedMatch.group(2)!.trim()}',
        );
        output.add('');
        continue;
      }

      final RegExpMatch? bulletMatch = bulletPoint.firstMatch(line);
      if (bulletMatch != null) {
        addBlankLine();
        output.add('• ${bulletMatch.group(1)!.trim()}');
        output.add('');
        continue;
      }

      output.add(line.trim());
    }

    return output.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  Future<GeminiKnowledgeFile?> _buildVisualKnowledgeFile(
    _RankedDocument result,
  ) async {
    final Map<String, dynamic> document = result.document;
    final String fileName =
        document['file_name']?.toString() ?? 'Unnamed document';
    final String category = document['category']?.toString() ?? 'Other';
    final String extractedText =
        document['extracted_text']?.toString() ?? '';
    final String fileUrl = document['file_url']?.toString() ?? '';
    final String mimeType = _detectMimeType(
      fileName: fileName,
      fileUrl: fileUrl,
    );
    final Uint8List? originalFileBytes = await _downloadFileBytes(
      document: document,
      mimeType: mimeType,
    );

    if (extractedText.trim().isEmpty &&
        (originalFileBytes == null || originalFileBytes.isEmpty)) {
      return null;
    }

    return GeminiKnowledgeFile(
      fileName: fileName,
      category: category,
      extractedText: extractedText,
      mimeType: mimeType,
      bytes: originalFileBytes,
    );
  }

  bool _looksLikeDisplayMath(String line) {
    final String value = line.trim();
    if (value.isEmpty) return false;

    final bool hasMathCommand = RegExp(
      r'\\(?:frac|sqrt|sum|int|rho|theta|alpha|beta|gamma|delta|Delta|pi|sigma|omega|mu|lambda|cdot|times)\b',
    ).hasMatch(value);
    final bool hasEquation = value.contains('=') &&
        RegExp(r'[A-Za-z0-9})]\s*[+\-*/^_=]').hasMatch(value);
    final bool mostlyFormula = !RegExp(r'[.!?]\s+[A-Za-z]').hasMatch(value) &&
        value.split(RegExp(r'\s+')).length <= 18;

    return (hasMathCommand || hasEquation) && mostlyFormula;
  }

  String _normaliseLatex(String value) {
    String latex = value.trim();
    latex = latex
        .replaceAll(RegExp(r'^\s*[-*•]\s*'), '')
        .replaceAll(RegExp(r'^\s*\d+[.)]\s*'), '')
        .replaceAll(r'\[', '')
        .replaceAll(r'\]', '')
        .replaceAll(r'\(', '')
        .replaceAll(r'\)', '')
        .replaceAll(r'$$', '')
        .replaceAll(r'$', '')
        .replaceAll('×', r'\times ')
        .replaceAll('·', r'\cdot ')
        .trim();
    return latex;
  }

  Widget _buildAssistantMessageText(String rawText) {
    final String normalized = rawText
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final List<Widget> blocks = <Widget>[];

    for (final String rawBlock in normalized.split('\n')) {
      final String line = rawBlock.trim();
      if (line.isEmpty) {
        blocks.add(const SizedBox(height: 10));
        continue;
      }

      if (_looksLikeDisplayMath(line)) {
        blocks.add(
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Math.tex(
                _normaliseLatex(line),
                mathStyle: MathStyle.display,
                textStyle: const TextStyle(color: Colors.white, fontSize: 17),
                onErrorFallback: (error) => SelectableText(
                  _cleanAssistantAnswer(line),
                  style: const TextStyle(
                    color: Colors.white,
                    height: 1.5,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
        );
      } else {
        blocks.add(
          SelectableText(
            _cleanAssistantAnswer(line),
            style: const TextStyle(
              color: Colors.white,
              height: 1.5,
              fontSize: 14,
            ),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
  }

  String _messageTextForActions(ChatMessage message) {
    return message.isUser
        ? message.text.trim()
        : _cleanAssistantAnswer(message.text);
  }

  Future<void> _copyMessage(ChatMessage message) async {
    await Clipboard.setData(
      ClipboardData(text: _messageTextForActions(message)),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Message copied.')));
  }

  Future<void> _shareMessage(ChatMessage message) async {
    await SharePlus.instance.share(
      ShareParams(
        text: _messageTextForActions(message),
        subject: message.isUser ? 'Keeper message' : 'Keeper AI answer',
      ),
    );
  }

  Widget _buildMessageAttachmentPreview(ChatAttachment attachment) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 74,
        height: 74,
        child: attachment.isImage
            ? Image.file(
                File(attachment.path),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    _buildAttachmentPlaceholder(attachment),
              )
            : _buildAttachmentPlaceholder(attachment),
      ),
    );
  }

  Widget _buildAttachmentPlaceholder(ChatAttachment attachment) {
    return ColoredBox(
      color: const Color(0xFF242A3D),
      child: Center(
        child: Icon(
          attachment.isPdf
              ? Icons.picture_as_pdf_rounded
              : Icons.description_rounded,
          color: const Color(0xFFAAA4FF),
          size: 30,
        ),
      ),
    );
  }

  Widget _buildMessage(ChatMessage message) {
    final bool isUser = message.isUser;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        constraints: const BoxConstraints(maxWidth: 360),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF766DFF) : const Color(0xFF151B2A),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isUser ? const Color(0xFF766DFF) : const Color(0xFF263247),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.attachments.isNotEmpty) ...[
              SizedBox(
                height: 74,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  shrinkWrap: true,
                  itemCount: message.attachments.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    return _buildMessageAttachmentPreview(
                      message.attachments[index],
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (message.isUser)
              SelectableText(
                message.text,
                style: const TextStyle(
                  color: Colors.white,
                  height: 1.5,
                  fontSize: 14,
                ),
              )
            else
              _buildAssistantMessageText(message.text),

            if (!message.isUser && message.sources.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(
                'Sources Used (${message.sources.length})',
                style: const TextStyle(
                  color: Color(0xFFAAA4FF),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              ...message.sources.map(_buildSourceCard),
            ],

            const SizedBox(height: 10),

            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(message.createdAt),
                  style: const TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(width: 8),
                _MessageAction(
                  icon: Icons.copy_rounded,
                  label: 'Copy',
                  onTap: () => _copyMessage(message),
                ),
                const SizedBox(width: 3),
                _MessageAction(
                  icon: Icons.share_outlined,
                  label: 'Share',
                  onTap: () => _shareMessage(message),
                ),
                if (!message.isUser && !message.isError) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => _reportAiMessage(message),
                    borderRadius: BorderRadius.circular(20),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.flag_outlined,
                            color: Color(0xFF9CA3AF),
                            size: 14,
                          ),
                          SizedBox(width: 3),
                          Text(
                            'Report',
                            style: TextStyle(
                              color: Color(0xFF9CA3AF),
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAttachmentOptions() async {
    if (_isThinking) {
      return;
    }

    _messageFocusNode.unfocus();

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF121725),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
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
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Add to Keeper AI',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Choose a photo or document to ask about.',
                  style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _buildAttachmentOption(
                        icon: Icons.camera_alt_rounded,
                        title: 'Take Photo',
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _takePhoto();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildAttachmentOption(
                        icon: Icons.photo_library_rounded,
                        title: 'Choose Images',
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _chooseImages();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildAttachmentOption(
                        icon: Icons.picture_as_pdf_rounded,
                        title: 'Choose PDF',
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _choosePdf();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildAttachmentOption(
                        icon: Icons.description_rounded,
                        title: 'Documents',
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _chooseDocuments();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAttachmentOption({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFF1A2030),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2F4A),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: const Color(0xFFAAA4FF), size: 23),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _mimeTypeFromName(String name) {
    final String lower = name.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.txt') ||
        lower.endsWith('.md') ||
        lower.endsWith('.csv') ||
        lower.endsWith('.log')) {
      return 'text/plain';
    }
    return 'application/octet-stream';
  }

  void _addSelectedAttachments(List<ChatAttachment> attachments) {
    if (!mounted || attachments.isEmpty) return;

    setState(() {
      for (final ChatAttachment attachment in attachments) {
        final bool alreadySelected = _selectedAttachments.any(
          (item) => item.path == attachment.path,
        );
        if (!alreadySelected && _selectedAttachments.length < 5) {
          _selectedAttachments.add(attachment);
        }
      }
    });

    _messageFocusNode.requestFocus();
  }

  void _removeSelectedAttachment(int index) {
    setState(() {
      _selectedAttachments.removeAt(index);
    });
  }

  void _clearSelectedAttachments() {
    setState(() {
      _selectedAttachments.clear();
    });
  }

  Future<void> _takePhoto() async {
    if (_isPickingAttachment) return;
    setState(() => _isPickingAttachment = true);

    try {
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 92,
      );

      if (photo == null) return;

      _addSelectedAttachments([
        ChatAttachment(
          name: photo.name,
          path: photo.path,
          mimeType: _mimeTypeFromName(photo.name),
        ),
      ]);
    } finally {
      if (mounted) setState(() => _isPickingAttachment = false);
    }
  }

  Future<void> _chooseImages() async {
    if (_isPickingAttachment) return;
    setState(() => _isPickingAttachment = true);

    try {
      final List<XFile> images = await _imagePicker.pickMultiImage(
        imageQuality: 92,
      );

      _addSelectedAttachments(
        images
            .map(
              (image) => ChatAttachment(
                name: image.name,
                path: image.path,
                mimeType: _mimeTypeFromName(image.name),
              ),
            )
            .toList(),
      );
    } finally {
      if (mounted) setState(() => _isPickingAttachment = false);
    }
  }

  Future<void> _choosePdf() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      allowMultiple: true,
    );

    if (result == null) return;

    _addSelectedAttachments(
      result.files
          .where((file) => file.path != null)
          .map(
            (file) => ChatAttachment(
              name: file.name,
              path: file.path!,
              mimeType: 'application/pdf',
            ),
          )
          .toList(),
    );
  }

  Future<void> _chooseDocuments() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'txt',
        'md',
        'csv',
        'log',
        'pdf',
        'jpg',
        'jpeg',
        'png',
        'webp',
      ],
      allowMultiple: true,
    );

    if (result == null) return;

    _addSelectedAttachments(
      result.files
          .where((file) => file.path != null)
          .map(
            (file) => ChatAttachment(
              name: file.name,
              path: file.path!,
              mimeType: _mimeTypeFromName(file.name),
            ),
          )
          .toList(),
    );
  }

  Widget _buildSelectedAttachmentsPreview({required bool compact}) {
    if (_selectedAttachments.isEmpty) return const SizedBox.shrink();

    final double previewHeight = compact ? 58 : 74;
    final double previewWidth = compact ? 58 : 74;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF151B2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2B3142)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                size: 17,
                color: Color(0xFF7ED7A9),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  _selectedAttachments.length == 1
                      ? '1 attachment selected'
                      : '${_selectedAttachments.length} attachments selected',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                onPressed: _clearSelectedAttachments,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: previewHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _selectedAttachments.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final ChatAttachment attachment = _selectedAttachments[index];

                return SizedBox(
                  width: compact ? 150 : 180,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF20273A),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(9),
                          child: SizedBox(
                            width: previewWidth,
                            height: previewHeight - 10,
                            child: attachment.isImage
                                ? Image.file(
                                    File(attachment.path),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) =>
                                        _buildAttachmentPlaceholder(attachment),
                                  )
                                : _buildAttachmentPlaceholder(attachment),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            attachment.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              height: 1.25,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => _removeSelectedAttachment(index),
                          borderRadius: BorderRadius.circular(99),
                          child: const Padding(
                            padding: EdgeInsets.all(3),
                            child: Icon(
                              Icons.close_rounded,
                              color: Color(0xFFFF7D92),
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (!compact) ...[
            const SizedBox(height: 7),
            const Text(
              'Type a question below. These files will be used for this chat only.',
              style: TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 10.5,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildThinkingWidget() {
    return const Padding(
      padding: EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF766DFF)),
          SizedBox(width: 14),
          Text(
            'Keeper AI is thinking...',
            style: TextStyle(color: Color(0xFFB8BBC7)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFF090D18),
      appBar: AppBar(
        backgroundColor: const Color(0xFF090D18),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          _activeChatTitle == 'New Chat' ? 'Keeper AI' : _activeChatTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Keeper Memory',
            onPressed: _isThinking ? null : _openKeeperMemory,
            icon: const Icon(Icons.psychology_alt_rounded),
          ),
          IconButton(
            tooltip: 'New chat',
            onPressed: _isThinking ? null : _startNewChat,
            icon: const Icon(Icons.add_comment_rounded),
          ),
          IconButton(
            tooltip: 'Chat history',
            onPressed: _isThinking ? null : _openChatHistory,
            icon: const Icon(Icons.history_rounded),
          ),
          IconButton(
            onPressed: _isLoadingKnowledge
                ? null
                : () => _loadKnowledge(showLoading: false),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              decoration: const BoxDecoration(
                color: Color(0xFF0F1421),
                border: Border(bottom: BorderSide(color: Color(0xFF222A3A))),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Search scope',
                    style: TextStyle(
                      color: Color(0xFF8E91A3),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 9),
                  _buildScopeSelector(),
                  const SizedBox(height: 8),
                  Text(
                    _isLoadingKnowledge
                        ? 'Loading your knowledge...'
                        : _knowledgeLoadError != null &&
                              _documentsForScope().isEmpty
                        ? 'Could not load documents • tap refresh'
                        : '${_documentsForScope().length} documents available',
                    style: TextStyle(
                      color:
                          _knowledgeLoadError != null &&
                              _documentsForScope().isEmpty
                          ? const Color(0xFFFF9B9B)
                          : const Color(0xFF777A8A),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: _isLoadingSavedChat
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF766DFF),
                      ),
                    )
                  : RefreshIndicator(
                      color: const Color(0xFF766DFF),
                      backgroundColor: const Color(0xFF121725),
                      onRefresh: () => _loadKnowledge(showLoading: false),
                      child: ListView.builder(
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                        itemCount: _messages.length + (_isThinking ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (_isThinking && index == _messages.length) {
                            return _buildThinkingWidget();
                          }

                          return _buildMessage(_messages[index]);
                        },
                      ),
                    ),
            ),

            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              decoration: const BoxDecoration(
                color: Color(0xFF0F1421),
                border: Border(top: BorderSide(color: Color(0xFF222A3A))),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isSavingAttachments && _totalAttachmentsToSave > 0) ...[
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF151B2A),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: const Color(0xFF2B3142)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Saving to Keeper... '
                            '$_savedAttachmentCount/$_totalAttachmentsToSave',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 9),
                          LinearProgressIndicator(
                            value:
                                _savedAttachmentCount / _totalAttachmentsToSave,
                            minHeight: 6,
                            borderRadius: BorderRadius.circular(20),
                            backgroundColor: const Color(0xFF292F42),
                            color: const Color(0xFF766DFF),
                          ),
                        ],
                      ),
                    ),
                  ],
                  _buildSelectedAttachmentsPreview(compact: keyboardVisible),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          focusNode: _messageFocusNode,
                          enabled: !_isThinking,
                          minLines: 1,
                          maxLines: 5,
                          textInputAction: TextInputAction.newline,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: _selectedAttachments.isNotEmpty
                                ? 'Ask about selected attachment(s)...'
                                : _isLoadingKnowledge
                                ? 'Loading knowledge...'
                                : 'Ask Keeper anything...',
                            hintStyle: const TextStyle(
                              color: Color(0xFF737B8E),
                            ),
                            filled: true,
                            fillColor: const Color(0xFF151B2A),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A2030),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFF2B3142)),
                        ),
                        child: IconButton(
                          tooltip: 'Attach file',
                          onPressed: _isThinking
                              ? null
                              : _showAttachmentOptions,
                          icon: const Icon(
                            Icons.add_rounded,
                            color: Color(0xFFAAA4FF),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: _isThinking || _isLoadingKnowledge
                              ? const Color(0xFF343A4B)
                              : const Color(0xFF766DFF),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: IconButton(
                          onPressed: _isThinking || _isLoadingKnowledge
                              ? null
                              : _sendMessage,
                          icon: _isThinking
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.arrow_upward_rounded,
                                  color: Colors.white,
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MessageAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFF9CA3AF), size: 14),
            const SizedBox(width: 3),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
