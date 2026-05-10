import 'dart:async';

import 'package:event_bus/event_bus.dart';

class CodePreviewEvent {
  final String hash;
  final String textContent;
  final Map<String, String> attributes;

  const CodePreviewEvent(this.hash, this.textContent, this.attributes);
}

class ToggleCodePreviewEvent {
  final bool showCodePreview;

  const ToggleCodePreviewEvent(this.showCodePreview);
}

class ShareEvent {
  final bool share;

  const ShareEvent(this.share);
}

class RunFunctionEvent {
  final String name;
  final Map<String, dynamic> arguments;

  const RunFunctionEvent(this.name, this.arguments);
}

class ToolCallResultEvent {
  final String toolName;
  final String result;

  const ToolCallResultEvent(this.toolName, this.result);
}

/// The global [EventBus] object.
EventBus eventBus = EventBus();

Future<void> emit<T>(T data) async {
  eventBus.fire(data);
}

StreamSubscription<T> on<T>(Function(T) callback) {
  StreamSubscription<T> loginSubscription = eventBus.on<T>().listen((data) {
    callback(data);
  });

  return loginSubscription;
}
