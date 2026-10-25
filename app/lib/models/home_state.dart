/// The whole-home snapshot published by the home server on `thdt/state`.
///
/// Kept as thin typed accessors over the decoded JSON, so a new field on
/// the server never breaks an older app - unknown keys are simply ignored.
class HomeState {
  final Map<String, dynamic> raw;

  const HomeState(this.raw);

  String get simTime => raw['sim_time']?.toString() ?? '--:--';
  String get serverVersion => raw['server']?.toString() ?? '';
  bool get dark => raw['dark'] == true;
  double get outdoorTemp => asDouble(raw['outdoor_temp']);

  Map<String, dynamic> get energy => asMap(raw['energy']);
  Map<String, dynamic> get generator => asMap(energy['generator']);
  Map<String, dynamic> get water => asMap(raw['water']);
  Map<String, dynamic> get security => asMap(raw['security']);
  Map<String, dynamic> get connectivity => asMap(raw['connectivity']);
  Map<String, dynamic> get slm => asMap(raw['slm']);
  Map<String, dynamic> get ahdt => asMap(raw['ahdt']);
  Map<String, dynamic> get esp32 => asMap(raw['esp32']);
  Map<String, dynamic> get audit => asMap(raw['audit']);

  List<Map<String, dynamic>> get rooms => asList(raw['rooms']);
  List<Map<String, dynamic>> get devices => asList(raw['devices']);
  List<Map<String, dynamic>> get twins => asList(raw['twins']);
  List<Map<String, dynamic>> get pending => asList(raw['pending']);
  List<Map<String, dynamic>> get alerts => asList(raw['alerts']);
  List<Map<String, dynamic>> get messages => asList(raw['messages']);
  List<Map<String, dynamic>> get events => asList(raw['events']);
  List<Map<String, dynamic>> get residents => asList(raw['residents']);

  Map<String, dynamic>? device(String id) {
    for (final d in devices) {
      if (d['id'] == id) return d;
    }
    return null;
  }

  Map<String, dynamic>? twin(String code) {
    for (final t in twins) {
      if (t['code'] == code) return t;
    }
    return null;
  }

  List<Map<String, dynamic>> devicesIn(String roomId) =>
      devices.where((d) => d['room'] == roomId && d['kind'] != 'presence').toList();

  String roomName(String? id) {
    for (final r in rooms) {
      if (r['id'] == id) return r['name']?.toString() ?? id ?? '';
    }
    return id ?? '';
  }

  /// The mode every twin shares, or null when they differ.
  String? get commonMode {
    final modes = twins.map((t) => t['mode']).toSet();
    return modes.length == 1 ? modes.first?.toString() : null;
  }

  bool get hasFireAlarm => device('siren')?['on'] == true;

  List<String> get cutCircuits {
    final c = asMap(energy['circuits']);
    return c.entries.where((e) => e.value == false).map((e) => e.key).toList();
  }
}

Map<String, dynamic> asMap(dynamic v) =>
    v is Map ? v.map((k, val) => MapEntry(k.toString(), val)) : <String, dynamic>{};

List<Map<String, dynamic>> asList(dynamic v) =>
    v is List ? v.whereType<Map>().map(asMap).toList() : <Map<String, dynamic>>[];

double asDouble(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
