import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('window')
external JSObject get _window;

@JS('SpeechSynthesisUtterance')
extension type _SpeechSynthesisUtterance._(JSObject _) implements JSObject {
  external factory _SpeechSynthesisUtterance(String text);
  external set lang(String value);
  external set rate(num value);
  external set onend(JSFunction? value);
  external set onerror(JSFunction? value);
}

Future<bool> speakWebLatinTts({
  required String text,
  required double rate,
  required void Function() onComplete,
}) async {
  try {
    final synth = _window.getProperty<JSObject?>('speechSynthesis'.toJS);
    if (synth == null) return false;

    synth.callMethod('cancel'.toJS);

    final utterance = _SpeechSynthesisUtterance(text)
      ..lang = 'id-ID'
      ..rate = rate;

    var completed = false;
    void finish() {
      if (completed) return;
      completed = true;
      onComplete();
    }

    utterance.onend = ((JSAny? _) => finish()).toJS;
    utterance.onerror = ((JSAny? _) => finish()).toJS;

    synth.callMethod('speak'.toJS, utterance);
    return true;
  } catch (_) {
    return false;
  }
}

void stopWebLatinTts() {
  try {
    final synth = _window.getProperty<JSObject?>('speechSynthesis'.toJS);
    synth?.callMethod('cancel'.toJS);
  } catch (_) {}
}
