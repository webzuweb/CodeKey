import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart' as reactive;
import 'package:permission_handler/permission_handler.dart';

import 'job_protocol.dart';
import 'models.dart';

class CodeKeyBleService {
  CodeKeyBleService({reactive.FlutterReactiveBle? ble})
      : _ble = ble ?? reactive.FlutterReactiveBle();

  static final _serviceUuid = reactive.Uuid.parse('6e88f3a0-7a2b-4f6e-b5ab-318e3d7b0001');
  static final _infoUuid = reactive.Uuid.parse('6e88f3a0-7a2b-4f6e-b5ab-318e3d7b0002');
  static final _configUuid = reactive.Uuid.parse('6e88f3a0-7a2b-4f6e-b5ab-318e3d7b0003');
  static final _controlUuid = reactive.Uuid.parse('6e88f3a0-7a2b-4f6e-b5ab-318e3d7b0004');
  static final _dataUuid = reactive.Uuid.parse('6e88f3a0-7a2b-4f6e-b5ab-318e3d7b0005');
  static final _statusUuid = reactive.Uuid.parse('6e88f3a0-7a2b-4f6e-b5ab-318e3d7b0006');

  final reactive.FlutterReactiveBle _ble;
  final _statusController = StreamController<DeviceStatus>.broadcast();
  final _eventController = StreamController<Map<String, dynamic>>.broadcast();
  StreamSubscription<reactive.ConnectionStateUpdate>? _connectionSubscription;
  StreamSubscription<List<int>>? _notificationSubscription;
  String _connectedId = '';
  String _connectedName = '';
  DeviceStatus _status = const DeviceStatus();

  reactive.QualifiedCharacteristic? _info;
  reactive.QualifiedCharacteristic? _config;
  reactive.QualifiedCharacteristic? _control;
  reactive.QualifiedCharacteristic? _data;
  reactive.QualifiedCharacteristic? _statusCharacteristic;

  Stream<DeviceStatus> get statusStream => _statusController.stream;
  DeviceStatus get currentStatus => _status;

