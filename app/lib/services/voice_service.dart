import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// The three outcomes a spoken phrase can produce. See
/// AGENT_BUILD_SPEC.md section 5.3 item 5 for the exact matching rules.
enum VoiceCommand { lightOn, lightOff, unrecognized }

/// Wraps speech_to_text for the single "hold to speak" button on the home
/// screen. Recognition is on-device; no audio or transcript ever leaves
/// the phone.
class VoiceService {
  final SpeechToText _speech = SpeechToText();
  bool _available = false;
  String _lastWords = '';
  bool _commandDelivered = false;

  bool get isAvailable => _available;
  bool get isListening => _speech.isListening;

  Future<bool> init() async {
    _available = await _speech.initialize(
      onError: (error) => debugPrint('VoiceService: error $error'),
      onStatus: (status) => debugPrint('VoiceService: status $status'),
    );
    return _available;
  }

  /// Starts listening. `onCommand` fires once, with the parsed command -
  /// either as soon as speech_to_text reports a final result, or (if the
  /// button is released first) from stopListening using whatever partial
  /// transcript was captured so far.
  Future<void> startListening({required void Function(VoiceCommand) onCommand}) async {
    if (!_available) return;
    _lastWords = '';
    _commandDelivered = false;
    await _speech.listen(
      onResult: (result) {
        _lastWords = result.recognizedWords;
        if (result.finalResult && !_commandDelivered) {
          _commandDelivered = true;
          onCommand(parseCommand(_lastWords));
        }
      },
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 8),
        pauseFor: const Duration(seconds: 3),
      ),
    );
  }

  /// Called when the user releases the voice button. If a final result
  /// already delivered a command, this is a no-op; otherwise it stops the
  /// microphone and evaluates whatever partial transcript was captured.
  Future<void> stopListening({required void Function(VoiceCommand) onCommand}) async {
    await _speech.stop();
    if (!_commandDelivered) {
      _commandDelivered = true;
      onCommand(parseCommand(_lastWords));
    }
  }

  /// Matches on keywords, not exact phrases, per the spec. The rules, in
  /// plain terms:
  ///  - Any "no" word ("don't", "not", "stop"...) -> unrecognized. Better to
  ///    do nothing than switch the lamp on when the person said not to.
  ///  - Both an "on" and an "off" word in one sentence -> unrecognized,
  ///    because we can't tell which one was meant.
  ///  - An "on" or "off" word plus a light word ("lamp", "bulb"...), or plus
  ///    an action word ("turn", "switch", "put"...) -> that command.
  ///    The lamp is the only device, so "turn on" alone is enough.
  ///  - Anything else                -> unrecognized.
  static VoiceCommand parseCommand(String text) {
    final words = text
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z' ]"), ' ')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toSet();

    const negations = {'not', "don't", 'dont', 'never', 'no', 'stop', 'cancel', 'wait'};
    // Questions such as "is the light on?" are not commands.
    const questions = {'is', 'are', 'was', 'what', 'how', 'why', 'whether'};
    if (words.any(negations.contains) || words.any(questions.contains)) {
      return VoiceCommand.unrecognized;
    }

    const onWords = {'on', 'activate', 'enable', 'start'};
    // "of" is included because speech recognition often hears "turn off"
    // as "turn of". "out" covers "put the light out".
    const offWords = {'off', 'of', 'out', 'disable', 'deactivate'};
    const lightWords = {'light', 'lights', 'lamp', 'lamps', 'bulb', 'bulbs', 'lighting'};
    const actionWords = {'turn', 'switch', 'put', 'power', 'set', 'shut'};

    final hasOn = words.any(onWords.contains);
    final hasOff = words.any(offWords.contains);
    if (hasOn == hasOff) return VoiceCommand.unrecognized;

    final hasLight = words.any(lightWords.contains);
    final hasAction = words.any(actionWords.contains);
    if (!hasLight && !hasAction) return VoiceCommand.unrecognized;

    return hasOn ? VoiceCommand.lightOn : VoiceCommand.lightOff;
  }
}
