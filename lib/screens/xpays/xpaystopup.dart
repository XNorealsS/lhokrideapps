import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Main Widget for the Revamped Top Up and History functionality
class TopUpPage extends StatefulWidget {
  @override
  _TopUpPageState createState() => _TopUpPageState();
}

class _TopUpPageState extends State<TopUpPage> {
  // --- State Variables ---
  int _selectedIndex = 0; // 0 for Top Up, 1 for History
  static const _storage = FlutterSecureStorage();

  // Loading and State Management
  bool isLoadingItems = true;
  bool isLoadingHistory = true;
  bool isGeneratingQR = false;
  bool isCheckingPayment = false;

  // Top-Up Data
  List<Map<String, dynamic>> availableItems = [];
  Map<String, dynamic>? selectedItem;
  final TextEditingController _customAmountController = TextEditingController();

  // Invoice & QR Data
  String qrImageUrl = '';
  double? finalAmount;
  double _uniqueAdminFee = 0.0; // Added for unique admin fee
  String? invoiceId;
  DateTime? _expiryTime;
  Timer? _countdownTimer;
  Duration _remainingTime = Duration(minutes: 30);

  // History Data
  List<Map<String, dynamic>> transactionHistory = [];

  // API and User Data
  final String baseUrl = 'http://api.lhokride.com/api/qrRoute';
  String? _userName;
  String? _userId;

  // Define primary color
  static const Color primaryOrange = Color(0xFFFF8A00);

  // --- Lifecycle Methods ---
  @override
  void initState() {
    super.initState();
    _loadUserDataAndFetchData();
    _customAmountController.addListener(_onCustomAmountChanged);
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _customAmountController.dispose();
    super.dispose();
  }

  // --- Core Logic ---

  Future<void> _loadUserDataAndFetchData() async {
    final name = await _storage.read(key: 'name');
    final userId = await _storage.read(key: 'user_id');

    setState(() {
      _userName = name ?? 'Pengguna';
      _userId = userId;
    });

    if (_userId == null) {
      _showErrorSnackBar('User ID tidak ditemukan. Harap login kembali.');
      return;
    }
    await fetchItems();
    await fetchTransactionHistory();
  }

  void _onCustomAmountChanged() {
    if (_customAmountController.text.isNotEmpty) {
      if (selectedItem != null) {
        setState(() {
          selectedItem = null; // Deselect grid item if user types
        });
      }
    }
  }

  // --- API Calls (Maintained from original code, with refined loading states) ---

