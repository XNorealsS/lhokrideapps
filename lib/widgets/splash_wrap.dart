import 'package:flutter/material.dart';

class SplashWrapperPage extends StatefulWidget {
  final Widget targetPage;
  final Duration duration;

  const SplashWrapperPage({
    Key? key,
    required this.targetPage,
    this.duration = const Duration(seconds: 1), // durasi singkat 1 detik
  }) : super(key: key);

  @override
  State<SplashWrapperPage> createState() => _SplashWrapperPageState();
}

class _SplashWrapperPageState extends State<SplashWrapperPage> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.duration, () {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    });
  }

@override
Widget build(BuildContext context) {
  return _loading
      ? Scaffold(
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.orange[600]!,
                  Colors.orange[400]!,
                ],
              ),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.motorcycle,
                    size: 80,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'LhokRide+',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(
                          blurRadius: 6,
                          color: Colors.black54,
                          offset: Offset(2, 2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                ],
              ),
            ),
            ),
          )
        : widget.targetPage;
  }
}
