import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../widgets/bottom_navigation.dart';

class WebviewPage extends StatefulWidget {
  final String url;
  final String? Title;

  const WebviewPage({
    super.key,
    required this.url,
    this.Title, // opsional, tidak pakai "required"
  });

  @override
  State<WebviewPage> createState() => _WebviewPageState();
}

class _WebviewPageState extends State<WebviewPage> {
  late final WebViewController _controller;
  final _storage = const FlutterSecureStorage();
  String _userRole = 'guest';
  bool _isLoading = true; // Menambahkan state loading

  @override
  void initState() {
    super.initState();
    _initWebView();
    _loadUserRole();
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
          },
          onWebResourceError: (WebResourceError error) {
            setState(() {
              _isLoading = false;
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _loadUserRole() async {
    final role = await _storage.read(key: 'role');
    if (role != null) {
      setState(() {
        _userRole = role;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageWithBottomNav(
      activeTab: 'home',
      userRole: _userRole,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.Title ?? 'LhokRide Browser'),
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_isLoading)
              const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'Loading...',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
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