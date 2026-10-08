class LocalAnswerResult {
  final String answer;
  final bool foundDirectAnswer;
  final double confidence;

  const LocalAnswerResult({
    required this.answer,
    required this.foundDirectAnswer,
    required this.confidence,
  });
}

class LocalAnswerService {
  static LocalAnswerResult generateAnswer({
    required String question,
    required List<String> relevantTexts,
  }) {
    final String normalizedQuestion = _normalize(question);

    final String combinedText = relevantTexts
        .where((text) => text.trim().isNotEmpty)
        .join('\n')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (combinedText.isEmpty) {
      return const LocalAnswerResult(
        answer:
            'I searched your knowledge base but could not find readable information related to this question.',
        foundDirectAnswer: false,
        confidence: 0,
      );
    }

    final LocalAnswerResult? directAnswer = _findDirectAnswer(
      question: normalizedQuestion,
      text: combinedText,
    );

    if (directAnswer != null) {
      return directAnswer;
    }

    final String bestSentence = _findBestSentence(
      question: normalizedQuestion,
      text: combinedText,
    );

    if (bestSentence.isNotEmpty) {
      return LocalAnswerResult(
        answer: bestSentence,
        foundDirectAnswer: true,
        confidence: 0.62,
      );
    }

    return LocalAnswerResult(
      answer:
          'I found related information in your documents:\n\n${_shorten(combinedText, 450)}',
      foundDirectAnswer: false,
      confidence: 0.35,
    );
  }

  static LocalAnswerResult? _findDirectAnswer({
    required String question,
    required String text,
  }) {
    if (_containsAny(question, [
      'stipend',
      'salary',
      'payment',
      'pay',
      'amount',
      'kitne paise',
      'kitna paisa',
      'मानधन',
      'वेतन',
      'पगार',
    ])) {
      final String? amount = _firstMatch(
        text,
        RegExp(
          r'(?:₹|rs\.?|inr)\s*[\d,]+(?:\.\d{1,2})?|[\d,]+\s*(?:rupees| रुपये|रुपये)',
          caseSensitive: false,
        ),
      );

      if (amount != null) {
        return LocalAnswerResult(
          answer: 'The mentioned amount is $amount.',
          foundDirectAnswer: true,
          confidence: 0.92,
        );
      }
    }

    if (_containsAny(question, [
      'date',
      'joining date',
      'start date',
      'kab',
      'when',
      'तारीख',
      'दिनांक',
      'कधी',
    ])) {
      final String? date = _firstDate(text);

      if (date != null) {
        return LocalAnswerResult(
          answer: 'The relevant date mentioned is $date.',
          foundDirectAnswer: true,
          confidence: 0.84,
        );
      }
    }

    if (_containsAny(question, [
      'cgpa',
      'sgpa',
      'percentage',
      'percent',
      'प्रतिशत',
      'टक्के',
    ])) {
      final String? academicValue = _firstMatch(
        text,
        RegExp(
          r'(?:CGPA|SGPA|GPA|Percentage|Percent)\s*[:=-]?\s*(\d{1,3}(?:\.\d{1,2})?\s*%?)',
          caseSensitive: false,
        ),
        returnGroup: 1,
      );

      if (academicValue != null) {
        return LocalAnswerResult(
          answer: 'The mentioned academic score is $academicValue.',
          foundDirectAnswer: true,
          confidence: 0.94,
        );
      }
    }

    if (_containsAny(question, ['email', 'email id', 'mail', 'ईमेल'])) {
      final String? email = _firstMatch(
        text,
        RegExp(r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}', caseSensitive: false),
      );

      if (email != null) {
        return LocalAnswerResult(
          answer: 'The email address mentioned is $email.',
          foundDirectAnswer: true,
          confidence: 0.98,
        );
      }
    }

    if (_containsAny(question, [
      'phone',
      'mobile',
      'contact number',
      'फोन',
      'मोबाइल',
      'संपर्क',
    ])) {
      final String? phone = _firstMatch(
        text,
        RegExp(r'(?:\+91[\s-]?)?[6-9]\d{9}'),
      );

      if (phone != null) {
        return LocalAnswerResult(
          answer: 'The contact number mentioned is $phone.',
          foundDirectAnswer: true,
          confidence: 0.94,
        );
      }
    }

    if (_containsAny(question, ['aadhaar', 'aadhar', 'आधार'])) {
      final String? aadhaar = _firstMatch(
        text,
        RegExp(r'\b\d{4}\s?\d{4}\s?\d{4}\b'),
      );

      if (aadhaar != null) {
        return LocalAnswerResult(
          answer: 'The Aadhaar number found is ${_maskAadhaar(aadhaar)}.',
          foundDirectAnswer: true,
          confidence: 0.96,
        );
      }
    }

    if (_containsAny(question, ['pan number', 'pan card', 'पैन'])) {
      final String? pan = _firstMatch(
        text,
        RegExp(r'\b[A-Z]{5}[0-9]{4}[A-Z]\b', caseSensitive: false),
      );

      if (pan != null) {
        return LocalAnswerResult(
          answer: 'The PAN number found is ${_maskPan(pan)}.',
          foundDirectAnswer: true,
          confidence: 0.96,
        );
      }
    }

    if (_containsAny(question, [
      'roll number',
      'roll no',
      'seat number',
      'रोल नंबर',
      'आसन क्रमांक',
    ])) {
      final String? rollNumber = _firstMatch(
        text,
        RegExp(
          r'(?:roll\s*(?:number|no\.?)|seat\s*(?:number|no\.?))\s*[:=-]?\s*([A-Z0-9/-]{2,20})',
          caseSensitive: false,
        ),
        returnGroup: 1,
      );

      if (rollNumber != null) {
        return LocalAnswerResult(
          answer: 'The roll/seat number mentioned is $rollNumber.',
          foundDirectAnswer: true,
          confidence: 0.9,
        );
      }
    }

    return null;
  }