  Future<bool> requestPermissions() async {
    final result = await <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      // Required only by Android 11 and older; the manifest limits it to API 30.
      Permission.locationWhenInUse,
    ].request();
    final modernBluetoothGranted =
        (result[Permission.bluetoothScan]?.isGranted ?? false) &&
        (result[Permission.bluetoothConnect]?.isGranted ?? false);
    final legacyLocationGranted =
        result[Permission.locationWhenInUse]?.isGranted ?? false;
    // Android 12+ uses BLUETOOTH_SCAN/CONNECT. Android 11 and older use
    // location permission for BLE scanning. The manifest scopes each set to
    // the Android versions where it is applicable.
    return modernBluetoothGranted || legacyLocationGranted;
  }

  Future<List<DiscoveredCodeKey>> scan({Duration duration = const Duration(seconds: 7)}) async {
    if (!await requestPermissions()) throw const BleException('bluetooth_permission_denied');
    final devices = <String, DiscoveredCodeKey>{};
    final subscription = _ble
        .scanForDevices(
          withServices: [_serviceUuid],
          scanMode: reactive.ScanMode.lowLatency,
        )
        .listen((device) {
          final name = device.name.isEmpty ? 'CodeKey' : device.name;
          devices[device.id] = DiscoveredCodeKey(id: device.id, name: name, rssi: device.rssi);
        });
    try {
      await Future<void>.delayed(duration);
    } finally {
      await subscription.cancel();
    }
    final result = devices.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
    return result;
  }

  Future<void> connect({
    required String deviceId,
    required String deviceName,
    required String setupKey,
    required String clientId,
  }) async {
    if (setupKey.trim().length < 16) throw const BleException('setup_key_too_short');
    if (!await requestPermissions()) throw const BleException('bluetooth_permission_denied');
    await disconnect();
    _connectedId = deviceId;
    _connectedName = deviceName;
    _updateStatus(DeviceStatus(
      connectionState: CodeKeyConnectionState.connecting,
      deviceName: deviceName,
    ));

    final connected = Completer<void>();
    _connectionSubscription = _ble
        .connectToAdvertisingDevice(
          id: deviceId,
          withServices: [_serviceUuid],
          prescanDuration: const Duration(seconds: 3),
          connectionTimeout: const Duration(seconds: 12),
        )
        .listen(
          (update) {
            if (update.connectionState == reactive.DeviceConnectionState.connected) {
              if (!connected.isCompleted) connected.complete();
              _updateStatus(_status.copyWith(
                connectionState: CodeKeyConnectionState.connected,
                deviceName: deviceName,
              ));
            } else if (update.connectionState == reactive.DeviceConnectionState.disconnected) {
              if (!connected.isCompleted) {
                connected.completeError(BleException(
                  update.failure?.toString() ?? 'connection_failed',
                ));
              }
              _updateStatus(_status.copyWith(
                connectionState: CodeKeyConnectionState.disconnected,
                message: update.failure?.toString() ?? 'disconnected',
              ));
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!connected.isCompleted) connected.completeError(error, stackTrace);
            _updateStatus(_status.copyWith(
              connectionState: CodeKeyConnectionState.error,
              message: error.toString(),
            ));
          },
        );

    await connected.future.timeout(const Duration(seconds: 16));
    _bindCharacteristics(deviceId);
    try {
      await _ble.requestMtu(deviceId: deviceId, mtu: 247);
    } on Object {
      // The default MTU also works; uploads use conservative chunks.
    }
    await _subscribeStatus();
    final info = await readDeviceInfo();
    final remoteDeviceId = info['deviceId'] as String? ?? '';
    final challenge = info['challenge'] as String? ?? '';
    if (remoteDeviceId.isEmpty || challenge.isEmpty) {
      throw const BleException('missing_device_challenge');
    }
    final message = '$remoteDeviceId:$challenge:$clientId';
    final proof = Hmac(sha256, utf8.encode(setupKey.trim()))
        .convert(utf8.encode(message))
        .toString();

    final authFuture = _waitForEvent(
      (event) => event['event'] == 'auth_ok',
      timeout: const Duration(seconds: 10),
    );
    await _writeControl({
      'cmd': 'auth',
      'clientId': clientId,
      'nonce': challenge,
      'proof': proof,
    });
    await authFuture;
    _updateStatus(_status.copyWith(
      connectionState: CodeKeyConnectionState.authenticated,
      deviceId: remoteDeviceId,
      deviceName: deviceName,
      message: 'ready',
    ));
  }

  void _bindCharacteristics(String deviceId) {
    reactive.QualifiedCharacteristic characteristic(reactive.Uuid uuid) =>
        reactive.QualifiedCharacteristic(
          serviceId: _serviceUuid,
          characteristicId: uuid,
          deviceId: deviceId,
        );
    _info = characteristic(_infoUuid);
    _config = characteristic(_configUuid);
    _control = characteristic(_controlUuid);
    _data = characteristic(_dataUuid);
    _statusCharacteristic = characteristic(_statusUuid);
  }

  Future<void> _subscribeStatus() async {
    await _notificationSubscription?.cancel();
    final characteristic = _statusCharacteristic;
    if (characteristic == null) throw const BleException('status_characteristic_missing');
    _notificationSubscription = _ble.subscribeToCharacteristic(characteristic).listen(
      (bytes) {
        try {
          final decoded = jsonDecode(utf8.decode(bytes));
          if (decoded is! Map) return;
          final event = Map<String, dynamic>.from(decoded);
          _eventController.add(event);
          if (event['event'] == 'job_status') {
            _updateStatus(_status.copyWith(
              jobState: event['state'] as String? ?? _status.jobState,
              completedSteps: (event['completedSteps'] as num?)?.toInt() ?? 0,
              totalSteps: (event['totalSteps'] as num?)?.toInt() ?? 0,
              message: event['error'] as String? ?? event['state'] as String? ?? '',
            ));
          } else if (event['event'] == 'error') {
            _updateStatus(_status.copyWith(message: event['message'] as String? ?? 'device_error'));
          }
        } on FormatException {
          // Ignore malformed notifications and keep the current connection alive.
        }
      },
      onError: (Object error) {
        _updateStatus(_status.copyWith(message: error.toString()));
      },
    );
  }

  Future<Map<String, dynamic>> readDeviceInfo() async {
    final characteristic = _info;
    if (characteristic == null) throw const BleException('not_connected');
    final bytes = await _ble.readCharacteristic(characteristic);
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) throw const BleException('invalid_device_info');
    return Map<String, dynamic>.from(decoded);
  }

  Future<Map<String, dynamic>> readUsbConfig() async {
    final characteristic = _config;
    if (characteristic == null) throw const BleException('not_connected');
    final bytes = await _ble.readCharacteristic(characteristic);
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) throw const BleException('invalid_usb_config');
    return Map<String, dynamic>.from(decoded);
  }

  Future<void> configureUsb(AppSettings settings) async {
    _requireReady();
    final saved = _waitForEvent(
      (event) => event['event'] == 'config_saved',
      timeout: const Duration(seconds: 8),
    );
    await _writeControl({
      'cmd': 'set_config',
      'vid': settings.usbVid.toUpperCase(),
      'pid': settings.usbPid.toUpperCase(),
      'manufacturer': settings.usbManufacturer,
      'product': settings.usbProduct,
      'serial': settings.usbSerial,
    });
    await saved;
    await _writeControl({'cmd': 'reboot'});
  }

  Future<void> uploadAndStart(CompiledJob job, AppSettings settings) async {
    _requireReady();
    final ready = _waitForEvent(
      (event) => event['event'] == 'job_status' && event['state'] == 'ready',
      timeout: const Duration(seconds: 15),
    );
    await _writeControl({
      'cmd': 'begin',
      'jobId': job.id,
      'length': job.bytes.length,
      'crc32': job.crc32,
      'cps': settings.charactersPerSecond,
      'humanized': settings.humanized,
    });

    final dataCharacteristic = _data;
    if (dataCharacteristic == null) throw const BleException('data_characteristic_missing');
    const chunkSize = 160;
    for (var offset = 0; offset < job.bytes.length; offset += chunkSize) {
      final end = min(offset + chunkSize, job.bytes.length);
      // A write response is deliberately used here. Job transmission is not
      // idempotent, so silent packet loss is worse than the small speed cost.
      await _ble.writeCharacteristicWithResponse(
        dataCharacteristic,
        value: job.bytes.sublist(offset, end),
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await _writeControl({'cmd': 'commit'});
    await ready;

    final running = _waitForEvent(
      (event) => event['event'] == 'job_status' && event['state'] == 'running',
      timeout: const Duration(seconds: 8),
    );
    await _writeControl({'cmd': 'start'});
    await running;
  }

  Future<void> pause() => _writeControl({'cmd': 'pause'});
  Future<void> resume() => _writeControl({'cmd': 'resume'});
  Future<void> cancel() => _writeControl({'cmd': 'cancel'});
  Future<void> releaseAll() => _writeControl({'cmd': 'release_all'});

  Future<void> _writeControl(Map<String, Object?> command) async {
    final characteristic = _control;
    if (characteristic == null) throw const BleException('not_connected');
    await _ble.writeCharacteristicWithResponse(
      characteristic,
      value: utf8.encode(jsonEncode(command)),
    );
  }

  Future<Map<String, dynamic>> _waitForEvent(
    bool Function(Map<String, dynamic>) predicate, {
    required Duration timeout,
  }) async {
    final event = await _eventController.stream.firstWhere((item) {
      if (item['event'] == 'error') {
        throw BleException(item['message'] as String? ?? 'device_error');
      }
      return predicate(item);
    }).timeout(timeout);
    return event;
  }

  void _requireReady() {
    if (!_status.isReady) throw const BleException('device_not_authenticated');
  }

  Future<void> disconnect() async {
    await _notificationSubscription?.cancel();
    _notificationSubscription = null;
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _connectedId = '';
    _connectedName = '';
    _info = null;
    _config = null;
    _control = null;
    _data = null;
    _statusCharacteristic = null;
    _updateStatus(const DeviceStatus());
  }

  void _updateStatus(DeviceStatus status) {
    _status = status;
    if (!_statusController.isClosed) _statusController.add(status);
  }

  Future<void> dispose() async {
    await disconnect();
    await _statusController.close();
    await _eventController.close();
  }
}

class BleException implements Exception {
  const BleException(this.message);
  final String message;
  @override
  String toString() => message;
}
