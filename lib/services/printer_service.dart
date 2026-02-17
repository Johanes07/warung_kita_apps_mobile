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

  /// Print receipt with multi-unit support
  Future<bool> printReceipt({
    required int transactionId,
    required int dailyNumber,
    required List<Map<String, dynamic>> cart,
    required int totalAmount,
    required String paymentMethod,
    int cashReceived = 0,
    int changeAmount = 0,
  }) async {
    if (!connected || selectedDevice == null) {
      return false;
    }

    try {
      // Header
      printer.printNewLine();
      printer.printCustom("TOKO RIZKI", 3, 1);
      printer.printCustom("Jl. Contoh No. 123", 1, 1);
      printer.printCustom("Telp: 08123456789", 1, 1);
      printer.printCustom("================================", 1, 1);

      // Transaction Info
      final now = DateTime.now();
      printer.printCustom("No: #$dailyNumber", 1, 0);
      printer.printCustom(
        "${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}",
        1,
        0,
      );
      printer.printCustom("================================", 1, 1);

      // Items
      for (var item in cart) {
        final qty = item['qty'] is int
            ? (item['qty'] as int).toDouble()
            : item['qty'] as double;
        final qtyStr = qty == qty.toInt()
            ? qty.toInt().toString()
            : qty.toString().replaceAll('.', ',');

        printer.printCustom(item['name'], 1, 0);

        final price = (item['price'] as int).toDouble();
        final subtotal = (price * qty).round();

        printer.printCustom(
          "$qtyStr ${item['unit']} x Rp ${_formatNumber(price.toInt())}",
          1,
          0,
        );
        printer.printCustom("Subtotal: Rp ${_formatNumber(subtotal)}", 1, 2);
      }

      printer.printCustom("================================", 1, 1);

      // Total
      printer.printCustom("TOTAL: Rp ${_formatNumber(totalAmount)}", 2, 1);

      // Payment Info
      printer.printCustom("--------------------------------", 1, 1);
      printer.printCustom("Metode: ${paymentMethod.toUpperCase()}", 1, 0);

      if (paymentMethod == 'cash') {
        printer.printCustom("Tunai: Rp ${_formatNumber(cashReceived)}", 1, 0);
        printer.printCustom("Kembali: Rp ${_formatNumber(changeAmount)}", 1, 0);
      }

      printer.printCustom("================================", 1, 1);
      printer.printCustom("Terima Kasih", 2, 1);
      printer.printCustom("Selamat Berbelanja Kembali", 1, 1);
      printer.printNewLine();
      printer.printNewLine();
      printer.printNewLine();

      return true;
    } catch (e) {
      debugPrint("Error print receipt: $e");
      return false;
    }
  }

  String _formatNumber(int number) {
    return number.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    );
  }
}
