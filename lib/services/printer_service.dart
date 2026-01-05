import 'package:flutter/material.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';

class PrinterService extends ChangeNotifier {
  static final PrinterService _instance = PrinterService._internal();
  factory PrinterService() => _instance;
  PrinterService._internal();

  final BlueThermalPrinter printer = BlueThermalPrinter.instance;
  List<BluetoothDevice> devices = [];
  BluetoothDevice? selectedDevice;
  bool connected = false;

  /// Inisialisasi printer saat aplikasi dibuka
  Future<void> initPrinter() async {
    try {
      devices = await printer.getBondedDevices();
      notifyListeners();

      // Listen untuk perubahan status koneksi
      printer.onStateChanged().listen((state) {
        final wasConnected = connected;
        connected = state == BlueThermalPrinter.CONNECTED;

        if (!connected) {
          selectedDevice = null;
        }

        // ✅ Notify hanya jika ada perubahan status
        if (wasConnected != connected) {
          notifyListeners();
        }
      });
    } catch (e) {
      debugPrint("Error init printer: $e");
    }
  }

  /// Koneksi ke printer
  Future<bool> connectPrinter(BluetoothDevice device) async {
    try {
      // Jika sudah terkoneksi ke printer lain, disconnect dulu
      if (connected &&
          selectedDevice != null &&
          selectedDevice!.name != device.name) {
        await printer.disconnect();
      }

      await printer.connect(device);
      selectedDevice = device;
      connected = true;
      notifyListeners(); // ✅ Notify setelah koneksi berhasil
      return true;
    } catch (e) {
      debugPrint("Error connect printer: $e");
      connected = false;
      notifyListeners();
      return false;
    }
  }

  /// Disconnect printer
  Future<void> disconnectPrinter() async {
    try {
      await printer.disconnect();
      connected = false;
      selectedDevice = null;
      notifyListeners(); // ✅ Notify setelah disconnect
    } catch (e) {
      debugPrint("Error disconnect printer: $e");
    }
  }

  /// Test print
  Future<bool> testPrint() async {
    if (!connected || selectedDevice == null) {
      return false;
    }

    try {
      printer.printNewLine();
      printer.printCustom("=== TEST PRINT ===", 3, 1);
      printer.printCustom("Printer OK!", 2, 1);
      printer.printNewLine();
      return true;
    } catch (e) {
      debugPrint("Error test print: $e");
      return false;
    }
  }
}
