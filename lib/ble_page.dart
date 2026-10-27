import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

const serviceUuid = '12345678-1234-5678-1234-56789abcdef0';
const ledUuid     = '12345678-1234-5678-1234-56789abcdef1';
const sensorUuid  = '12345678-1234-5678-1234-56789abcdef2';

class BlePage extends StatefulWidget {
  const BlePage({super.key});

  @override
  State<BlePage> createState() => _BlePageState();
}

class _BlePageState extends State<BlePage> {
  List<ScanResult> _results = [];
  BluetoothDevice? _device;
  BluetoothCharacteristic? _ledChar;
  StreamSubscription? _scanSub, _notifySub, _connSub;
  bool _scanning = false;
  bool _ledon = false;
  double _pwmValue = 0; // Skala PWM 0-100
  String _suhu = '-', _hum = '-';
  String _status = 'Belum terhubung';
  String _latBle = '-';

  Future<void> _scan() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    final adapter = await FlutterBluePlus.adapterState.first;
    if (adapter != BluetoothAdapterState.on) {
      setState(() => _status = 'Aktifkan Bluetooth terlebih dahulu');
      return;
    }

    setState(() {
      _results = [];
      _scanning = true;
      _status = 'Memindai...';
    });

    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((r) {
      if (mounted) setState(() => _results = r);
    });

    await FlutterBluePlus.startScan(
      withServices: [Guid(serviceUuid)],
      timeout: const Duration(seconds: 6),
    );

    if (mounted) {
      setState(() {
        _scanning = false;
        _status = 'Pemindaian selesai';
      });
    }
  }

  Future<void> _connect(BluetoothDevice d) async {
    await FlutterBluePlus.stopScan();
    try {
      await d.connect(timeout: const Duration(seconds: 10));
    } catch (e) {
      setState(() => _status = 'Gagal terhubung: $e');
      return;
    }

    _connSub = d.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected && mounted) {
        setState(() {
          _status = 'Terputus';
          _device = null;
          _ledChar = null;
        });
      }
    });

    final services = await d.discoverServices();
    for (final s in services) {
      if (s.uuid != Guid(serviceUuid)) continue;
      for (final c in s.characteristics) {
        if (c.uuid == Guid(ledUuid)) _ledChar = c;
        if (c.uuid == Guid(sensorUuid)) {
          await c.setNotifyValue(true);
          _notifySub = c.onValueReceived.listen((v) {
            final p = utf8.decode(v).split(';');
            if (p.length == 2 && mounted) {
              setState(() {
                _suhu = p[0];
                _hum = p[1];
              });
            }
          });
        }
      }
    }

    setState(() {
      _device = d;
      _status = 'Terhubung ke ${d.platformName.isEmpty ? d.remoteId.str : d.platformName}';
    });
  }

  // Pengiriman nilai PWM (0-100) via BLE
  Future<void> _setPwm(double val) async {
    final intValue = val.toInt();
    await _ledChar?.write([intValue]);
    setState(() {
      _pwmValue = val;
      _ledon = intValue > 0;
    });
  }

  Future<void> _setLed(bool on) async {
    await _setPwm(on ? 100 : 0);
  }

  Future<void> _measureLatency() async {
    if (_ledChar == null) return;
    final samples = <int>[];
    for (var i = 0; i < 10; i++) {
      final sw = Stopwatch()..start();
      await _ledChar!.write([i.isEven ? 100 : 0]);
      sw.stop();
      samples.add(sw.elapsedMilliseconds);
      await Future.delayed(const Duration(milliseconds: 500));
    }
    if (!mounted) return;
    final avg = samples.reduce((a, b) => a + b) / samples.length;
    setState(() => _latBle =
        'rata-rata ${avg.toStringAsFixed(0)} ms (min ${samples.reduce(min)}, maks ${samples.reduce(max)})');
  }

  Future<void> _disconnect() async {
    await _device?.disconnect();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _notifySub?.cancel();
    _connSub?.cancel();
    _device?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = _device != null;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('BLE Controller', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(_status),
          const SizedBox(height: 12),
          if (!connected) ...[
            ElevatedButton(
              onPressed: _scanning ? null : _scan,
              child: Text(_scanning ? 'Memindai...' : 'Scan perangkat'),
            ),
            Expanded(
              child: ListView(
                children: _results.map((r) {
                  final name = r.device.platformName.isEmpty
                      ? r.device.remoteId.str
                      : r.device.platformName;
                  return ListTile(
                    title: Text(name),
                    subtitle: Text('RSSI ${r.rssi} dBm'),
                    onTap: () => _connect(r.device),
                  );
                }).toList(),
              ),
            ),
          ] else ...[
            SwitchListTile(
              title: const Text('LED On/Off'),
              value: _ledon,
              onChanged: _setLed,
            ),
            const SizedBox(height: 8),
            Text('Kecerahan LED PWM: ${_pwmValue.toInt()}%'),
            Slider(
              value: _pwmValue,
              min: 0,
              max: 100,
              divisions: 100,
              label: '${_pwmValue.round()}%',
              onChanged: _setPwm,
            ),
            Card(
              child: ListTile(
                title: Text('Suhu: $_suhu °C'),
                subtitle: Text('Kelembapan: $_hum %'),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _measureLatency,
              child: const Text('Ukur latensi (10 kali)'),
            ),
            Text('Latensi BLE: $_latBle'),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _disconnect,
              child: const Text('Putuskan'),
            ),
          ],
        ],
      ),
    );
  }
}