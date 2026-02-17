import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:warung_kita/db/database_helper.dart';
import 'package:warung_kita/services/printer_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CheckoutScreen extends StatefulWidget {
  final List<Map<String, dynamic>> cart;
  final int totalAmount;
  final bool editMode;
  final int? transactionId;
  final int? dailyNumber;

  const CheckoutScreen({
    super.key,
    required this.cart,
    required this.totalAmount,
    this.editMode = false,
    this.transactionId,
    this.dailyNumber,
  });

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final dbHelper = DatabaseHelper.instance;
  final printerService = PrinterService();
  final TextEditingController cashController = TextEditingController();
  final formatCurrency = NumberFormat.currency(
    locale: 'id',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  String paymentMethod = 'cash'; // 'cash' atau 'qris'
  int cashReceived = 0;
  int changeAmount = 0;
  bool isProcessing = false;

  @override
  void dispose() {
    cashController.dispose();
    super.dispose();
  }

  void _updateCash(int amount) {
    setState(() {
      cashReceived = amount;
      cashController.text = formatCurrency.format(amount).replaceAll('Rp ', '');
      _calculateChange();
    });
  }

  void _calculateChange() {
    setState(() {
      changeAmount = cashReceived - widget.totalAmount;
    });
  }

  void _onCashInputChanged(String value) {
    final cleanValue = value.replaceAll('.', '').replaceAll(',', '');
    if (cleanValue.isEmpty) {
      setState(() {
        cashReceived = 0;
        changeAmount = 0;
      });
      return;
    }

    setState(() {
      cashReceived = int.tryParse(cleanValue) ?? 0;
      _calculateChange();
    });
  }

  Future<void> _processCheckout() async {
    if (paymentMethod == 'cash' && cashReceived < widget.totalAmount) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Uang yang diterima kurang dari total belanja"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => isProcessing = true);

    try {
      final db = await dbHelper.database;
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id') ?? 1;
      int transactionId;
      int dailyNumber;

      if (widget.editMode && widget.transactionId != null) {
        // Update existing transaction
        transactionId = widget.transactionId!;
        await db.update(
          'transactions',
          {
            'total_amount': widget.totalAmount,
            'payment_method': paymentMethod,
            'cash_received': paymentMethod == 'cash' ? cashReceived : 0,
            'change_amount': paymentMethod == 'cash' ? changeAmount : 0,
          },
          where: 'id = ?',
          whereArgs: [widget.transactionId],
        );

        // Delete old transaction items
        await db.delete(
          'transaction_items',
          where: 'transaction_id = ?',
          whereArgs: [widget.transactionId],
        );

        // Insert updated items
        for (var item in widget.cart) {
          await db.insert('transaction_items', {
            'transaction_id': widget.transactionId,
            'product_id': item['id'],
            'quantity': item['qty'],
            'unit_name': item['unit'],
            'price': item['price'],
          });

          // Update stock (kembalikan stok lama, kurangi stok baru)
          final conversionRate = item['conversion_rate'] ?? 1.0;
          final stockChange = item['qty'] * conversionRate;

          await db.rawUpdate(
            'UPDATE products SET stock = stock - ? WHERE id = ?',
            [stockChange, item['id']],
          );
        }

        dailyNumber = widget.dailyNumber ?? transactionId;
      } else {
        // Create new transaction
        transactionId = await db.insert('transactions', {
          'user_id': userId,
          'total_amount': widget.totalAmount,
          'payment_method': paymentMethod,
          'cash_received': paymentMethod == 'cash' ? cashReceived : 0,
          'change_amount': paymentMethod == 'cash' ? changeAmount : 0,
          'created_at': DateTime.now().toIso8601String(),
        });

        // Insert transaction items and update stock
        for (var item in widget.cart) {
          await db.insert('transaction_items', {
            'transaction_id': transactionId,
            'product_id': item['id'],
            'quantity': item['qty'],
            'unit_name': item['unit'],
            'price': item['price'],
          });

          // Update stock based on conversion rate
          final conversionRate = item['conversion_rate'] ?? 1.0;
          final stockChange = item['qty'] * conversionRate;

          await db.rawUpdate(
            'UPDATE products SET stock = stock - ? WHERE id = ?',
            [stockChange, item['id']],
          );
        }

        // Get daily transaction number
        final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
        final result = await db.rawQuery(
          '''
          SELECT COUNT(*) as count FROM transactions
          WHERE DATE(created_at) = ? AND id <= ?
          ORDER BY created_at ASC
        ''',
          [today, transactionId],
        );
        dailyNumber = result.first['count'] as int;
      }

      setState(() => isProcessing = false);

      // Show receipt preview
      if (mounted) {
        await _showReceiptPreview(transactionId, dailyNumber);
      }
    } catch (e) {
      setState(() => isProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showReceiptPreview(int transactionId, int dailyNumber) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ReceiptPreviewDialog(
        transactionId: transactionId,
        dailyNumber: dailyNumber,
        cart: widget.cart,
        totalAmount: widget.totalAmount,
        paymentMethod: paymentMethod,
        cashReceived: cashReceived,
        changeAmount: changeAmount,
        printerService: printerService,
        formatCurrency: formatCurrency,
        editMode: widget.editMode,
      ),
    );

    if (mounted && result == true) {
      // Pop checkout screen, kembali ke cashier
      Navigator.pop(context, true);
    }
  }

  Widget _buildPaymentMethodButton({
    required String method,
    required String label,
    required IconData icon,
  }) {
    final isSelected = paymentMethod == method;

    return Material(
      color: isSelected ? Colors.blueAccent : Colors.white,
      borderRadius: BorderRadius.circular(12),
      elevation: isSelected ? 4 : 1,
      child: InkWell(
        onTap: () {
          setState(() {
            paymentMethod = method;
            if (method == 'qris') {
              cashReceived = 0;
              changeAmount = 0;
              cashController.clear();
            }
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.white : Colors.blueAccent,
                size: 32,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickCashButton(int amount) {
    final isSelected = cashReceived == amount;

    return Expanded(
      child: Material(
        color: isSelected ? Colors.blueAccent : Colors.white,
        borderRadius: BorderRadius.circular(12),
        elevation: isSelected ? 4 : 1,
        child: InkWell(
          onTap: () => _updateCash(amount),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              children: [
                Icon(
                  Icons.payments_outlined,
                  color: isSelected ? Colors.white : Colors.blueAccent,
                  size: 24,
                ),
                const SizedBox(height: 4),
                Text(
                  formatCurrency.format(amount),
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        elevation: 0,
        title: Text(
          'Checkout',
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Total Amount
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade700, Colors.blue.shade500],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Text(
                      'Total Belanja',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      formatCurrency.format(widget.totalAmount),
                      style: GoogleFonts.poppins(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Payment Method
            Text(
              'Metode Pembayaran',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildPaymentMethodButton(
                    method: 'cash',
                    label: 'Cash',
                    icon: Icons.payments,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildPaymentMethodButton(
                    method: 'qris',
                    label: 'QRIS',
                    icon: Icons.qr_code,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Cash Payment Section
            if (paymentMethod == 'cash') ...[
              Text(
                'Nominal Cepat',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildQuickCashButton(20000),
                  const SizedBox(width: 8),
                  _buildQuickCashButton(50000),
                  const SizedBox(width: 8),
                  _buildQuickCashButton(100000),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Uang Diterima',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: cashController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  TextInputFormatter.withFunction((oldValue, newValue) {
                    if (newValue.text.isEmpty) {
                      return newValue;
                    }
                    final number = int.parse(newValue.text);
                    final formatted = formatCurrency
                        .format(number)
                        .replaceAll('Rp ', '');
                    return TextEditingValue(
                      text: formatted,
                      selection: TextSelection.collapsed(
                        offset: formatted.length,
                      ),
                    );
                  }),
                ],
                decoration: InputDecoration(
                  prefixText: 'Rp ',
                  hintText: '0',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                onChanged: _onCashInputChanged,
              ),
              const SizedBox(height: 24),
              Card(
                color: changeAmount >= 0
                    ? Colors.green.shade50
                    : Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Kembalian',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        formatCurrency.format(changeAmount),
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: changeAmount >= 0
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 32),

            // Checkout Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isProcessing ? null : _processCheckout,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: isProcessing
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        widget.editMode
                            ? 'Update Pembelian'
                            : 'Selesaikan Pembayaran',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Receipt Preview Dialog
class _ReceiptPreviewDialog extends StatefulWidget {
  final int transactionId;
  final int dailyNumber;
  final List<Map<String, dynamic>> cart;
  final int totalAmount;
  final String paymentMethod;
  final int cashReceived;
  final int changeAmount;
  final PrinterService printerService;
  final NumberFormat formatCurrency;
  final bool editMode;

  const _ReceiptPreviewDialog({
    required this.transactionId,
    required this.dailyNumber,
    required this.cart,
    required this.totalAmount,
    required this.paymentMethod,
    required this.cashReceived,
    required this.changeAmount,
    required this.printerService,
    required this.formatCurrency,
    required this.editMode,
  });

  @override
  State<_ReceiptPreviewDialog> createState() => _ReceiptPreviewDialogState();
}

class _ReceiptPreviewDialogState extends State<_ReceiptPreviewDialog> {
  bool isPrinting = false;

  Future<void> _printReceipt() async {
    if (!widget.printerService.connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Printer belum terhubung'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => isPrinting = true);

    try {
      await widget.printerService.printReceipt(
        transactionId: widget.transactionId,
        dailyNumber: widget.dailyNumber,
        cart: widget.cart,
        totalAmount: widget.totalAmount,
        paymentMethod: widget.paymentMethod,
        cashReceived: widget.cashReceived,
        changeAmount: widget.changeAmount,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Struk berhasil dicetak!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mencetak: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => isPrinting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
          maxWidth: 400,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.green.shade600, Colors.green.shade400],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 64),
                  const SizedBox(height: 12),
                  Text(
                    widget.editMode
                        ? 'Pembelian Berhasil Diupdate!'
                        : 'Pembayaran Berhasil!',
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Transaksi #${widget.dailyNumber}',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            ),

            // Receipt Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Store Info
                    Center(
                      child: Column(
                        children: [
                          Text(
                            'TOKO RIZKI',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            DateFormat(
                              'dd MMM yyyy, HH:mm',
                            ).format(DateTime.now()),
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 12),

                    // Items
                    ...widget.cart.map((item) {
                      final qty = item['qty'] is int
                          ? (item['qty'] as int).toDouble()
                          : item['qty'] as double;
                      final price = (item['price'] as int).toDouble();
                      final subtotal = (price * qty).round();
                      final qtyText = qty % 1 == 0
                          ? qty.toInt().toString()
                          : qty.toString().replaceAll('.', ',');

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    item['name'],
                                    style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Text(
                                  widget.formatCurrency.format(subtotal),
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$qtyText ${item['unit']} × ${widget.formatCurrency.format(price)}',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),

                    const Divider(),
                    const SizedBox(height: 12),

                    // Total
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'TOTAL',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          widget.formatCurrency.format(widget.totalAmount),
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Payment Details
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Metode',
                                style: GoogleFonts.poppins(fontSize: 12),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: widget.paymentMethod == 'cash'
                                      ? Colors.green.shade100
                                      : Colors.blue.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  widget.paymentMethod == 'cash'
                                      ? 'TUNAI'
                                      : 'QRIS',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: widget.paymentMethod == 'cash'
                                        ? Colors.green.shade700
                                        : Colors.blue.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (widget.paymentMethod == 'cash' &&
                              widget.cashReceived > 0) ...[
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Tunai',
                                  style: GoogleFonts.poppins(fontSize: 12),
                                ),
                                Text(
                                  widget.formatCurrency.format(
                                    widget.cashReceived,
                                  ),
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Kembali',
                                  style: GoogleFonts.poppins(fontSize: 12),
                                ),
                                Text(
                                  widget.formatCurrency.format(
                                    widget.changeAmount,
                                  ),
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.green.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    Center(
                      child: Text(
                        'Terima kasih telah berbelanja!',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Action Buttons
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  if (widget.printerService.connected)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: isPrinting ? null : _printReceipt,
                        icon: isPrinting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.print),
                        label: Text(
                          isPrinting ? 'Mencetak...' : 'Cetak Struk',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.orange.shade700,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Printer belum terhubung',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: Colors.orange.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context, true),
                      icon: const Icon(Icons.check),
                      label: Text(
                        'Selesai',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.green,
                        side: const BorderSide(color: Colors.green, width: 2),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
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
