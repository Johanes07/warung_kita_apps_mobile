import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:warung_kita/db/database_helper.dart';
import 'package:intl/intl.dart';

/// =============================
/// Custom Formatter Rupiah
/// =============================
class CurrencyInputFormatter extends TextInputFormatter {
  final NumberFormat _formatter = NumberFormat.currency(
    locale: 'id_ID',
    symbol: '',
    decimalDigits: 0,
  );

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue.copyWith(text: '');
    }

    // Hanya angka
    String digitsOnly = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    // Format Rupiah
    final formatted = _formatter.format(int.parse(digitsOnly));

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// =============================
/// Halaman Tambah Produk
/// =============================
class AddProductScreen extends StatefulWidget {
  const AddProductScreen({super.key});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final dbHelper = DatabaseHelper.instance;
  final _formKey = GlobalKey<FormState>();

  final TextEditingController barcodeController = TextEditingController();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController priceRetailController = TextEditingController();
  final TextEditingController priceWholesaleController = TextEditingController();
  final TextEditingController stockController = TextEditingController();

  bool isSaving = false;

  /// Pindah ke halaman scan barcode
  Future<void> _scanBarcode() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const BarcodeScannerScreen(),
      ),
    );

    if (result != null && result is String) {
      setState(() {
        barcodeController.text = result;
      });
    }
  }

  /// Simpan Produk ke Database
  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isSaving = true);

    try {
      final db = await dbHelper.database;

      await db.insert('products', {
        'name': nameController.text.trim(),
        'barcode': barcodeController.text.trim(),
        'price_retail':
            int.parse(priceRetailController.text.replaceAll('.', '')), // hapus titik
        'price_wholesale':
            int.parse(priceWholesaleController.text.replaceAll('.', '')), // hapus titik
        'stock': int.parse(stockController.text),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Produk berhasil ditambahkan")),
      );

      Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Gagal menyimpan produk: $e")),
      );
    } finally {
      setState(() => isSaving = false);
    }
  }

  /// Widget untuk TextField
  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required TextInputType keyboardType,
    required String? Function(String?) validator,
    bool readOnly = false,
    Widget? suffixIcon,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        labelText: label,
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.grey.shade100,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.blueAccent, width: 1.5),
        ),
      ),
      validator: validator,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        elevation: 0,
        title: Text(
          "Tambah Produk",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.blueAccent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Card(
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  /// Barcode
                  _buildTextField(
                    label: "Barcode",
                    controller: barcodeController,
                    keyboardType: TextInputType.number,
                    validator: (value) =>
                        value!.isEmpty ? "Barcode wajib diisi" : null,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.qr_code_scanner),
                      onPressed: _scanBarcode,
                      color: Colors.blueAccent,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly, // hanya angka
                    ],
                  ),
                  const SizedBox(height: 18),

                  /// Nama Produk
                  _buildTextField(
                    label: "Nama Produk",
                    controller: nameController,
                    keyboardType: TextInputType.text,
                    validator: (value) =>
                        value!.isEmpty ? "Nama produk wajib diisi" : null,
                  ),
                  const SizedBox(height: 18),

                  /// Harga Eceran
                  _buildTextField(
                    label: "Harga Eceran",
                    controller: priceRetailController,
                    keyboardType: TextInputType.number,
                    validator: (value) =>
                        value!.isEmpty ? "Harga eceran wajib diisi" : null,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly, // hanya angka
                      CurrencyInputFormatter(), // format otomatis Rupiah
                    ],
                  ),
                  const SizedBox(height: 18),

                  /// Harga Grosir
                  _buildTextField(
                    label: "Harga Grosir",
                    controller: priceWholesaleController,
                    keyboardType: TextInputType.number,
                    validator: (value) =>
                        value!.isEmpty ? "Harga grosir wajib diisi" : null,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly, // hanya angka
                      CurrencyInputFormatter(), // format otomatis Rupiah
                    ],
                  ),
                  const SizedBox(height: 18),

                  /// Stok Awal
                  _buildTextField(
                    label: "Stok Awal",
                    controller: stockController,
                    keyboardType: TextInputType.number,
                    validator: (value) =>
                        value!.isEmpty ? "Stok awal wajib diisi" : null,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly, // hanya angka
                    ],
                  ),
                  const SizedBox(height: 28),

                  /// Tombol Simpan
                  SizedBox(
                    height: 55,
                    child: ElevatedButton.icon(
                      icon: isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.save),
                      label: Text(
                        isSaving ? "Menyimpan..." : "Simpan Produk",
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: isSaving ? null : _saveProduct,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// =============================
/// Halaman Scanner Barcode
/// =============================
class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  bool _isBarcodeDetected = false; // Cegah multiple detect

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Scan Barcode"),
        backgroundColor: Colors.blueAccent,
      ),
      body: MobileScanner(
        onDetect: (BarcodeCapture capture) {
          if (_isBarcodeDetected) return;
          final List<Barcode> barcodes = capture.barcodes;

          if (barcodes.isNotEmpty) {
            final String? value = barcodes.first.rawValue;
            if (value != null && value.isNotEmpty) {
              setState(() {
                _isBarcodeDetected = true;
              });

              /// Delay sedikit agar tidak glitch
              Future.delayed(const Duration(milliseconds: 300), () {
                Navigator.pop(context, value); // kirim hasil ke AddProduct
              });
            }
          }
        },
      ),
    );
  }
}
