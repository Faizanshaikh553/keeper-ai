import 'dart:collection';
import 'dart:math';

enum KeeperQuestionMode { fast, knowledge, vision, advanced }

class KeeperKnowledgeDocument {
  final String id;
  final String fileName;
  final String category;
  final String space;
  final String fileUrl;
  final String extractedText;
  final String organizationId;
  final String visibility;
  final DateTime? createdAt;
  final Map<String, dynamic> raw;

  const KeeperKnowledgeDocument({
    required this.id,
    required this.fileName,
    required this.category,
    required this.space,
    required this.fileUrl,
    required this.extractedText,
    required this.organizationId,
    required this.visibility,
    required this.createdAt,
    required this.raw,
  });

  factory KeeperKnowledgeDocument.fromMap(Map<String, dynamic> map) {
    return KeeperKnowledgeDocument(
      id: map['id']?.toString() ?? '',
      fileName: map['file_name']?.toString() ?? 'Unnamed document',
      category: map['category']?.toString() ?? 'Other',
      space: map['space']?.toString() ?? 'personal',
      fileUrl: map['file_url']?.toString() ?? '',
      extractedText: map['extracted_text']?.toString() ?? '',
      organizationId: map['organization_id']?.toString() ?? '',
      visibility: map['visibility']?.toString() ?? '',
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? ''),
      raw: Map<String, dynamic>.from(map),
    );
  }

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

  bool get isTextFile => fileName.toLowerCase().endsWith('.txt');

  String get documentType {
    if (isImage) return 'image';
    if (isPdf) return 'pdf';
    if (isTextFile) return 'text';

    final String lowerName = fileName.toLowerCase();
    if (lowerName.endsWith('.doc') || lowerName.endsWith('.docx')) {
      return 'document';
    }
    return 'file';
  }
}

class KeeperRankedDocument {
  final KeeperKnowledgeDocument document;
  final double score;
  final String snippet;
  final List<String> matchedTerms;

  const KeeperRankedDocument({
    required this.document,
    required this.score,
    required this.snippet,
    required this.matchedTerms,
  });
}

class KeeperQuestionAnalysis {
  final KeeperQuestionMode mode;
  final bool needsOriginalFile;
  final bool asksForDocumentList;
  final bool asksForComparison;
  final List<String> searchTerms;

  const KeeperQuestionAnalysis({
    required this.mode,
    required this.needsOriginalFile,
    required this.asksForDocumentList,
    required this.asksForComparison,
    required this.searchTerms,
  });
}

class KeeperKnowledgeEngine {
  KeeperKnowledgeEngine._();

  static final LinkedHashMap<String, List<KeeperRankedDocument>> _searchCache =
      LinkedHashMap<String, List<KeeperRankedDocument>>();
  static const int _maximumSearchCacheEntries = 50;

  static KeeperQuestionAnalysis analyzeQuestion(String question) {
    final String normalized = _normalize(question);
    final List<String> terms = _expandedTerms(_importantTerms(normalized));

    final bool asksForListDirectly = _containsAny(normalized, const [
      'show all',
      'find all',
      'list all',
      'which documents',
      'what documents',
      'which files',
      'what files',
      'documents do i have',
      'files do i have',
      'mere documents',
      'meri files',
      'documents dikhao',
      'files dikhao',
      'kon konse documents',
      'kon kon se documents',
      'kaun konse documents',
      'kaun kaun se documents',
      'documents hai mere',
      'documents hain mere',
      'mere paas documents',
      'mere pass documents',
      'tumhare paas documents',
      'tumhare pass documents',
    ]);

    final bool mentionsDocumentCollection = _containsAny(normalized, const [
      'document',
      'documents',
      'file',
      'files',
      'pdf',
      'pdfs',
    ]);
    final bool usesInventoryLanguage = _containsAny(normalized, const [
      'which',
      'what',
      'list',
      'show',
      'all',
      'how many',
      'kon',
      'kaun',
      'konse',
      'kaunse',
      'kya kya',
      'kitne',
      'sab',
      'paas',
      'pass',
      'dikhao',
      'batao',
    ]);
    final bool asksForList =
        asksForListDirectly ||
        (mentionsDocumentCollection && usesInventoryLanguage);

    final bool asksForComparison = _containsAny(normalized, const [
      'compare',
      'difference between',
      'differences between',
      'versus',
      ' vs ',
      'similarities',
      'dono documents',
      'in dono',
    ]);

    final bool visualQuestion = _containsAny(normalized, const [
      'image',
      'photo',
      'picture',
      'scan',
      'handwritten',
      'handwriting',
      'written by hand',
      'diagram',
      'table',
      'row',
      'column',
      'marksheet',
      'visible',
      'what is written',
      'read this',
      'exact question',
      'question number',
      'roll number',
      'signature',
    ]);

    final KeeperQuestionMode mode = asksForList
        ? KeeperQuestionMode.fast
        : asksForComparison
        ? KeeperQuestionMode.advanced
        : visualQuestion
        ? KeeperQuestionMode.vision
        : KeeperQuestionMode.knowledge;

    return KeeperQuestionAnalysis(
      mode: mode,
      needsOriginalFile:
          mode == KeeperQuestionMode.vision ||
          mode == KeeperQuestionMode.advanced,
      asksForDocumentList: asksForList,
      asksForComparison: asksForComparison,
      searchTerms: terms,
    );
  }

