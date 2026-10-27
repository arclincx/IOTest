import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

const kelompok = 'kel4';
const host = 'broker.emqx.io';

const tSensor = 'polnes/oit/$kelompok/sensor';
const tLed = 'polnes/oit/$kelompok/led';
const tLedState = 'polnes/oit/$kelompok/led/state';
const tStatus = 'polnes/oit/$kelompok/status';

class MqttPage extends StatefulWidget {
  const MqttPage({super.key});

  @override
  State<MqttPage> createState() => _MqttPageState();
}

class _MqttPageState extends State<MqttPage> {
  MqttServerClient? _client;
  StreamSubscription? _subscription;

  bool _connected = false;
  bool _connecting = false;
  bool _ledOn = false;
  double _pwmValue = 0; // Skala PWM 0-100
  String _suhu = '-', _hum = '-', _device = 'tidak diketahui';
  String _status = 'Belum terhubung';

  String _latMqtt = '-';
  bool _measuring = false;
  Completer<void>? _waiting;
  String _expect = '';

  Future<void> _connect() async {
    final id = 'flutter-$kelompok-${DateTime.now().millisecondsSinceEpoch}';
    final c = MqttServerClient(host, id);
    c.port = 1883;
    c.keepAlivePeriod = 30;
    c.logging(on: false);
    c.onDisconnected = _onDisconnected;

    c.autoReconnect = true;
    c.resubscribeOnAutoReconnect = true;
    
    c.onAutoReconnect = () {
      if (mounted) {
        setState(() {
          _status = 'Koneksi terputus! Menyambung kembali...';
        });
      }
    };
    
    c.onAutoReconnected = () {
      if (mounted) {
        setState(() {
          _status = 'Terhubung kembali ke $host';
        });
      }
    };

    final connMessage = MqttConnectMessage()
        .withClientIdentifier(id)
        .withWillTopic(tStatus)
        .withWillMessage('offline')
        .withWillQos(MqttQos.atLeastOnce)
        .startClean();
        
    c.connectionMessage = connMessage;

    setState(() {
      _connecting = true;
      _status = 'Menghubungkan...';
    });

    try {
      await c.connect();
    } catch (e) {
      c.disconnect();
      setState(() {
        _connecting = false;
        _status = 'Gagal: $e';
      });
      return;
    }

    if (c.connectionStatus?.state != MqttConnectionState.connected) {
      c.disconnect();
      setState(() {
        _connecting = false;
        _status = 'Gagal: ${c.connectionStatus}';
      });
      return;
    }

    _subscription?.cancel();
    _subscription = c.updates!.listen(_onMessage);

    c.subscribe(tSensor, MqttQos.atMostOnce);
    c.subscribe(tLedState, MqttQos.atLeastOnce);
    c.subscribe(tStatus, MqttQos.atLeastOnce);

    setState(() {
      _client = c;
      _connected = true;
      _connecting = false;
      _status = 'Terhubung ke $host';
    });
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> events) {
    if (!mounted) return;

    for (final e in events) {
      final msg = e.payload as MqttPublishMessage;
      final text =
          MqttPublishPayload.bytesToStringAsString(msg.payload.message).trim();
      final topic = e.topic;

      if (topic == tLedState) {
        final w = _waiting;
        if (w != null && !w.isCompleted && text == _expect) {
          w.complete();
        }
      }

      setState(() {
        if (topic == tSensor) {
          try {
            final j = jsonDecode(text);
            _suhu = j['suhu'].toString();
            _hum = j['hum'].toString();
          } catch (_) {}
        } else if (topic == tLedState) {
          if (text == 'ON') {
            _ledOn = true;
            _pwmValue = 100;
          } else if (text == 'OFF') {
            _ledOn = false;
            _pwmValue = 0;
          } else {
            final parsed = double.tryParse(text);
            if (parsed != null) {
              _pwmValue = parsed;
              _ledOn = _pwmValue > 0;
            }
          }
        } else if (topic == tStatus) {
          _device = text;
        }
      });
    }
  }

  void _onDisconnected() {
    if (!mounted) return;
    _subscription?.cancel();
    _subscription = null;

    setState(() {
      _connected = false;
      _client = null;
      _device = 'tidak diketahui';
      _status = 'Terputus dari broker';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Peringatan: Koneksi MQTT terputus atau perangkat offline!'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _publish(String topic, String text) {
    final b = MqttClientPayloadBuilder()..addString(text);
    _client?.publishMessage(topic, MqttQos.atLeastOnce, b.payload!);
  }

  void _setPwm(double val) {
    setState(() {
      _pwmValue = val;
      _ledOn = val > 0;
    });
    _publish(tLed, val.toInt().toString());
  }

  Future<void> _measureLatency() async {
    if (!_connected || _measuring) return;
    setState(() {
      _measuring = true;
      _latMqtt = 'mengukur...';
    });

    final samples = <int>[];
    for (var i = 0; i < 10; i++) {
      if (!_connected) break;
      final cmd = i.isEven ? '100' : '0';
      _expect = cmd;
      _waiting = Completer<void>();
      final sw = Stopwatch()..start();
      _publish(tLed, cmd);
      try {
        await _waiting!.future.timeout(const Duration(seconds: 3));
        sw.stop();
        samples.add(sw.elapsedMilliseconds);
      } on TimeoutException {}
      await Future.delayed(const Duration(milliseconds: 500));
    }
    _waiting = null;

    if (!mounted) return;
    setState(() {
      _measuring = false;
      if (samples.isEmpty) {
        _latMqtt = 'tidak ada respons';
      } else {
        final avg = samples.reduce((a, b) => a + b) / samples.length;
        _latMqtt = 'rata-rata ${avg.toStringAsFixed(0)} ms '
            '(min ${samples.reduce(min)}, maks ${samples.reduce(max)}, '
            '${samples.length}/10 sampel)';
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _client?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('MQTT Controller',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(_status),
          const SizedBox(height: 12),
          if (!_connected)
            ElevatedButton(
              onPressed: _connecting ? null : _connect,
              child: Text(_connecting ? 'Menghubungkan...' : 'Hubungkan'),
            )
          else ...[
            Text('Perangkat: $_device'),
            SwitchListTile(
              title: const Text('LED (kondisi nyata dari ESP32)'),
              value: _ledOn,
              onChanged: _measuring
                  ? null
                  : (v) => _setPwm(v ? 100 : 0),
            ),
            const SizedBox(height: 8),
            Text('Kecerahan LED PWM: ${_pwmValue.toInt()}%'),
            Slider(
              value: _pwmValue,
              min: 0,
              max: 100,
              divisions: 100,
              label: '${_pwmValue.round()}%',
              onChanged: _measuring ? null : _setPwm,
            ),
            Card(
              child: ListTile(
                title: Text('Suhu: $_suhu °C'),
                subtitle: Text('Kelembapan: $_hum %'),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _measuring ? null : _measureLatency,
              child: Text(
                  _measuring ? 'Mengukur...' : 'Ukur latensi (10 kali)'),
            ),
            Text('Latensi MQTT: $_latMqtt'),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => _client?.disconnect(),
              child: const Text('Putuskan'),
            ),
          ],
        ],
      ),
    );
  }
}