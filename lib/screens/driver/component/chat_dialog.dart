// chat_service.dart (formerly chat_dialog.dart)
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_database/firebase_database.dart'; // Needed for DatabaseEvent
import 'dart:async';
import 'package:lhokride/services/firebase_service.dart'; // Make sure this path is correct

// Renamed from ChatDialog to ChatService for better semantic
class ChatService {
  static final storage = FlutterSecureStorage();

  static Future<void> show(
    BuildContext context, {
    required String rideId,
    required String otherUserName,
    required String otherUserId,
    required bool isDriver,
  }) async {
    final userId = await storage.read(key: 'user_id');
    final userName = await storage.read(key: 'name');

    if (userId == null || userName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("User data tidak ditemukan. Mohon login kembali."),
        ),
      );
      return;
    }

    // Push ChatScreen onto the navigation stack
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => ChatScreen(
              rideId: rideId,
              currentUserId: userId,
              currentUserName: userName,
              otherUserName: otherUserName,
              otherUserId: otherUserId,
              isDriver: isDriver,
            ),
      ),
    );
  }
}

// The actual Chat UI and logic
class ChatScreen extends StatefulWidget {
  final String rideId;
  final String currentUserId;
  final String currentUserName;
  final String otherUserName;
  final String otherUserId;
  final bool isDriver;

  const ChatScreen({
    Key? key,
    required this.rideId,
    required this.currentUserId,
    required this.currentUserName,
    required this.otherUserName,
    required this.otherUserId,
    required this.isDriver,
  }) : super(key: key);

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  StreamSubscription<DatabaseEvent>? _messagesSubscription;
  bool _isTyping = false;
  bool _showQuickMessages = false;

  // WhatsApp-like colors - Friendly orange tones
  static const Color primaryOrange = Color(0xFFFF9800); // Warm orange
  static const Color lightOrange = Color(
    0xFFFFCC80,
  ); // Light orange for bubbles
  static const Color backgroundColor = Color(
    0xFFF5F5F5,
  ); // Light grey background
  static const Color myMessageColor = Color.fromARGB(
    255,
    255,
    230,
    139,
  ); // Light green for my messages
  static const Color otherMessageColor =
      Colors.white; // White for other messages

  // Quick message templates
  List<String> get driverQuickMessages => [
    "Saya sudah sampai di lokasi penjemputan",
    "Mohon tunggu sebentar, saya dalam perjalanan",
    "Tolong bagikan lokasi Anda yang tepat",
    "Saya akan tiba dalam 5 menit",
    "Terima kasih sudah menunggu",
    "Perjalanan dimulai, silakan pakai sabuk pengaman",
  ];

  List<String> get passengerQuickMessages => [
    "Saya sudah siap di lokasi penjemputan",
    "Mohon tunggu sebentar, saya sedang bersiap",
    "Dimana posisi Anda sekarang?",
    "Berapa lama lagi sampai?",
    "Terima kasih",
    "Tolong antarkan ke lokasi yang tepat",
  ];

  @override
  void initState() {
    super.initState();
    _startListeningToMessages();
    _messageController.addListener(_updateTypingStatus);
  }

  @override
  void dispose() {
    _messagesSubscription?.cancel();
    _messageController.removeListener(_updateTypingStatus);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _updateTypingStatus() {
    setState(() {
      _isTyping = _messageController.text.trim().isNotEmpty;
    });
  }

  void _startListeningToMessages() {
    _messagesSubscription = FirebaseService.listenToMessages(widget.rideId, (
      messages,
    ) {
      setState(() {
        _messages = messages;
      });
      _scrollToBottom();
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage([String? customMessage]) async {
    final text = customMessage ?? _messageController.text.trim();
    if (text.isNotEmpty) {
      try {
        await FirebaseService.sendMessage(
          widget.rideId,
          widget.currentUserId,
          widget.currentUserName,
          text,
        );
        if (customMessage == null) {
          _messageController.clear();
        }
        setState(() {
          _showQuickMessages = false;
        });
      } catch (e) {
        debugPrint('Failed to send message: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Gagal mengirim pesan."),
            backgroundColor: Colors.red.shade400,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(
            child:
                _messages.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8.0,
                        vertical: 4.0,
                      ),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final message = _messages[index];
                        final isMe =
                            message['senderId'] == widget.currentUserId;
                        return _buildMessageBubble(message, isMe);
                      },
                    ),
          ),
          if (_showQuickMessages) _buildQuickMessages(),
          _buildMessageInput(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 1,
      backgroundColor: primaryOrange,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          CircleAvatar(
            backgroundColor: lightOrange,
            radius: 18,
            child: Text(
              widget.otherUserName.isNotEmpty
                  ? widget.otherUserName[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.otherUserName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  widget.isDriver ? 'Penumpang' : 'Driver',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.more_vert, color: Colors.white),
          onPressed: () {
            // Add more options if needed
          },
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            "Belum ada pesan",
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Mulai percakapan dengan mengirim pesan",
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> message, bool isMe) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              backgroundColor: lightOrange,
              radius: 12,
              child: Text(
                message['senderName']?.isNotEmpty == true
                    ? message['senderName'][0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isMe ? myMessageColor : otherMessageColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft:
                      isMe
                          ? const Radius.circular(18)
                          : const Radius.circular(4),
                  bottomRight:
                      isMe
                          ? const Radius.circular(4)
                          : const Radius.circular(18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isMe)
                    Text(
                      message['senderName'] ?? 'Unknown',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: primaryOrange,
                        fontSize: 12,
                      ),
                    ),
                  if (!isMe) const SizedBox(height: 2),
                  Text(
                    message['message'] ?? 'Pesan kosong',
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 15,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatTimestamp(message['timestamp']),
                        style: TextStyle(color: Colors.grey[600], fontSize: 11),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.done_all, size: 14, color: Colors.grey[600]),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (isMe) const SizedBox(width: 20),
        ],
      ),
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp is int) {
      final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final now = DateTime.now();

      if (dateTime.day == now.day &&
          dateTime.month == now.month &&
          dateTime.year == now.year) {
        return "${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}";
      } else {
        return "${dateTime.day}/${dateTime.month} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}";
      }
    }
    return '';
  }

  Widget _buildQuickMessages() {
    final messages =
        widget.isDriver ? driverQuickMessages : passengerQuickMessages;

    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Text(
                  'Pesan Cepat',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() => _showQuickMessages = false),
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                return Container(
                  margin: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    label: Text(
                      messages[index],
                      style: const TextStyle(fontSize: 12),
                    ),
                    backgroundColor: lightOrange.withOpacity(0.2),
                    onPressed: () => _sendMessage(messages[index]),
                    labelStyle: TextStyle(color: primaryOrange),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            GestureDetector(
              onTap: () {
                setState(() {
                  _showQuickMessages = !_showQuickMessages;
                });
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: lightOrange.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _showQuickMessages ? Icons.keyboard_arrow_down : Icons.chat,
                  color: primaryOrange,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: TextField(
                  controller: _messageController,
                  minLines: 1,
                  maxLines: 4,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: "Ketik pesan...",
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    border: InputBorder.none,
                    hintStyle: TextStyle(color: Colors.grey[600], fontSize: 15),
                  ),
                  style: const TextStyle(fontSize: 15),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _isTyping ? () => _sendMessage() : null,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _isTyping ? primaryOrange : Colors.grey.shade400,
                  shape: BoxShape.circle,
                  boxShadow:
                      _isTyping
                          ? [
                            BoxShadow(
                              color: primaryOrange.withOpacity(0.3),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ]
                          : null,
                ),
                child: Icon(Icons.send, color: Colors.white, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
