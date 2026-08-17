enum ConnectionType { usb, tcpip, unknown }

class DeviceInfo {
  const DeviceInfo({
    required this.id,
    required this.name,
    required this.connection,
    this.battery,
    this.model,
    this.isTablet = false,
    this.details,
  });

  final String id;
  final String name;
  final ConnectionType connection;
  final int? battery;
  final String? model;
  final bool isTablet;
  final DeviceDetails? details;

  String get shortId {
    if (id.length <= 10) return id;
    return '${id.substring(0, 8)}...';
  }

  String get connectionLabel {
    switch (connection) {
      case ConnectionType.usb:
        return 'USB';
      case ConnectionType.tcpip:
        return '无线';
      case ConnectionType.unknown:
        return '已连接';
    }
  }

  DeviceInfo copyWith({
    String? id,
    String? name,
    ConnectionType? connection,
    int? battery,
    String? model,
    bool? isTablet,
    DeviceDetails? details,
  }) {
    return DeviceInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      connection: connection ?? this.connection,
      battery: battery ?? this.battery,
      model: model ?? this.model,
      isTablet: isTablet ?? this.isTablet,
      details: details ?? this.details,
    );
  }
}

/// Rich device properties loaded on demand for the details dialog.
class DeviceDetails {
  const DeviceDetails({
    this.brand,
    this.manufacturer,
    this.model,
    this.device,
    this.marketName,
    this.androidVersion,
    this.sdkInt,
    this.securityPatch,
    this.buildId,
    this.fingerprint,
    this.abi,
    this.abis,
    this.serialNo,
    this.hardware,
    this.board,
    this.screenSize,
    this.screenDensity,
    this.batteryLevel,
    this.batteryStatus,
    this.batteryHealth,
    this.batteryTempC,
    this.batteryVoltageMv,
    this.acPowered,
    this.usbPowered,
    this.wirelessPowered,
    this.ipAddress,
    this.wifiSsid,
    this.locale,
    this.timezone,
    this.uptime,
    this.androidId,
  });

  final String? brand;
  final String? manufacturer;
  final String? model;
  final String? device;
  final String? marketName;
  final String? androidVersion;
  final String? sdkInt;
  final String? securityPatch;
  final String? buildId;
  final String? fingerprint;
  final String? abi;
  final String? abis;
  final String? serialNo;
  final String? hardware;
  final String? board;
  final String? screenSize;
  final String? screenDensity;
  final int? batteryLevel;
  final String? batteryStatus;
  final String? batteryHealth;
  final double? batteryTempC;
  final int? batteryVoltageMv;
  final bool? acPowered;
  final bool? usbPowered;
  final bool? wirelessPowered;
  final String? ipAddress;
  final String? wifiSsid;
  final String? locale;
  final String? timezone;
  final String? uptime;
  final String? androidId;

  String get displayTitle {
    final parts = [
      if (brand != null && brand!.isNotEmpty) brand,
      if (model != null && model!.isNotEmpty) model,
    ];
    if (parts.isEmpty) return marketName ?? device ?? '设备';
    return parts.join(' ');
  }
}
