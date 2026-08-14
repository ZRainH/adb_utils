enum ConnectionType { usb, tcpip, unknown }

class DeviceInfo {
  const DeviceInfo({
    required this.id,
    required this.name,
    required this.connection,
    this.battery,
    this.model,
    this.isTablet = false,
  });

  final String id;
  final String name;
  final ConnectionType connection;
  final int? battery;
  final String? model;
  final bool isTablet;

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
}
