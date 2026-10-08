class KeeperCategorySuggestion {
  final String category;
  final String subject;
  final double confidence;
  final List<String> matchedKeywords;

  const KeeperCategorySuggestion({
    required this.category,
    required this.subject,
    required this.confidence,
    required this.matchedKeywords,
  });
}

class KeeperCategoryDetectionService {
  KeeperCategoryDetectionService._();

  static const Map<String, List<String>> _categoryKeywords = {
    'Resume': [
      'resume',
      'curriculum vitae',
      'career objective',
      'work experience',
      'linkedin',
    ],
    'Certificate': [
      'certificate',
      'certify that',
      'completion certificate',
      'participation certificate',
      'awarded to',
    ],
    'Marksheet': [
      'marksheet',
      'mark sheet',
      'statement of marks',
      'grade card',
      'sgpa',
      'cgpa',
      'marks obtained',
    ],
    'Previous Year Paper': [
      'question paper',
      'previous year',
      'semester examination',
      'end semester',
      'mid semester',
      'attempt any',
    ],
    'Assignment': [
      'assignment',
      'submission date',
      'home assignment',
      'tutorial sheet',
    ],
    'Syllabus': [
      'syllabus',
      'course outcomes',
      'teaching scheme',
      'unit i',
      'unit ii',
    ],
    'Lab Manual': [
      'lab manual',
      'experiment no',
      'apparatus',
      'observation table',
      'procedure',
    ],
    'Internship': [
      'internship',
      'offer letter',
      'joining letter',
      'stipend',
      'letter of recommendation',
    ],
    'Project': [
      'project report',
      'project title',
      'problem statement',
      'methodology',
      'expected outcome',
    ],
    'Bill': ['invoice', 'receipt', 'amount due', 'tax invoice', 'total amount'],
    'Notice': ['notice', 'circular', 'announcement', 'hereby informed'],
    'Exam Timetable': [
      'exam timetable',
      'examination timetable',
      'exam schedule',
      'subject code',
      'time table',
    ],
    'Personal Notes': [
      'notes',
      'important points',
      'revision notes',
      'short notes',
    ],
    'Study Material': [
      'chapter',
      'learning objectives',
      'introduction',
      'definition',
      'theory',
    ],
  };

  static const Map<String, List<String>> _subjectKeywords = {
    'Fluid Mechanics': [
      'fluid mechanics',
      'bernoulli',
      'reynolds number',
      'viscosity',
      'laminar flow',
      'turbulent flow',
    ],
    'Strength of Materials': [
      'strength of materials',
      'stress strain',
      'hooke law',
      'bending moment',
      'shear force',
      'flexural equation',
    ],
    'Thermodynamics': [
      'thermodynamics',
      'entropy',
      'enthalpy',
      'first law',
      'second law',
      'heat engine',
    ],
    'Material Science': [
      'material science',
      'bcc',
      'fcc',
      'hcp',
      'crystal structure',
      'dislocation',
    ],
    'Manufacturing': [
      'manufacturing',
      'casting',
      'forging',
      'machining',
      'welding',
    ],
    'Entrepreneurship Development': [
      'entrepreneurship',
      'business plan',
      'startup',
      'market analysis',
      'entrepreneur',
    ],
    'Mathematics': [
      'differentiate',
      'integration',
      'laplace transform',
      'probability',
      'statistics',
      'matrix',
    ],
    'Java Programming': [
      'java',
      'inheritance',
      'polymorphism',
      'interface',
      'exception handling',
    ],
    'Artificial Intelligence': [
      'artificial intelligence',
      'machine learning',
      'deep learning',
      'neural network',
      'prompt engineering',
    ],
    'Mechanical Engineering': [
      'mechanical engineering',
      'machine design',
      'thermal engineering',
      'production engineering',
    ],
  };

  static KeeperCategorySuggestion detect({
    required String fileName,
    required String extractedText,
    String? currentCategory,
  }) {
    final String haystack = _normalize(
      '$fileName ${fileName.replaceAll('_', ' ')} $extractedText',
    );

    String detectedCategory = currentCategory?.trim().isNotEmpty == true
        ? currentCategory!.trim()
        : 'Other';

    double bestCategoryScore = 0;
    final List<String> categoryMatches = [];

    for (final entry in _categoryKeywords.entries) {
      double score = 0;
      final List<String> matches = [];

      for (final keyword in entry.value) {
        final String normalizedKeyword = _normalize(keyword);

        if (haystack.contains(normalizedKeyword)) {
          score += fileName.toLowerCase().contains(normalizedKeyword) ? 3 : 1;
          matches.add(keyword);
        }
      }

      if (score > bestCategoryScore) {
        bestCategoryScore = score;
        detectedCategory = entry.key;
        categoryMatches
          ..clear()
          ..addAll(matches);
      }
    }

    String detectedSubject = '';
    double bestSubjectScore = 0;
    final List<String> subjectMatches = [];

    for (final entry in _subjectKeywords.entries) {
      double score = 0;
      final List<String> matches = [];

      for (final keyword in entry.value) {
        final String normalizedKeyword = _normalize(keyword);

        if (haystack.contains(normalizedKeyword)) {
          score += fileName.toLowerCase().contains(normalizedKeyword) ? 3 : 1;
          matches.add(keyword);
        }
      }

      if (score > bestSubjectScore) {
        bestSubjectScore = score;
        detectedSubject = entry.key;
        subjectMatches
          ..clear()
          ..addAll(matches);
      }
    }

    final double confidence = (bestCategoryScore / 6).clamp(0, 1).toDouble();

    return KeeperCategorySuggestion(
      category: detectedCategory,
      subject: detectedSubject,
      confidence: confidence,
      matchedKeywords: [...categoryMatches, ...subjectMatches],
    );
  }

  static String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