  static List<KeeperRankedDocument> search({
    required String question,
    required List<Map<String, dynamic>> documents,
    int limit = 5,
  }) {
    final String normalizedQuestion = _normalize(question);
    final KeeperQuestionAnalysis analysis = analyzeQuestion(question);
    final List<String> queryTerms = analysis.searchTerms;
    final bool asksAboutIdentityDocument = _containsAny(
      normalizedQuestion,
      const [
        'aadhaar',
        'aadhar',
        'adhar',
        'uidai',
        'identity card',
        'id card',
        'pan',
        'pan card',
        'pancard',
        'permanent account number',
        'passport',
        'voter id',
        'voter card',
        'driving licence',
        'driving license',
        'dl',
      ],
    );

    final String cacheKey = <Object?>[
      normalizedQuestion,
      documents.length,
      ...documents
          .take(30)
          .map(
            (document) =>
                '${document['id'] ?? document['file_url'] ?? document['file_name']}'
                '|${document['updated_at'] ?? document['created_at']}'
                '|${document['processing_status']}'
                '|${document['extracted_text']?.toString().length ?? 0}',
          ),
    ].join('|');

    final List<KeeperRankedDocument>? cached = _searchCache[cacheKey];
    if (cached != null) return cached.take(limit).toList();

    final List<KeeperRankedDocument> ranked = <KeeperRankedDocument>[];

    for (final Map<String, dynamic> raw in documents) {
      final KeeperKnowledgeDocument document = KeeperKnowledgeDocument.fromMap(
        raw,
      );
      final String fileName = _normalize(
        _fileNameWithoutExtension(document.fileName),
      );
      final String category = _normalize(document.category);
      // Large OCR/PDF text can reach millions of characters. Searching all of
      // it on every keystroke can freeze the UI isolate on lower-end phones.
      // Keep enough from the start and end to preserve IDs, headers and footer
      // metadata while making ranking predictable and fast.
      final String searchableText = _searchableText(document.extractedText);
      final String text = _normalize(searchableText);
      final String combined = '$fileName $category $text';
      final List<String> documentTokens = _tokens(combined);

      double score = 0;
      final Set<String> matchedTerms = <String>{};

      if (analysis.asksForDocumentList) {
        score += 18;
      }

      // Identity documents must be matched by their actual OCR/name/category.
      // Never boost every image/PDF just because the question mentions Aadhaar
      // or PAN; that was causing unrelated screenshots and notes to win.
      final bool identityMatch = asksAboutIdentityDocument &&
          _matchesIdentityDocument(combined, normalizedQuestion);
      if (identityMatch) {
        score += 180;
      }

      if (normalizedQuestion.isNotEmpty) {
        if (fileName == normalizedQuestion) {
          score += 240;
        } else if (fileName.startsWith(normalizedQuestion)) {
          score += 175;
        } else if (fileName.contains(normalizedQuestion)) {
          score += 135;
        }

        if (category == normalizedQuestion) {
          score += 115;
        } else if (category.contains(normalizedQuestion)) {
          score += 75;
        }

        if (text.contains(normalizedQuestion) &&
            normalizedQuestion.length >= 4) {
          score += 65;
        }
      }

      for (final String term in queryTerms) {
        double termScore = 0;

        if (fileName.contains(term)) termScore += 38;
        if (category.contains(term)) termScore += 24;

        final int textOccurrences = _countOccurrences(text, term);
        if (textOccurrences > 0) {
          termScore += 9 + min(18, (textOccurrences - 1) * 2);
        }

        if (termScore == 0 && term.length >= 5) {
          final bool fuzzyMatch = documentTokens.any(
            (token) => _isCloseToken(term, token),
          );
          if (fuzzyMatch) termScore += 4;
        }

        if (termScore > 0) {
          score += termScore;
          matchedTerms.add(term);
        }
      }

      if (queryTerms.isNotEmpty) {
        final double coverage = matchedTerms.length / queryTerms.length;
        score += coverage * 45;
        if (coverage == 1) score += 22;
      }

      if (asksAboutIdentityDocument && !identityMatch) {
        // A weak generic match (for example a WhatsApp chat containing
        // 'number') must not be returned as an Aadhaar/PAN source.
        score -= 120;
      }

      if (document.isTextFile && document.extractedText.trim().isNotEmpty) {
        score += 4;
      }

      final String processingStatus =
          raw['processing_status']?.toString().toLowerCase() ?? '';
      if (processingStatus == 'completed') score += 2;

      // Old documents are never penalised. Date is only a very small tie-breaker.
      if (document.createdAt != null) {
        final int ageDays = DateTime.now()
            .difference(document.createdAt!)
            .inDays;
        if (ageDays <= 30) score += 2;
      }

      if (score <= 0) continue;

      ranked.add(
        KeeperRankedDocument(
          document: document,
          score: score,
          snippet: buildSnippet(
            query: normalizedQuestion,
            extractedText: document.extractedText,
            searchTerms: queryTerms,
          ),
          matchedTerms: matchedTerms.toList(),
        ),
      );
    }

    ranked.sort((a, b) {
      final int byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final DateTime aDate = a.document.createdAt ?? DateTime(1970);
      final DateTime bDate = b.document.createdAt ?? DateTime(1970);
      return bDate.compareTo(aDate);
    });

    // Never return weak/random documents as sources. A result must have
    // meaningful evidence from filename/category/content before it can be
    // used by the AI pipeline.
    final double minimumScore = asksAboutIdentityDocument ? 35 : 12;
    final List<KeeperRankedDocument> relevant = ranked
        .where((result) => result.score >= minimumScore)
        .toList();

    _searchCache[cacheKey] = List<KeeperRankedDocument>.from(relevant);
    while (_searchCache.length > _maximumSearchCacheEntries) {
      _searchCache.remove(_searchCache.keys.first);
    }

    return relevant.take(limit).toList();
  }

