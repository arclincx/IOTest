import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Sesuaikan 'nama_proyek_anda' dengan nama package di pubspec.yaml Anda
import 'package:iot_app/main.dart'; 

void main() {
  testWidgets('Uji navigasi BottomNavigationBar pada Home', (WidgetTester tester) async {
    // 1. Build widget Home di dalam MaterialApp
    await tester.pumpWidget(const MaterialApp(
      home: Home(),
    ));

    // 2. Verifikasi AppBar utama muncul
    expect(find.text('Mobile IoT Lab - Kelompok 4'), findsOneWidget);

    // 3. Verifikasi halaman awal yang aktif adalah BLE Page
    // Mencari teks 'BLE Controller' yang ada di ble_page.dart
    expect(find.text('BLE Controller'), findsOneWidget);

    // 4. Cari ikon MQTT di BottomNavigationBar
    final mqttTab = find.byIcon(Icons.cloud);
    expect(mqttTab, findsOneWidget);

    // 5. Tap ikon MQTT dan tunggu animasi transisi selesai
    await tester.tap(mqttTab);
    await tester.pumpAndSettle();

    // 6. Verifikasi halaman berubah ke MQTT Page
    // Mencari teks 'MQTT Controller' yang ada di mqtt_page.dart
    expect(find.text('MQTT Controller'), findsOneWidget);
    
    // (Opsional) Jika Anda menggunakan tab PWM, Anda bisa menambahkan pengujiannya:
    // final pwmTab = find.byIcon(Icons.lightbulb);
    // await tester.tap(pwmTab);
    // await tester.pumpAndSettle();
    // expect(find.text('Intensitas LED: 0%'), findsOneWidget); // Sesuaikan dengan teks di PwmPage
  });
}