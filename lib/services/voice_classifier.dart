enum VoiceInputClass { greeting, question, ack, statement }

class VoiceClassResult {
  final VoiceInputClass inputClass;
  final String immediateResponse;
  final String? extractedQuestion;

  const VoiceClassResult({required this.inputClass, required this.immediateResponse, this.extractedQuestion});
}

class VoiceClassifier {
  static final VoiceClassifier _instance = VoiceClassifier._internal();
  factory VoiceClassifier() => _instance;
  VoiceClassifier._internal();

  static const _greetings = [
    'hi',
    'hello',
    'hey',
    'yo',
    'sup',
    'howdy',
    'hiya',
    'good morning',
    'good afternoon',
    'good evening',
    'good night',
    'g\'day',
    '你好',
    '您好',
    '嗨',
    '哈喽',
    '早上好',
    '晚上好',
    'merhaba',
    'selam',
    'günaydın',
    'hallo',
    'guten tag',
    'guten morgen',
    'bonjour',
    'salut',
    'hola',
    'buenos días',
  ];

  static const _acks = [
    'thanks',
    'thank you',
    'thx',
    'ty',
    'ok',
    'okay',
    'sure',
    'alright',
    'got it',
    'understood',
    'noted',
    'fine',
    'cool',
    'nice',
    'great',
    'perfect',
    'excellent',
    'awesome',
    'wonderful',
    'brilliant',
    'yes',
    'yeah',
    'yep',
    'yup',
    'no',
    'nope',
    '谢谢',
    '感谢',
    '好的',
    '明白',
    '知道了',
    '收到',
    '对',
    '是的',
    '不是',
    'teşekkürler',
    'sağol',
    'tamam',
    'anladım',
    'peki',
    'danke',
    'bitte',
    'ja',
    'nein',
    'verstanden',
    'merci',
    'oui',
    'non',
    'gracias',
    'sí',
    'no',
    'vale',
  ];

  static final _questionStarters = RegExp(
    r'^('
    r'who|what|when|where|why|how|which|whose|whom|'
    r'is|are|was|were|do|does|did|can|could|will|would|shall|should|may|might|'
    r'have|has|had|'
    r'为什么|怎么|如何|什么|哪|谁|几|多少|是否|能否|可以|会不会|有没有|'
    r'ne|niçin|nasıl|kim|ne|hangi|'
    r'warum|wie|wer|was|wann|wo|welche|'
    r'pourquoi|comment|qui|que|quand|où|quel|'
    r'por qué|cómo|quién|qué|cuándo|dónde|cuál'
    r')\b',
    caseSensitive: false,
  );

  static final _questionMark = RegExp(r'[?？¿⁇]');

  VoiceClassResult classify(String text) {
    final normalized = text.trim().toLowerCase();
    if (normalized.isEmpty) {
      return const VoiceClassResult(inputClass: VoiceInputClass.statement, immediateResponse: "I'm listening.");
    }

    // Check greetings (exact match or starts-with)
    for (final g in _greetings) {
      if (normalized == g || normalized.startsWith('$g ') || normalized.startsWith('$g,')) {
        return VoiceClassResult(inputClass: VoiceInputClass.greeting, immediateResponse: _greetingResponse());
      }
    }

    // Check acknowledgments
    for (final a in _acks) {
      if (normalized == a || normalized.startsWith('$a ') || normalized.startsWith('$a,')) {
        return VoiceClassResult(inputClass: VoiceInputClass.ack, immediateResponse: _ackResponse());
      }
    }

    // Check questions
    final hasQuestionMark = _questionMark.hasMatch(normalized);
    final startsWithQuestionWord = _questionStarters.hasMatch(normalized);

    if (hasQuestionMark || startsWithQuestionWord) {
      final questionText = text.trim();
      return VoiceClassResult(
        inputClass: VoiceInputClass.question,
        immediateResponse: _questionResponse(questionText),
        extractedQuestion: questionText,
      );
    }

    // Default: statement
    return VoiceClassResult(inputClass: VoiceInputClass.statement, immediateResponse: _statementResponse());
  }

  String _greetingResponse() {
    final responses = [
      "Hey! What can I do for you?",
      "Hi there! How can I help?",
      "Hello! What would you like to know?",
      "Hey! What's on your mind?",
    ];
    return responses[DateTime.now().millisecond % responses.length];
  }

  String _ackResponse() {
    final responses = ["Sure, anything else?", "Got it. Let me know if you need more.", "Alright, I'm here if you need me.", "No problem."];
    return responses[DateTime.now().millisecond % responses.length];
  }

  String _questionResponse(String question) {
    // Truncate long questions for speech
    final short = question.length > 80 ? '${question.substring(0, 80)}...' : question;
    return "You're asking: \"$short\". Let me look into that.";
  }

  String _statementResponse() {
    final responses = ["Got it, processing that now.", "On it, one moment.", "Let me work on that.", "Processing, give me a second."];
    return responses[DateTime.now().millisecond % responses.length];
  }
}
