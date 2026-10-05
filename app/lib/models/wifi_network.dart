/// One Wi-Fi network the ESP32 can see, as reported on home/wifi/scans.
class WifiNetwork {
  final String ssid;
  final int rssi;
  final bool secure;

  const WifiNetwork({
    required this.ssid,
    required this.rssi,
    required this.secure,
  });

  factory WifiNetwork.fromJson(Map<String, dynamic> json) {
    return WifiNetwork(
      ssid: json['ssid']?.toString() ?? '',
      rssi: (json['rssi'] as num?)?.toInt() ?? -100,
      secure: json['secure'] as bool? ?? true,
    );
  }

  /// 0-4 bars for the signal icon, from the RSSI in dBm.
  int get bars {
    if (rssi >= -55) return 4;
    if (rssi >= -67) return 3;
    if (rssi >= -75) return 2;
    if (rssi >= -85) return 1;
    return 0;
  }
}