  Future<void> fetchItems() async {
    setState(() => isLoadingItems = true);
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/items'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
          )
          .timeout(Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['items'] != null) {
          setState(
            () =>
                availableItems = List<Map<String, dynamic>>.from(data['items']),
          );
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      _showErrorSnackBar('Gagal memuat pilihan top up.');
    } finally {
      setState(() => isLoadingItems = false);
    }
  }

  Future<void> handleBayar() async {
    if (_userId == null) return;
    // For now, we only handle predefined items. Custom amount would need a different endpoint.
    if (selectedItem == null) {
      _showInfoSnackBar("Pilih nominal top up terlebih dahulu.");
      return;
    }
    ;

    setState(() => isGeneratingQR = true);

    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/generate-topup-qr'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'item_ids': [selectedItem!['id']],
              'user_id': _userId,
            }),
          )
          .timeout(Duration(seconds: 20));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['qr_base64'] != null) {
        double? parsedFinalAmount = (data['final_amount'] as num?)?.toDouble();
        double? uniqecode = (data['unique_code'] as num?)?.toDouble();

        setState(() {
          finalAmount = parsedFinalAmount;
          _uniqueAdminFee = uniqecode ?? 0.0;
          qrImageUrl = data['qr_base64'];
          invoiceId = data['invoice_id'];
          if (data['expires_at'] != null) {
            _expiryTime = DateTime.tryParse(data['expires_at']);
            _startExpiryCountdown();
          }
        });
        _showPaymentBottomSheet(); // NEW: Show bottom sheet instead of rebuilding screen
      } else {
        throw Exception(data['error'] ?? 'Gagal membuat kode QR');
      }
    } catch (e) {
      _showErrorSnackBar('Terjadi kesalahan: ${e.toString()}');
    } finally {
      setState(() => isGeneratingQR = false);
    }
  }

  Future<void> handleCekPembayaran({String? specificInvoiceId}) async {
    final idToCheck = specificInvoiceId ?? invoiceId;
    if (idToCheck == null) return;

    setState(() => isCheckingPayment = true);

    try {
      // Ambil token dari secure storage
      final token = await _storage.read(key: 'token');
      if (token == null) throw Exception('Token tidak ditemukan');

      final response = await http.post(
        Uri.parse('$baseUrl/paymentcheck'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'invoice_id': idToCheck}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        if (data['status'] == 'paid') {
          _showSuccessSnackBar(
            "Pembayaran berhasil! Saldo akan segera diperbarui.",
          );
          if (specificInvoiceId == null)
            Navigator.pop(context); // Tutup bottom sheet
          await fetchTransactionHistory(); // Refresh histori
        } else {
          _showInfoSnackBar("Pembayaran masih tertunda.");
        }
      } else {
        throw Exception(data['error'] ?? 'Gagal cek status');
      }
    } catch (e) {
      _showErrorSnackBar('Gagal cek pembayaran: ${e.toString()}');
    } finally {
      setState(() => isCheckingPayment = false);
    }
  }

  Future<void> fetchTransactionHistory() async {
    if (_userId == null) return;
    setState(() => isLoadingHistory = true);
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/invoices/user'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'user_id': _userId}),
          )
          .timeout(Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['invoices'] != null) {
          setState(
            () =>
                transactionHistory = List<Map<String, dynamic>>.from(
                  data['invoices'],
                ),
          );
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      // Don't show snackbar on initial load error, handled by UI state
    } finally {
      setState(() => isLoadingHistory = false);
    }
  }

  // --- UI Helpers & Formatters ---

  void _startExpiryCountdown() {
    _expiryTime ??= DateTime.now().add(Duration(minutes: 30));
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      final remaining = _expiryTime!.difference(DateTime.now());
      if (mounted) {
        setState(() {
          if (remaining.isNegative) {
            _remainingTime = Duration.zero;
            timer.cancel();
            // Only close if the current sheet corresponds to this timer
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            }
            _showInfoSnackBar("Kode QR telah kedaluwarsa.");
          } else {
            _remainingTime = remaining;
          }
        });
      } else {
        timer.cancel();
      }
    });
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showInfoSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.blue.shade600,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String formatCurrency(double? amount, {String symbol = 'Rp'}) {
    if (amount == null) return "${symbol}0";
    final formatter = NumberFormat.currency(
      locale: 'id_ID',
      symbol: symbol,
      decimalDigits: 0,
    );
    return formatter.format(amount);
  }

  // New formatter for unique code (3 digits)
  String formatUniqueCode(double amount) {
    return NumberFormat('000').format(amount.toInt());
  }

  String formatDate(String? dateString) {
    if (dateString == null) return "N/A";
    try {
      final dateTime = DateTime.parse(dateString).toLocal();
      return DateFormat('dd MMM yyyy, HH:mm').format(dateTime);
    } catch (e) {
      return "Invalid Date";
    }
  }

  void selectItem(Map<String, dynamic> item) {
    setState(() {
      _customAmountController.clear();
      if (selectedItem == item) {
        selectedItem = null;
      } else {
        selectedItem = item;
      }
    });
  }

  // --- Main Build Method ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7), // A clean, light grey background
      appBar: AppBar(
        title: Text(
          _selectedIndex == 0 ? "Top Up XPays" : "Riwayat Transaksi",
          style: const TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _selectedIndex == 0 ? _buildTopUpBody() : _buildHistoryBody(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
            // No need to clear items, just switch the view
          });
        },
        selectedItemColor: primaryOrange,
        unselectedItemColor: Colors.grey.shade600,
        selectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
        unselectedLabelStyle: const TextStyle(fontSize: 12),
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        elevation: 2.0,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet_outlined),
            activeIcon: Icon(Icons.account_balance_wallet),
            label: 'Top Up',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history_outlined),
            activeIcon: Icon(Icons.history),
            label: 'Riwayat',
          ),
        ],
      ),
    );
  }

  // --- UI Builders ---

  // NEW: Main body for the Top-Up tab
  Widget _buildTopUpBody() {
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: fetchItems,
            color: primaryOrange,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 20.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 24),
                  // For now custom amount is disabled as it needs backend logic
                  // _buildCustomAmountInput(),
                  // SizedBox(height: 16),
                  const Text(
                    "Pilih Nominal Cepat",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 16),
                  isLoadingItems
                      ? _buildItemsLoading()
                      : _buildItemSelectionGrid(),
                ],
              ),
            ),
          ),
        ),
        _buildStickyPayButton(),
      ],
    );
  }

  // NEW: Header section with user greeting
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: primaryOrange.withOpacity(0.1),
            child: const Icon(Icons.person, color: primaryOrange),
            radius: 24,
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Halo, ${_userName ?? 'Pengguna'}!",
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "Mau top up XPays berapa hari ini?",
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // NEW: A cleaner grid for item selection
  Widget _buildItemSelectionGrid() {
    if (availableItems.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40.0),
          child: Column(
            children: [
              Icon(
                Icons.cloud_off_outlined,
                color: Colors.grey.shade400,
                size: 50,
              ),
              const SizedBox(height: 16),
              Text(
                "Pilihan top up tidak tersedia",
                style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.9,
      ),
      itemCount: availableItems.length,
      itemBuilder: (context, index) {
        final item = availableItems[index];
        final isSelected = selectedItem == item;
        final price = double.tryParse(item['price']?.toString() ?? '0.0');

        return GestureDetector(
          onTap: () => selectItem(item),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              color: isSelected ? primaryOrange : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? primaryOrange : Colors.grey.shade200,
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  item['name'] ?? 'XPays',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: isSelected ? Colors.white : Colors.grey.shade500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  formatCurrency(price, symbol: ''),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : primaryOrange,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // NEW: A loading shimmer for the grid
  Widget _buildItemsLoading() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.9,
      ),
      itemCount: 6,
      itemBuilder:
          (context, index) => Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
    );
  }

  // NEW: Sticky pay button at the bottom
  Widget _buildStickyPayButton() {
    final price = double.tryParse(selectedItem?['price']?.toString() ?? '0.0');
    bool isButtonEnabled = selectedItem != null;

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        16 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: isButtonEnabled && !isGeneratingQR ? handleBayar : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryOrange,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey.shade300,
            disabledForegroundColor: Colors.grey.shade500,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 0,
          ),
          child:
              isGeneratingQR
                  ? const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    strokeWidth: 3,
                  )
                  : Text(
                    selectedItem == null
                        ? "Pilih Nominal"
                        : "Lanjut Bayar • ${formatCurrency(price)}",
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
        ),
      ),
    );
  }

  // NEW: The payment bottom sheet
  void _showPaymentBottomSheet() {
    // Only decode QR image once
    final Widget qrImageWidget =
        qrImageUrl.isNotEmpty
            ? Image.memory(
              base64Decode(qrImageUrl.split(',').last),
              width: 220,
              height: 220,
              fit: BoxFit.contain,
              errorBuilder:
                  (c, e, s) =>
                      Icon(Icons.error, size: 80, color: Colors.red.shade300),
            )
            : const Center(
              child: SizedBox(
                width: 50,
                height: 50,
                child: CircularProgressIndicator(color: primaryOrange),
              ),
            );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            // Re-create the countdown timer logic inside the sheet to update independently
            Timer? sheetCountdownTimer;
            Duration sheetRemainingTime = _remainingTime;

            // Important: This function needs to be defined inside StatefulBuilder
            // or called with setSheetState to update the sheet's UI
            void startSheetCountdownForSheet() {
              final expiry =
                  _expiryTime ?? DateTime.now().add(const Duration(minutes: 30));
              sheetCountdownTimer?.cancel();
              sheetCountdownTimer = Timer.periodic(const Duration(seconds: 1), (
                timer,
              ) {
                final remaining = expiry.difference(DateTime.now());
                if (mounted) {
                  setSheetState(() {
                    if (remaining.isNegative) {
                      sheetRemainingTime = Duration.zero;
                      timer.cancel();
                      if (Navigator.canPop(context)) {
                        Navigator.pop(context); // Close the bottom sheet
                      }
                      _showInfoSnackBar("Kode QR telah kedaluwarsa.");
                    } else {
                      sheetRemainingTime = remaining;
                    }
                  });
                } else {
                  timer.cancel(); // Cancel if widget is unmounted
                }
              });
            }

            // Start the countdown when the sheet is built
            // Ensure this is called only once, e.g., using a flag or in init state for the sheet
            WidgetsBinding.instance.addPostFrameCallback((_) {
              startSheetCountdownForSheet();
            });


            return DraggableScrollableSheet(
              initialChildSize: 0.9,
              minChildSize: 0.5,
              maxChildSize: 0.9,
              builder: (_, scrollController) {
                return Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF5F5F7),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: Column(
                    children: [
                      // Handle and Title
                      Container(
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        "Selesaikan Pembayaran",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Selesaikan dalam ${sheetRemainingTime.inMinutes.toString().padLeft(2, '0')}:${(sheetRemainingTime.inSeconds % 60).toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: 16,
                          color:
                              sheetRemainingTime.inSeconds < 60
                                  ? Colors.red.shade700
                                  : Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          controller: scrollController,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24.0),
                            child: Column(
                              children: [
                                _buildQRDisplay(
                                  qrImageWidget,
                                ), // Pass the pre-decoded QR image
                                const SizedBox(height: 24),
                                _buildPaymentDetails(),
                              ],
                            ),
                          ),
                        ),
                      ),
                      _buildCheckStatusButton(),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    ).whenComplete(() {
      _countdownTimer?.cancel(); // Important: cancel timer when sheet is closed
      // Reset state for next top-up attempt
      setState(() {
        selectedItem = null;
        qrImageUrl = '';
        invoiceId = null;
        finalAmount = null;
        _uniqueAdminFee = 0.0;
        _remainingTime = const Duration(minutes: 30);
      });
    });
  }

  Widget _buildQRDisplay(Widget qrImageWidget) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            "Scan QRIS untuk Membayar",
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade200),
              borderRadius: BorderRadius.circular(16),
            ),
            child: qrImageWidget, // Use the pre-decoded widget here
          ),
          const SizedBox(height: 20),
          Image.asset(
            'assets/images/qris-logo.png', // Ensure this image is in your assets folder
            height: 25,
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentDetails() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Rincian Tagihan",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          const SizedBox(height: 16),
          _buildDetailRow(
            "Top Up XPays",
            formatCurrency(
              double.tryParse(selectedItem?['price']?.toString() ?? '0.0'),
            ),
          ),
          const SizedBox(height: 8),
          _buildDetailRow(
            "Biaya Admin Unik",
            formatCurrency(_uniqueAdminFee),
          ), // Display unique admin fee
          const Divider(height: 32, thickness: 1, color: Colors.grey),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Total Pembayaran",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              Text(
                formatCurrency(finalAmount),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: primaryOrange,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCheckStatusButton() {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          onPressed: isCheckingPayment ? null : () => handleCekPembayaran(),
          icon:
              isCheckingPayment
                  ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                  : const Icon(Icons.check_circle_outline, size: 22),
          label: const Text(
            "Saya Sudah Bayar",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryOrange,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 0,
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
        ),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ],
    );
  }

  // --- History UI ---

  Widget _buildHistoryBody() {
    if (isLoadingHistory) {
      return const Center(child: CircularProgressIndicator(color: primaryOrange));
    }
    if (transactionHistory.isEmpty) {
      return _buildEmptyHistory();
    }
    return RefreshIndicator(
      onRefresh: fetchTransactionHistory,
      color: primaryOrange,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: transactionHistory.length,
        itemBuilder: (context, index) {
          return _buildHistoryCard(transactionHistory[index]);
        },
      ),
    );
  }

  Widget _buildEmptyHistory() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 70,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 20),
          Text(
            "Riwayat Transaksi Kosong",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Semua transaksimu akan muncul di sini.",
            style: TextStyle(color: Colors.grey.shade500),
          ),
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: fetchTransactionHistory,
            icon: const Icon(Icons.refresh, color: primaryOrange),
            label: const Text(
              "Coba Muat Ulang",
              style: TextStyle(
                color: primaryOrange,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> invoice) {
    final isPaid = invoice['status'] == 'paid';
    final amount = double.tryParse(
      invoice['final_amount']?.toString() ?? '0.0',
    );
    final itemName =
        (invoice['items'] as List?)?.isNotEmpty ?? false
            ? (invoice['items'][0]['name'] ?? 'Top Up')
            : 'Top Up';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                      isPaid
                          ? Colors.green.withOpacity(0.1)
                          : primaryOrange.withOpacity(0.1),
                  child: Icon(
                    isPaid
                        ? Icons.check_circle_rounded
                        : Icons.hourglass_top_rounded,
                    color:
                        isPaid ? Colors.green.shade600 : primaryOrange,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Top Up $itemName",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatDate(invoice['created_at']),
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  formatCurrency(amount),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: primaryOrange,
                  ),
                ),
              ],
            ),
            if (!isPaid) ...[
              const Divider(height: 24, thickness: 1, color: Colors.grey),
              SizedBox(
                width: double.infinity,
                height: 40,
                child: ElevatedButton(
                  onPressed:
                      () =>
                          handleCekPembayaran(specificInvoiceId: invoice['id']),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryOrange.withOpacity(0.1),
                    foregroundColor: primaryOrange,
                    elevation: 0,
                    textStyle: const TextStyle(fontWeight: FontWeight.bold),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: isCheckingPayment && invoiceId == invoice['id'] // Show loading only for the specific invoice being checked
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: primaryOrange,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text("Cek Status Pembayaran"),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}