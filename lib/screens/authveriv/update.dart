// lib/screens/force_update_screen.dart
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:install_plugin/install_plugin.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:app_settings/app_settings.dart';
import 'package:dio/dio.dart';
import 'dart:io';

class ForceUpdateScreen extends StatefulWidget {
  final String updateMessage;
  final String apkUrl;
  final String currentAppVersion;
  final String serverAppVersion;

  const ForceUpdateScreen({
    Key? key,
    required this.updateMessage,
    required this.apkUrl,
    required this.currentAppVersion,
    required this.serverAppVersion,
  }) : super(key: key);

  @override
  State<ForceUpdateScreen> createState() => _ForceUpdateScreenState();
}

class _ForceUpdateScreenState extends State<ForceUpdateScreen> {
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.error, color: Colors.red.shade600, size: 24),
              const SizedBox(width: 8),
              const Text('Error'),
            ],
          ),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _downloadAndInstallApk(String apkUrl) async {
    final installStatus = await Permission.requestInstallPackages.status;

    if (!installStatus.isGranted) {
      _showInstallPermissionDialog(context, apkUrl);
      return;
    }

    final dir = await getExternalStorageDirectory();
    if (dir == null) {
      print("Gagal mendapatkan direktori penyimpanan eksternal");
      _showErrorDialog('Gagal menyiapkan lokasi penyimpanan untuk pembaruan.');
      return;
    }
    final filePath = '${dir.path}/lhokride-latest.apk';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return _buildDownloadDialog();
      },
    );

    try {
      final dio = Dio();
      await dio.download(
        apkUrl,
        filePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final progress = received / total;
            print("Download progress: ${(progress * 100).toStringAsFixed(0)}%");
          }
        },
      );

      if (mounted) {
        Navigator.of(context).pop(); // Dismiss download dialog
      }

      _showInstallingDialog();

      await InstallPlugin.installApk(filePath);
    } catch (e) {
      print("Gagal mengunduh/install: $e");
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(); // Dismiss any open dialog
      }
      _showErrorDialog('Gagal mengunduh atau menginstal pembaruan: $e');
    }
  }

  void _showInstallPermissionDialog(BuildContext context, String apkUrl) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Izin Instalasi Diperlukan'),
          content: const Text(
            'Untuk menginstal pembaruan, Anda perlu memberikan izin "Instal aplikasi tidak dikenal" untuk aplikasi ini di Pengaturan. Setelah memberikan izin, silakan coba lagi.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                exit(0);
              },
              child: const Text('Tutup Aplikasi'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await AppSettings.openAppSettings(
                  type: AppSettingsType.security,
                );
              },
              child: const Text('Buka Pengaturan'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDownloadDialog() {
    return PopScope(
      canPop: false,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(35),
                ),
                child: Icon(
                  Icons.file_download,
                  size: 35,
                  color: Colors.blue.shade600,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Mengunduh Pembaruan',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Mohon tunggu, sedang mengunduh file pembaruan...',
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              Container(
                width: double.infinity,
                height: 6,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.blue.shade600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Jangan tutup aplikasi selama proses ini berlangsung',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade500,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showInstallingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return PopScope(
          canPop: false,
          child: Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            elevation: 0,
            backgroundColor: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(35),
                    ),
                    child: Icon(
                      Icons.install_mobile,
                      size: 35,
                      color: Colors.green.shade600,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Menginstal Pembaruan',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Sedang menginstal pembaruan aplikasi...',
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.green.shade600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Ikuti petunjuk instalasi yang muncul',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade500,
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.orange.shade50,
                Colors.white,
                Colors.orange.shade50
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(
                        color: Colors.orange.shade200,
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      Icons.system_update_alt,
                      size: 50,
                      color: Colors.orange.shade600,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Pembaruan Aplikasi Diperlukan',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.updateMessage,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade600,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Versi Saat Ini: ${widget.currentAppVersion}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(Icons.arrow_right_alt,
                          size: 20, color: Colors.grey.shade500),
                      const SizedBox(width: 10),
                      Text(
                        'Versi Terbaru: ${widget.serverAppVersion}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () {
                        _downloadAndInstallApk(widget.apkUrl);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade600,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: const Text(
                        'Perbarui Sekarang',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton(
                      onPressed: () {
                        exit(0); // Force exit the app
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey.shade600,
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Keluar dari Aplikasi',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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