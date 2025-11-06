import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:warung_kita/db/database_helper.dart';

class CashierScreen extends StatefulWidget {
  const CashierScreen({super.key});

  @override
  State<CashierScreen> createState() => _CashierScreenState();
}

class _CashierScreenState extends State<CashierScreen>
    with WidgetsBindingObserver {
  final dbHelper = DatabaseHelper.instance;
  final formatCurrency =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  List<Map<String, dynamic>> cart = [];
  List<Map<String, dynamic>> products = [];
  List<Map<String, dynamic>> filteredProducts = [];

  final TextEditingController searchController = TextEditingController();
  int totalAmount = 0;
  bool isLoading = false;

  /// Bluetooth printer instance
  final BlueThermalPrinter printer = BlueThermalPrinter.instance;
  List<BluetoothDevice> _devices = [];
  BluetoothDevice? _selectedDevice;
  bool _connected = false;
  bool _reconnectDialogShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadProducts();
    _initPrinter();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Saat kembali ke halaman, cek koneksi printer
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPrinterConnectionOnResume();
    }
  }

  Future<void> _checkPrinterConnectionOnResume() async {
    if (_selectedDevice != null && !_connected && !_reconnectDialogShown) {
      _reconnectDialogShown = true;
      _showReconnectDialog();
    }
  }

  /// Validasi saat keluar halaman
  Future<bool> _onWillPop() async {
    if (_connected && _selectedDevice != null) {
      final result = await _showConfirmationDialog(
        "Putuskan Koneksi Printer?",
        "Anda terhubung dengan ${_selectedDevice!.name}. Apakah ingin memutus koneksi sebelum keluar?",
      );
      if (result) {
        await _disconnectPrinter();
      }
      return result;
    }
    return true;
  }

  Future<void> _loadProducts() async {
    final db = await dbHelper.database;
    final result = await db.query('products', orderBy: 'name ASC');

    setState(() {
      products = result;
      filteredProducts = result;
    });
  }

  void _searchProducts(String query) {
    final filtered = products.where((product) {
      final name = (product['name'] ?? '').toString().toLowerCase();
      final barcode = (product['barcode'] ?? '').toString().toLowerCase();
      return name.contains(query.toLowerCase()) ||
          barcode.contains(query.toLowerCase());
    }).toList();

    setState(() {
      filteredProducts = filtered;
    });
  }

  Future<void> _initPrinter() async {
    try {
      List<BluetoothDevice> devices = await printer.getBondedDevices();
      setState(() {
        _devices = devices;
      });

      printer.onStateChanged().listen((state) {
        setState(() {
          _connected = state == BlueThermalPrinter.CONNECTED;
        });

        if (!_connected && mounted) {
          // Jika printer disconnect saat halaman aktif
          _selectedDevice = null;
          _showReconnectDialog();
        }
      });
    } catch (e) {
      debugPrint("Error init printer: $e");
    }
  }

  Future<void> _connectPrinter(BluetoothDevice device) async {
    if (_connected &&
        _selectedDevice != null &&
        _selectedDevice!.name != device.name) {
      final result = await _showConfirmationDialog(
        "Ganti Printer",
        "Printer saat ini sudah terhubung ke ${_selectedDevice!.name}. Apakah Anda yakin ingin mengganti koneksi ke ${device.name}?",
      );
      if (!result) return;
      await printer.disconnect();
    }

    try {
      await printer.connect(device);
      setState(() {
        _selectedDevice = device;
        _connected = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Terhubung ke printer: ${device.name}")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Gagal menghubungkan printer: $e")),
      );
    }
  }

  Future<void> _disconnectPrinter() async {
    try {
      await printer.disconnect();
      setState(() {
        _connected = false;
        _selectedDevice = null;
      });
    } catch (e) {
      debugPrint("Error disconnect printer: $e");
    }
  }

  /// Pop-up reconnect saat printer terputus
  void _showReconnectDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text("Printer Terputus"),
          content: Text(
            "Printer tidak terhubung.\n\nSilakan pilih printer kembali agar bisa mencetak struk.",
            style: GoogleFonts.poppins(),
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _reconnectDialogShown = false;
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent),
              child: const Text(
                "OK",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Dialog umum
  Future<bool> _showConfirmationDialog(String title, String content) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          content: Text(content, style: GoogleFonts.poppins()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Batal"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Iya"),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  /// Test print
  Future<void> _testPrint() async {
    if (!_connected || _selectedDevice == null) {
      _showReconnectDialog();
      return;
    }

    try {
      printer.printNewLine();
      printer.printCustom("=== TEST PRINT ===", 3, 1);
      printer.printCustom("Printer OK!", 2, 1);
      printer.printNewLine();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Gagal test print: $e")),
      );
    }
  }

  Future<void> _scanBarcode() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CashierBarcodeScannerScreen(),
      ),
    );

    if (result != null && result is String) {
      _addProductToCartByBarcode(result);
    }
  }

  Future<void> _addProductToCartByBarcode(String barcode) async {
    final db = await dbHelper.database;
    final result = await db.query(
      'products',
      where: 'barcode = ?',
      whereArgs: [barcode.trim()],
    );

    if (result.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Produk tidak ditemukan")),
      );
      return;
    }

    final product = result.first;
    _showPriceOptionDialog(product);
  }

  void _showPriceOptionDialog(Map<String, dynamic> product) {
    final qtyController = TextEditingController(text: "1");

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text("Pilih Harga",
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(product['name'], style: GoogleFonts.poppins(fontSize: 16)),
              const SizedBox(height: 12),
              ListTile(
                tileColor: Colors.grey[100],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                title: Text("Harga Eceran",
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  formatCurrency.format(product['price_retail']),
                  style: GoogleFonts.poppins(color: Colors.black87),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _addProductToCart(
                    product,
                    int.tryParse(qtyController.text) ?? 1,
                    product['price_retail'],
                  );
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                tileColor: Colors.grey[100],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                title: Text("Harga Grosir",
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  formatCurrency.format(product['price_wholesale']),
                  style: GoogleFonts.poppins(color: Colors.black87),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _addProductToCart(
                    product,
                    int.tryParse(qtyController.text) ?? 1,
                    product['price_wholesale'],
                  );
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: "Jumlah",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _addProductToCart(Map<String, dynamic> product, int qty, int price) {
    setState(() {
      final index = cart.indexWhere(
        (item) => item['id'] == product['id'] && item['price'] == price,
      );

      if (index >= 0) {
        cart[index]['qty'] += qty;
      } else {
        cart.add({
          'id': product['id'],
          'name': product['name'],
          'price': price,
          'qty': qty,
        });
      }
      _calculateTotal();
    });
  }

  void _calculateTotal() {
    setState(() {
      totalAmount = cart.fold(
        0,
        (sum, item) {
          final price = int.tryParse(item['price'].toString()) ?? 0;
          final qty = int.tryParse(item['qty'].toString()) ?? 0;
          return sum + (price * qty);
        },
      );
    });
  }

  void _updateQty(int index, int delta) {
    setState(() {
      cart[index]['qty'] += delta;
      if (cart[index]['qty'] <= 0) {
        cart.removeAt(index);
      }
      _calculateTotal();
    });
  }

  void _removeItem(int index) {
    setState(() {
      cart.removeAt(index);
      _calculateTotal();
    });
  }

  Future<void> _printReceiptBluetooth(
      int transactionId, List<Map<String, dynamic>> items, int total) async {
    if (!_connected || _selectedDevice == null) {
      _showReconnectDialog();
      return;
    }

    try {
      printer.printNewLine();
      printer.printCustom("WARUNG KITA", 3, 1);
      printer.printCustom("Transaksi #$transactionId", 1, 1);
      printer.printCustom(
          DateFormat('dd MMM yyyy, HH:mm').format(DateTime.now()), 1, 1);
      printer.printNewLine();

      for (var item in items) {
        final name = item['name'];
        final qty = item['qty'];
        final price = item['price'];
        final subtotal = qty * price;

        printer.printLeftRight(name, formatCurrency.format(subtotal), 1);
        printer.printCustom("$qty x ${formatCurrency.format(price)}", 0, 0);
      }

      printer.printNewLine();
      printer.printLeftRight("TOTAL", formatCurrency.format(total), 2);
      printer.printNewLine();
      printer.printCustom("Terima kasih telah berbelanja!", 1, 1);
      printer.printNewLine();
      printer.printNewLine();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error print: $e")),
      );
    }
  }

  Future<void> _checkout() async {
    if (cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Keranjang kosong")),
      );
      return;
    }

    final db = await dbHelper.database;
    setState(() => isLoading = true);

    try {
      int userId = 1;
      int transactionId = 0;

      await db.transaction((txn) async {
        transactionId = await txn.insert('transactions', {
          'user_id': userId,
          'total_amount': totalAmount,
          'created_at': DateTime.now().toIso8601String(),
        });

        for (var item in cart) {
          await txn.insert('transaction_items', {
            'transaction_id': transactionId,
            'product_id': item['id'],
            'quantity': item['qty'],
            'price': item['price'],
          });

          await txn.rawUpdate(
            'UPDATE products SET stock = stock - ? WHERE id = ?',
            [item['qty'], item['id']],
          );
        }
      });

      await _printReceiptBluetooth(transactionId, List.from(cart), totalAmount);

      setState(() {
        cart.clear();
        totalAmount = 0;
      });

      _showTransactionSuccessDialog();
    } catch (e) {
      debugPrint("Error checkout: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Gagal menyimpan transaksi: $e")),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _showTransactionSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Column(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 64),
            const SizedBox(height: 8),
            Text("Transaksi Berhasil",
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold, fontSize: 20)),
          ],
        ),
        content: Text(
          "Struk berhasil dicetak dan transaksi tersimpan.",
          style: GoogleFonts.poppins(),
          textAlign: TextAlign.center,
        ),
        actions: [
          Center(
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              child: const Text("OK", style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: Colors.grey.shade100,
        appBar: AppBar(
          elevation: 0,
          title: Text(
            "Kasir",
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.black),
          ),
          backgroundColor: Colors.transparent,
          actions: [
            PopupMenuButton<BluetoothDevice>(
              icon: Icon(
                Icons.print,
                color: _connected ? Colors.green : Colors.white,
              ),
              tooltip: "Pilih Printer",
              onSelected: (device) => _connectPrinter(device),
              itemBuilder: (context) {
                return _devices
                    .map(
                      (device) => PopupMenuItem(
                        value: device,
                        child: Text(device.name ?? "Unknown"),
                      ),
                    )
                    .toList();
              },
            ),
            IconButton(
              icon: const Icon(Icons.receipt_long, color: Colors.white),
              tooltip: "Test Print",
              onPressed: _testPrint,
            ),
            IconButton(
              icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
              tooltip: "Scan Barcode",
              onPressed: _scanBarcode,
            ),
          ],
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage("assets/images/bgwarung2.jpg"),
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: searchController,
                onChanged: _searchProducts,
                decoration: InputDecoration(
                  hintText: "Cari produk nama / barcode...",
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.grey[100],
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: filteredProducts.isEmpty
                  ? const Center(child: Text("Produk tidak ditemukan"))
                  : GridView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.8,
                      ),
                      itemCount: filteredProducts.length,
                      itemBuilder: (context, index) {
                        final product = filteredProducts[index];
                        return GestureDetector(
                          onTap: () => _showPriceOptionDialog(product),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.blueAccent,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.inventory_2,
                                    color: Colors.white, size: 32),
                                const SizedBox(height: 12),
                                Text(
                                  product['name'],
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  "Ecer: ${formatCurrency.format(product['price_retail'])}",
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12),
                                ),
                                Text(
                                  "Grosir: ${formatCurrency.format(product['price_wholesale'])}",
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12),
                                ),
                                const SizedBox(height: 6),
                                Text("Stok: ${product['stock']}",
                                    style: const TextStyle(
                                        color: Colors.yellowAccent)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: Column(
                children: [
                  if (cart.isNotEmpty)
                    Column(
                      children: [
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: cart.length,
                          itemBuilder: (context, index) {
                            final item = cart[index];
                            return ListTile(
                              title:
                                  Text(item['name'], style: GoogleFonts.poppins()),
                              subtitle: Text(formatCurrency.format(item['price']),
                                  style: GoogleFonts.poppins(fontSize: 12)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle_outline),
                                    onPressed: () => _updateQty(index, -1),
                                  ),
                                  Text(item['qty'].toString(),
                                      style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.bold)),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline),
                                    onPressed: () => _updateQty(index, 1),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete,
                                        color: Colors.red),
                                    onPressed: () => _removeItem(index),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const Divider(),
                      ],
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Total",
                          style: GoogleFonts.poppins(
                              fontSize: 18, fontWeight: FontWeight.w600)),
                      Text(formatCurrency.format(totalAmount),
                          style: GoogleFonts.poppins(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.blueAccent)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      icon: isLoading
                          ? const CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2)
                          : const Icon(Icons.payment),
                      label: Text(
                        isLoading ? "Memproses..." : "Checkout",
                        style: GoogleFonts.poppins(
                            fontSize: 16, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: isLoading ? null : _checkout,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CashierBarcodeScannerScreen extends StatelessWidget {
  const CashierBarcodeScannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Scan Produk"),
        backgroundColor: Colors.blueAccent,
      ),
      body: MobileScanner(
        onDetect: (capture) {
          final barcodes = capture.barcodes;
          if (barcodes.isNotEmpty) {
            final value = barcodes.first.rawValue;
            Navigator.pop(context, value);
          }
        },
      ),
    );
  }
}
