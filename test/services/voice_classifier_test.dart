import 'package:chatmcp/services/voice_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final classifier = VoiceClassifier();

  group('VoiceClassifier.classify — greetings', () {
    test('exact greeting match', () {
      final r = classifier.classify('hi');
      expect(r.inputClass, VoiceInputClass.greeting);
      expect(r.immediateResponse, isNotEmpty);
    });

    test('greeting with trailing text', () {
      final r = classifier.classify('hello there');
      expect(r.inputClass, VoiceInputClass.greeting);
    });

    test('Chinese greeting', () {
      final r = classifier.classify('你好');
      expect(r.inputClass, VoiceInputClass.greeting);
    });

    test('case-insensitive greeting', () {
      final r = classifier.classify('Hello');
      expect(r.inputClass, VoiceInputClass.greeting);
    });

    test('good morning greeting', () {
      final r = classifier.classify('good morning');
      expect(r.inputClass, VoiceInputClass.greeting);
    });
  });

  group('VoiceClassifier.classify — acknowledgments', () {
    test('ok is ack', () {
      final r = classifier.classify('ok');
      expect(r.inputClass, VoiceInputClass.ack);
    });

    test('thanks is ack', () {
      final r = classifier.classify('thanks');
      expect(r.inputClass, VoiceInputClass.ack);
    });

    test('yes is ack', () {
      final r = classifier.classify('yes');
      expect(r.inputClass, VoiceInputClass.ack);
    });

    test('Chinese ack', () {
      final r = classifier.classify('好的');
      expect(r.inputClass, VoiceInputClass.ack);
    });

    test('ack with comma suffix', () {
      final r = classifier.classify('okay, thanks');
      expect(r.inputClass, VoiceInputClass.ack);
    });
  });

  group('VoiceClassifier.classify — questions', () {
    test('question mark triggers question class', () {
      final r = classifier.classify('Is it raining today?');
      expect(r.inputClass, VoiceInputClass.question);
      expect(r.extractedQuestion, isNotNull);
    });

    test('what prefix is a question', () {
      final r = classifier.classify('What time is it');
      expect(r.inputClass, VoiceInputClass.question);
    });

    test('how prefix is a question', () {
      final r = classifier.classify('How do I reset my password');
      expect(r.inputClass, VoiceInputClass.question);
    });

    test('extractedQuestion contains original text', () {
      final r = classifier.classify('What is the weather?');
      expect(r.extractedQuestion, 'What is the weather?');
    });

    test('immediate response references the question', () {
      final r = classifier.classify('Why is the sky blue?');
      expect(r.immediateResponse, contains('Why is the sky blue?'));
    });

    test('long question gets truncated in immediate response', () {
      final longQ = 'What is the meaning of ${'life ' * 20}?';
      final r = classifier.classify(longQ);
      expect(r.immediateResponse.length, lessThan(200));
    });
  });

  group('VoiceClassifier.classify — statements', () {
    test('plain statement', () {
      final r = classifier.classify('Set a reminder for tomorrow');
      expect(r.inputClass, VoiceInputClass.statement);
    });

    test('empty string is statement with fallback response', () {
      final r = classifier.classify('');
      expect(r.inputClass, VoiceInputClass.statement);
      expect(r.immediateResponse, isNotEmpty);
    });

    test('statement has non-empty immediate response', () {
      final r = classifier.classify('Send a message to John');
      expect(r.immediateResponse, isNotEmpty);
    });
  });

  group('VoiceClassifier — greeting vs statement boundary', () {
    test('greeting word embedded in sentence is NOT greeting', () {
      // "hello" is only a greeting when it starts (exact or prefix match)
      final r = classifier.classify('say hello to him');
      // should not be greeting since 'say hello...' doesn't start with 'hello '
      expect(r.inputClass, isNot(VoiceInputClass.greeting));
    });
  });
}