  static String _findBestSentence({
    required String question,
    required String text,
  }) {
    final Set<String> questionWords = _importantWords(question);

    if (questionWords.isEmpty) {
      return '';
    }

    final List<String> sentences = text
        .split(RegExp(r'(?<=[.!?।])\s+|\n+'))
        .map((sentence) => sentence.trim())
        .where((sentence) => sentence.length >= 15)
        .toList();

    double bestScore = 0;
    String bestSentence = '';

    for (final String sentence in sentences) {
      final Set<String> sentenceWords = _importantWords(_normalize(sentence));

      int matches = 0;

      for (final String word in questionWords) {
        if (sentenceWords.contains(word)) {
          matches++;
        }
      }

      final double score = matches / questionWords.length;

      if (score > bestScore) {
        bestScore = score;
        bestSentence = sentence;
      }
    }

    if (bestScore < 0.18) {
      return '';
    }

    return _shorten(bestSentence, 420);
  }

  static Set<String> _importantWords(String value) {
    const Set<String> ignoredWords = {
      'the',
      'is',
      'are',
      'was',
      'were',
      'what',
      'when',
      'where',
      'which',
      'who',
      'how',
      'my',
      'me',
      'mera',
      'meri',
      'mere',
      'mujhe',
      'hai',
      'ka',
      'ki',
      'ke',
      'kya',
      'batao',
      'bata',
      'please',
      'about',
      'document',
      'documents',
    };

    return value
        .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
        .map((word) => word.trim())
        .where((word) => word.length > 2)
        .where((word) => !ignoredWords.contains(word))
        .toSet();
  }

  static bool _containsAny(String question, List<String> keywords) {
    for (final String keyword in keywords) {
      if (question.contains(_normalize(keyword))) {
        return true;
      }
    }

    return false;
  }

  static String? _firstDate(String text) {
    final List<RegExp> patterns = [
      RegExp(r'\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b', caseSensitive: false),
      RegExp(
        r'\b\d{1,2}\s+(?:january|february|march|april|may|june|july|august|september|october|november|december)\s+\d{4}\b',
        caseSensitive: false,
      ),
      RegExp(
        r'\b(?:january|february|march|april|may|june|july|august|september|october|november|december)\s+\d{1,2},?\s+\d{4}\b',
        caseSensitive: false,
      ),
    ];

    for (final RegExp pattern in patterns) {
      final RegExpMatch? match = pattern.firstMatch(text);

      if (match != null) {
        return match.group(0);
      }
    }

    return null;
  }

  static String? _firstMatch(
    String text,
    RegExp pattern, {
    int returnGroup = 0,
  }) {
    final RegExpMatch? match = pattern.firstMatch(text);

    if (match == null) {
      return null;
    }

    return match.group(returnGroup)?.trim();
  }

  static String _maskAadhaar(String value) {
    final String digits = value.replaceAll(RegExp(r'\D'), '');

    if (digits.length != 12) {
      return value;
    }

    return 'XXXX XXXX ${digits.substring(8)}';
  }

  static String _maskPan(String value) {
    final String pan = value.toUpperCase();

    if (pan.length != 10) {
      return value;
    }

    return '${pan.substring(0, 2)}***${pan.substring(5, 9)}*';
  }

  static String _shorten(String value, int limit) {
    final String cleaned = value.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (cleaned.length <= limit) {
      return cleaned;
    }

    return '${cleaned.substring(0, limit)}...';
  }

  static String _normalize(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
