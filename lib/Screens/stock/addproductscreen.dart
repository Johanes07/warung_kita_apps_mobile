import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:warung_kita/db/database_helper.dart';
import 'package:intl/intl.dart';

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

    String digitsOnly = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final formatted = _formatter.format(int.parse(digitsOnly));

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

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
  final TextEditingController priceWholesaleController =
      TextEditingController();
  final TextEditingController stockRetailController = TextEditingController();
  final TextEditingController stockWholesaleController =
      TextEditingController();

  bool isSaving = false;

  @override
  void dispose() {
    barcodeController.dispose();
    nameController.dispose();
    priceRetailController.dispose();
    priceWholesaleController.dispose();
    stockRetailController.dispose();
    stockWholesaleController.dispose();
    super.dispose();
  }

  Future<void> _scanBarcode() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const BarcodeScannerScreen()),
    );

    if (result != null && result is String) {
      setState(() {
        barcodeController.text = result;
      });
    }
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isSaving = true);

    try {
      final db = await dbHelper.database;

      int stockRetail = int.parse(stockRetailController.text);
      int stockWholesale = int.parse(stockWholesaleController.text);
      int totalStock = stockRetail + stockWholesale;

      await db.insert('products', {
        'name': nameController.text.trim(),
        'barcode': barcodeController.text.trim(),
        'price_retail': int.parse(
          priceRetailController.text.replaceAll('.', ''),
        ),
        'price_wholesale': int.parse(
          priceWholesaleController.text.replaceAll('.', ''),
        ),
        'stock': totalStock,
        'stock_retail': stockRetail,
        'stock_wholesale': stockWholesale,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Produk berhasil ditambahkan")),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Gagal menyimpan produk: $e")));
      }
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required TextInputType keyboardType,
    required String? Function(String?) validator,
    required IconData icon,
    bool readOnly = false,
    Widget? suffixIcon,
    List<TextInputFormatter>? inputFormatters,
    String? prefix,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.poppins(fontSize: 14),
        prefixIcon: Icon(icon, color: Colors.blueAccent),
        prefixText: prefix,
        prefixStyle: GoogleFonts.poppins(
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.blueAccent, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      validator: validator,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        elevation: 0,
        title: Text(
          "Tambah Produk",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.black),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage("assets/images/bgwarung2.jpg"),
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Barcode
                  _buildTextField(
                    label: "Barcode",
                    controller: barcodeController,
                    keyboardType: TextInputType.number,
                    icon: Icons.qr_code_2,
                    validator: (value) =>
                        value!.isEmpty ? "Barcode wajib diisi" : null,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.qr_code_scanner),
                      onPressed: _scanBarcode,
                      color: Colors.blueAccent,
                    ),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  const SizedBox(height: 16),

                  // Nama Produk
                  _buildTextField(
                    label: "Nama Produk",
                    controller: nameController,
                    keyboardType: TextInputType.text,
                    icon: Icons.shopping_bag,
                    validator: (value) =>
                        value!.isEmpty ? "Nama produk wajib diisi" : null,
                  ),
                  const SizedBox(height: 16),

                  // Harga Eceran
                  _buildTextField(
                    label: "Harga Eceran",
                    controller: priceRetailController,
                    keyboardType: TextInputType.number,
                    icon: Icons.sell,
                    prefix: "Rp ",
                    validator: (value) =>
                        value!.isEmpty ? "Harga eceran wajib diisi" : null,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      CurrencyInputFormatter(),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Harga Grosir
                  _buildTextField(
                    label: "Harga Grosir",
                    controller: priceWholesaleController,
                    keyboardType: TextInputType.number,
                    icon: Icons.local_offer,
                    prefix: "Rp ",
                    validator: (value) =>
                        value!.isEmpty ? "Harga grosir wajib diisi" : null,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      CurrencyInputFormatter(),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Stok Eceran
                  _buildTextField(
                    label: "Stok Eceran",
                    controller: stockRetailController,
                    keyboardType: TextInputType.number,
                    icon: Icons.shopping_basket,
                    validator: (value) =>
                        value!.isEmpty ? "Stok eceran wajib diisi" : null,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  const SizedBox(height: 16),

                  // Stok Grosir
                  _buildTextField(
                    label: "Stok Grosir",
                    controller: stockWholesaleController,
                    keyboardType: TextInputType.number,
                    icon: Icons.warehouse,
                    validator: (value) =>
                        value!.isEmpty ? "Stok grosir wajib diisi" : null,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  const SizedBox(height: 24),

                  // Tombol Simpan
                  SizedBox(
                    height: 50,
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
                          : const Icon(Icons.save, color: Colors.white),
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
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
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

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  bool _isBarcodeDetected = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Scan Barcode",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.black),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage("assets/images/bgwarung2.jpg"),
              fit: BoxFit.cover,
            ),
          ),
        ),
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

              Future.delayed(const Duration(milliseconds: 300), () {
                Navigator.pop(context, value);
              });
            }
          }
        },
      ),
    );
  }
}
