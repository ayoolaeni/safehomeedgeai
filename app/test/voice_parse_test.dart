import 'package:flutter_test/flutter_test.dart';
import 'package:safehome_edge_ai/services/voice_service.dart';

void main() {
  group('VoiceService.parseCommand - turn on', () {
    for (final phrase in [
      'turn on the light',
      'turn the light on',
      'lights on',
      'switch the lamp on please',
      'put on the lamp',
      'turn on',
      'turn it on',
      'Turn On The Light!',
    ]) {
      test('"$phrase" -> lightOn', () {
        expect(VoiceService.parseCommand(phrase), VoiceCommand.lightOn);
      });
    }
  });

  group('VoiceService.parseCommand - turn off', () {
    for (final phrase in [
      'turn off the light',
      'turn the lamp off',
      'switch off the lights',
      'put the light out',
      'turn of the light', // speech often hears "off" as "of"
      'shut off the lamp',
      'turn off',
    ]) {
      test('"$phrase" -> lightOff', () {
        expect(VoiceService.parseCommand(phrase), VoiceCommand.lightOff);
      });
    }
  });

  group('VoiceService.parseCommand - must NOT act', () {
    for (final phrase in [
      "don't turn on the light",
      'do not turn off the light',
      'turn the light off not on',
      'turn on the light, no wait off',
      'is the light on',
      'what is the light doing',
      'hello there',
      'on',
      'off',
      '',
    ]) {
      test('"$phrase" -> unrecognized', () {
        expect(VoiceService.parseCommand(phrase), VoiceCommand.unrecognized);
      });
    }
  });
}