  static String buildSnippet({
    required String query,
    required String extractedText,
    List<String> searchTerms = const <String>[],
    int maximumLength = 260,
  }) {
    final String cleaned = extractedText
        .replaceAll('\u0000', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (cleaned.isEmpty) return 'No extracted text available.';
    if (cleaned.length <= maximumLength) return cleaned;

    final String lower = cleaned.toLowerCase();
    int matchIndex = query.trim().length >= 3
        ? lower.indexOf(query.toLowerCase())
        : -1;
    int matchedLength = query.length;

    if (matchIndex < 0) {
      for (final String term in searchTerms) {
        final int index = lower.indexOf(term);
        if (index >= 0 && (matchIndex < 0 || index < matchIndex)) {
          matchIndex = index;
          matchedLength = term.length;
        }
      }
    }

    if (matchIndex < 0) return '${cleaned.substring(0, maximumLength)}...';

    final int before = maximumLength ~/ 3;
    final int start = max(0, matchIndex - before);
    final int end = min(cleaned.length, start + maximumLength + matchedLength);

    return '${start > 0 ? '...' : ''}${cleaned.substring(start, end)}'
        '${end < cleaned.length ? '...' : ''}';
  }

  static List<Map<String, dynamic>> buildCompactContext({
    required List<KeeperRankedDocument> results,
    int maximumCharactersPerDocument = 7000,
  }) {
    return results.map((result) {
      final KeeperKnowledgeDocument document = result.document;
      final String text =
          document.extractedText.length > maximumCharactersPerDocument
          ? document.extractedText.substring(0, maximumCharactersPerDocument)
          : document.extractedText;

      return <String, dynamic>{
        'id': document.id,
        'fileName': document.fileName,
        'category': document.category,
        'space': document.space,
        'documentType': document.documentType,
        'fileUrl': document.fileUrl,
        'text': text,
        'score': result.score,
        'snippet': result.snippet,
        'matchedTerms': result.matchedTerms,
      };
    }).toList();
  }

  static String buildDocumentListAnswer({
    required List<KeeperRankedDocument> results,
    required String scopeLabel,
    int maximumItems = 8,
  }) {
    if (results.isEmpty) {
      return 'No matching documents were found in $scopeLabel knowledge.';
    }

    final List<KeeperRankedDocument> visible = results
        .take(maximumItems)
        .toList();
    final StringBuffer buffer = StringBuffer(
      'I found ${results.length} matching document'
      '${results.length == 1 ? '' : 's'} in $scopeLabel knowledge.\n\n',
    );

    for (int index = 0; index < visible.length; index++) {
      final KeeperKnowledgeDocument document = visible[index].document;
      buffer.writeln('${index + 1}. ${document.fileName}');
      buffer.writeln('   Category: ${document.category}');
      buffer.writeln('   Space: ${document.space}');
    }

    if (results.length > visible.length) {
      buffer.writeln(
        '\n${results.length - visible.length} more matching documents are available.',
      );
    }
    return buffer.toString().trim();
  }

  static void clearCache() => _searchCache.clear();

  static List<String> _expandedTerms(List<String> terms) {
    const Map<String, List<String>> aliases = <String, List<String>>{
      'aadhaar': <String>[
        'aadhar',
        'adhar',
        'aadhaarcard',
        'aadharcard',
        'adharcard',
        'uidai',
        'identity',
      ],
      'aadhar': <String>[
        'aadhaar',
        'adhar',
        'aadhaarcard',
        'aadharcard',
        'adharcard',
        'uidai',
        'identity',
      ],
      'adhar': <String>[
        'aadhaar',
        'aadhar',
        'aadhaarcard',
        'aadharcard',
        'adharcard',
        'uidai',
        'identity',
      ],
      'aadhaarcard': <String>[
        'aadhaar',
        'aadhar',
        'adhar',
        'aadharcard',
        'adharcard',
        'uidai',
      ],
      'aadharcard': <String>[
        'aadhaar',
        'aadhar',
        'adhar',
        'aadhaarcard',
        'adharcard',
        'uidai',
      ],
      'adharcard': <String>[
        'aadhaar',
        'aadhar',
        'adhar',
        'aadhaarcard',
        'aadharcard',
        'uidai',
      ],
      'uidai': <String>[
        'aadhaar',
        'aadhar',
        'adhar',
        'aadhaarcard',
        'aadharcard',
      ],
      'pan': <String>['pancard', 'permanent account number', 'taxid'],
      'pancard': <String>['pan', 'permanent account number', 'taxid'],
      'passport': <String>['passportphoto', 'travel document'],
      'voter': <String>['voterid', 'voter card', 'election card'],
      'voterid': <String>['voter', 'voter card', 'election card'],
      'driving': <String>['drivinglicense', 'drivinglicence', 'dl'],
      'licence': <String>['driving', 'drivinglicence', 'drivinglicense'],
      'license': <String>['driving', 'drivinglicense', 'drivinglicence'],
      'timetable': <String>['schedule', 'examtime', 'datesheet'],
      'schedule': <String>['timetable', 'datesheet'],
      'marksheet': <String>['result', 'marks', 'grade'],
      'result': <String>['marksheet', 'marks', 'grade'],
      'syllabus': <String>['curriculum', 'course'],
      'resume': <String>['cv', 'curriculumvitae'],
      'certificate': <String>['certification'],
      'assignment': <String>['homework', 'task'],
      'question': <String>['questions', 'paper', 'questionpaper'],
      'physics': <String>['physic', 'science'],
      'chemistry': <String>['chemist'],
      'maths': <String>['mathematics', 'math'],
      'marks': <String>['mark', 'score', 'result'],
      'attendance': <String>['present', 'absent', 'presence'],
      'paper': <String>['questionpaper', 'exam'],
      'purana': <String>['old', 'previous'],
      'old': <String>['purana', 'previous'],
    };

    final Set<String> expanded = <String>{...terms};
    for (final String term in terms) {
      expanded.addAll(aliases[term] ?? const <String>[]);
    }
    return expanded.toList();
  }

  static List<String> _importantTerms(String normalizedQuestion) {
    const Set<String> ignored = <String>{
      'a',
      'an',
      'and',
      'are',
      'all',
      'about',
      'can',
      'do',
      'for',
      'from',
      'give',
      'i',
      'in',
      'is',
      'it',
      'me',
      'my',
      'of',
      'on',
      'please',
      'show',
      'tell',
      'the',
      'this',
      'to',
      'what',
      'which',
      'with',
      'document',
      'documents',
      'file',
      'files',
      'hai',
      'hain',
      'ka',
      'ki',
      'ke',
      'ko',
      'mujhe',
      'mera',
      'meri',
      'mere',
      'batao',
      'dikhao',
      'wala',
      'wali',
    };

    return _tokens(normalizedQuestion)
        .where((word) => word.length >= 2 && !ignored.contains(word))
        .toSet()
        .toList();
  }

  static List<String> _tokens(String value) {
    return _normalize(
      value,
    ).split(' ').map(_lightStem).where((word) => word.isNotEmpty).toList();
  }

  static String _lightStem(String word) {
    if (word.length > 5 && word.endsWith('ies')) {
      return '${word.substring(0, word.length - 3)}y';
    }
    if (word.length > 5 && word.endsWith('ing')) {
      return word.substring(0, word.length - 3);
    }
    if (word.length > 4 && word.endsWith('ed')) {
      return word.substring(0, word.length - 2);
    }
    if (word.length > 4 && word.endsWith('s')) {
      return word.substring(0, word.length - 1);
    }
    return word;
  }

  static int _countOccurrences(String value, String term) {
    if (value.isEmpty || term.isEmpty) return 0;
    int count = 0;
    int start = 0;
    while (count < 20) {
      final int index = value.indexOf(term, start);
      if (index < 0) break;
      count++;
      start = index + term.length;
    }
    return count;
  }

  static bool _isCloseToken(String first, String second) {
    if ((first.length - second.length).abs() > 1) return false;
    if (first.startsWith(second) || second.startsWith(first)) return true;
    return _editDistanceAtMostOne(first, second);
  }

  static bool _editDistanceAtMostOne(String a, String b) {
    if ((a.length - b.length).abs() > 1) return false;
    int i = 0;
    int j = 0;
    int edits = 0;

    while (i < a.length && j < b.length) {
      if (a.codeUnitAt(i) == b.codeUnitAt(j)) {
        i++;
        j++;
        continue;
      }
      edits++;
      if (edits > 1) return false;
      if (a.length > b.length) {
        i++;
      } else if (b.length > a.length) {
        j++;
      } else {
        i++;
        j++;
      }
    }
    if (i < a.length || j < b.length) edits++;
    return edits <= 1;
  }


  static bool _matchesIdentityDocument(
    String combined,
    String normalizedQuestion,
  ) {
    final bool asksAadhaar = _containsAny(normalizedQuestion, const [
      'aadhaar', 'aadhar', 'adhar', 'uidai', 'aadhaarcard', 'aadharcard',
      'adharcard',
    ]);
    final bool asksPan = _containsAny(normalizedQuestion, const [
      'pan', 'pan card', 'pancard', 'permanent account number', 'taxid',
    ]);
    final bool asksPassport = normalizedQuestion.contains('passport');
    final bool asksVoter = _containsAny(normalizedQuestion, const [
      'voter id', 'voter card', 'voterid', 'election card',
    ]);
    final bool asksDriving = _containsAny(normalizedQuestion, const [
      'driving licence', 'driving license', 'drivinglicense',
      'drivinglicence',
    ]);

    if (asksAadhaar && _containsAny(combined, const [
      'aadhaar', 'aadhar', 'adhar', 'uidai',
    ])) return true;
    if (asksPan && _containsAny(combined, const [
      'pan card', 'pancard', 'permanent account number', 'income tax', 'taxid',
    ])) return true;
    if (asksPassport && combined.contains('passport')) return true;
    if (asksVoter && _containsAny(combined, const [
      'voter id', 'voter card', 'election commission',
    ])) return true;
    if (asksDriving && _containsAny(combined, const [
      'driving licence', 'driving license', 'drivinglicence', 'drivinglicense',
    ])) return true;
    return false;
  }

  static String _searchableText(String value) {
    const int maximumSearchCharacters = 30000;

    if (value.length <= maximumSearchCharacters) {
      return value;
    }

    const int headCharacters = 22000;
    const int tailCharacters = maximumSearchCharacters - headCharacters;
    return '${value.substring(0, headCharacters)}\n${value.substring(value.length - tailCharacters)}';
  }

  static String _fileNameWithoutExtension(String value) {
    final int dot = value.lastIndexOf('.');
    return dot <= 0 ? value : value.substring(0, dot);
  }

  static bool _containsAny(String value, List<String> phrases) {
    return phrases.any(value.contains);
  }

  static String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[_\-.]+'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9\u0900-\u097f\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
