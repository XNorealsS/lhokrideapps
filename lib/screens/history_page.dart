import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../widgets/bottom_navigation.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  String _selectedFilter = 'Semua';

  // Storage
  static const _storage = FlutterSecureStorage();

  // User Data
  String? _userId;
  String? _userRole;
  String? _userName;
  String? _userPhone;

  // History data from API
  List<HistoryItem> _allHistory = [];
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final userId = await _storage.read(key: 'user_id');
    final role = await _storage.read(key: 'role');
    final name = await _storage.read(key: 'name');

    final phone = await _storage.read(key: 'phone');

    if (!mounted) return;

    setState(() {
      _userId = userId ?? 'LHK${DateTime.now().millisecondsSinceEpoch % 10000}';
      _userRole =
          role?.toLowerCase() ??
          'passenger'; // Pastikan lowercase untuk backend
      _userName = name ?? 'Pengguna LHOKRIDE+';
      _userPhone = phone ?? '+62 xxx xxxx xxxx';
    });

    // Load history after getting user data
    if (_userId != null) {
      await _fetchHistory();
    }
  }

  Future<void> _fetchHistory() async {
    if (_userId == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final token = await _storage.read(key: 'token');

      print(
        'Fetching history for userId: $_userId, role: $_userRole',
      ); // Debug log

      final response = await http.get(
        Uri.parse(
          'http://api.lhokride.com/api/rides/history/$_userId?role=$_userRole',
        ),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      print('Response status: ${response.statusCode}'); // Debug log
      print('Response body: ${response.body}'); // Debug log

      if (response.statusCode == 200) {
        final responseBody = response.body.trim();
        if (responseBody.isEmpty) {
          setState(() {
            _allHistory = [];
            _isLoading = false;
          });
          return;
        }

        try {
          final dynamic decodedData = json.decode(responseBody);
          List<dynamic> data;

          // Handle different response formats
          if (decodedData is List) {
            data = decodedData;
          } else if (decodedData is Map && decodedData.containsKey('data')) {
            data = decodedData['data'] as List;
          } else if (decodedData is Map && decodedData.containsKey('history')) {
            data = decodedData['history'] as List;
          } else {
            throw Exception('Invalid response format');
          }

          setState(() {
            _allHistory =
                data
                    .map((item) {
                      try {
                        return HistoryItem.fromJson(item);
                      } catch (e) {
                        print('Error parsing item: $item, Error: $e');
                        return null;
                      }
                    })
                    .where((item) => item != null)
                    .cast<HistoryItem>()
                    .toList();

            // Sort by date descending
            _allHistory.sort((a, b) => b.date.compareTo(a.date));
            _isLoading = false;
          });

          print('Loaded ${_allHistory.length} history items'); // Debug log
        } catch (parseError) {
          print('Parse error: $parseError');
          setState(() {
            _errorMessage = 'Error parsing data: $parseError';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage =
              'Gagal memuat riwayat: ${response.statusCode} - ${response.body}';
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Network error: $e');
      setState(() {
        _errorMessage = 'Error jaringan: $e';
        _isLoading = false;
      });
    }
  }

  List<HistoryItem> get _filteredHistory {
    if (_selectedFilter == 'Semua') {
      return _allHistory;
    }
    return _allHistory
        .where((item) => item.serviceType == _selectedFilter)
        .toList();
  }

  DateTime? _lastBackPressTime;

  Future<bool> _onWillPop() async {
    final now = DateTime.now();
    if (_lastBackPressTime == null ||
        now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
      _lastBackPressTime = now;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tekan sekali lagi untuk keluar')),
      );
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: PageWithBottomNav(
        activeTab: 'history',
        userRole: _userRole?.toLowerCase() ?? 'guest',
        child: Scaffold(
          backgroundColor: Colors.grey[50],
          appBar: AppBar(
            backgroundColor: Colors.orange[600],
            elevation: 0,
            automaticallyImplyLeading: false,
            title: Text(
              'Riwayat',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.refresh, color: Colors.white),
                onPressed: _fetchHistory,
              ),
            ],
          ),
          body: Column(
            children: [
              // Filter Tabs
              Container(
                color: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('Semua'),
                      SizedBox(width: 8),
                      _buildFilterChip('LhokRide'),
                      SizedBox(width: 8),
                      _buildFilterChip('LhokFood'),
                      SizedBox(width: 8),
                      _buildFilterChip('LhokSend'),
                      SizedBox(width: 8),
                      _buildFilterChip('LhokMart'),
                    ],
                  ),
                ),
              ),

              // Debug info (remove in production)
              if (_userId != null && _userRole != null)
                // History List
                Expanded(
                  child:
                      _isLoading
                          ? _buildLoadingState()
                          : _errorMessage.isNotEmpty
                          ? _buildErrorState()
                          : _filteredHistory.isEmpty
                          ? _buildEmptyState()
                          : RefreshIndicator(
                            onRefresh: _refreshHistory,
                            child: ListView.builder(
                              padding: EdgeInsets.all(16),
                              itemCount: _filteredHistory.length,
                              itemBuilder: (context, index) {
                                final item = _filteredHistory[index];
                                return _buildSimpleHistoryCard(item);
                              },
                            ),
                          ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.orange[600]!),
          ),
          SizedBox(height: 16),
          Text(
            'Memuat riwayat...',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            SizedBox(height: 16),
            Text(
              'Gagal memuat riwayat',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: 8),
            Text(
              _errorMessage,
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchHistory,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[600],
                foregroundColor: Colors.white,
              ),
              child: Text('Coba Lagi'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String filter) {
    final isSelected = _selectedFilter == filter;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFilter = filter;
        });
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.orange[600] : Colors.grey[200],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          filter == 'LhokRide'
              ? 'Ride'
              : filter == 'LhokFood'
              ? 'Food'
              : filter == 'LhokSend'
              ? 'Send'
              : filter == 'LhokMart'
              ? 'Mart'
              : filter,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[700],
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, size: 64, color: Colors.grey[400]),
          SizedBox(height: 16),
          Text(
            'Belum ada riwayat',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: 8),
          Text(
            _selectedFilter == 'Semua'
                ? 'Mulai gunakan layanan kami'
                : 'Belum ada riwayat untuk $_selectedFilter',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleHistoryCard(HistoryItem item) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Service Icon
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: item.color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(item.icon, color: item.color, size: 20),
          ),
          SizedBox(width: 12),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _getStatusColor(item.status).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        item.status,
                        style: TextStyle(
                          fontSize: 10,
                          color: _getStatusColor(item.status),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4),
                Text(
                  item.subtitle,
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDate(item.date),
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                    Text(
                      'Rp ${_formatCurrency(item.amount)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color:
                            item.status == 'Dibatalkan'
                                ? Colors.grey[500]
                                : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'selesai':
      case 'completed':
      case 'accepted':
        return Colors.green;
      case 'dibatalkan':
      case 'cancelled':
        return Colors.red;
      case 'dalam proses':
      case 'in_progress':
      case 'ongoing':
        return Colors.orange;
      case 'pending':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        return '${difference.inMinutes} menit lalu';
      }
      return '${difference.inHours} jam lalu';
    } else if (difference.inDays == 1) {
      return 'Kemarin';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} hari lalu';
    } else {
      return DateFormat('dd MMM yyyy', 'id_ID').format(date);
    }
  }

  String _formatCurrency(int amount) {
    return NumberFormat('#,###', 'id_ID').format(amount).replaceAll(',', '.');
  }

  Future<void> _refreshHistory() async {
    await _fetchHistory();
  }
}

class HistoryItem {
  final String id;
  final String serviceType;
  final String title;
  final String subtitle;
  final DateTime date;
  final String status;
  final int amount;
  final IconData icon;
  final Color color;

  HistoryItem({
    required this.id,
    required this.serviceType,
    required this.title,
    required this.subtitle,
    required this.date,
    required this.status,
    required this.amount,
    required this.icon,
    required this.color,
  });

  factory HistoryItem.fromJson(Map<String, dynamic> json) {
    try {
      // Parse date with multiple formats
      DateTime parsedDate;
      if (json['date'] is String) {
        try {
          parsedDate = DateTime.parse(json['date']);
        } catch (e) {
          parsedDate = DateTime.now();
        }
      } else {
        parsedDate = DateTime.now();
      }

      // Determine service type
      String serviceType = json['serviceType'] ?? json['type'] ?? 'LhokRide';

      // Get icon and color based on service type
      IconData icon;
      Color color;

      switch (serviceType.toLowerCase()) {
        case 'lhokfood':
        case 'food':
          icon = Icons.restaurant;
          color = Colors.orange;
          break;
        case 'lhoksend':
        case 'send':
          icon = Icons.local_shipping;
          color = Colors.blue;
          break;
        case 'lhokmart':
        case 'mart':
          icon = Icons.shopping_bag;
          color = Colors.purple;
          break;
        default:
          icon = Icons.motorcycle;
          color = Colors.green;
          serviceType = 'LhokRide';
      }

      // Override with JSON values if provided
      if (json['icon'] != null) {
        icon = _getIconFromString(json['icon']);
      }
      if (json['color'] != null) {
        color = _getColorFromString(json['color']);
      }

      return HistoryItem(
        id: json['id']?.toString() ?? '',
        serviceType: serviceType,
        title: json['title']?.toString() ?? 'Layanan',
        subtitle: json['subtitle']?.toString() ?? '',
        date: parsedDate,
        status: json['status']?.toString() ?? 'Selesai',
        amount: _parseAmount(json['amount']),
        icon: icon,
        color: color,
      );
    } catch (e) {
      print('Error in HistoryItem.fromJson: $e, JSON: $json');
      rethrow;
    }
  }

  static int _parseAmount(dynamic amount) {
    if (amount == null) return 0;
    if (amount is int) return amount;
    if (amount is double) return amount.round();
    if (amount is String) {
      return int.tryParse(amount) ?? 0;
    }
    return 0;
  }

  static IconData _getIconFromString(String? iconString) {
    switch (iconString?.toLowerCase()) {
      case 'motorcycle':
        return Icons.motorcycle;
      case 'restaurant':
        return Icons.restaurant;
      case 'local_shipping':
        return Icons.local_shipping;
      case 'shopping_bag':
        return Icons.shopping_bag;
      default:
        return Icons.motorcycle;
    }
  }

  static Color _getColorFromString(String? colorString) {
    switch (colorString?.toLowerCase()) {
      case 'green':
        return Colors.green;
      case 'red':
        return Colors.red;
      case 'blue':
        return Colors.blue;
      case 'purple':
        return Colors.purple;
      case 'orange':
        return Colors.orange;
      default:
        return Colors.green;
    }
  }
}
