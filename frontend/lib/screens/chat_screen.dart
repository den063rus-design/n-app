import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../models/message.dart';
import '../widgets/message_bubble.dart';
import 'call_screen.dart';

class ChatScreen extends StatefulWidget {
  final int userId;
  final String userName;
  final bool isAdmin;
  final bool isOnline;

  const ChatScreen({
    super.key,
    required this.userId,
    required this.userName,
    this.isAdmin = false,
    this.isOnline = false,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _imagePicker = ImagePicker();
  final _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  String? _recordingPath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMessages();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    _scrollController.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadMessages();
    }
  }

  void _loadMessages() {
    final chat = context.read<ChatProvider>();
    if (widget.isAdmin) {
      chat.loadUserMessages(widget.userId);
    } else {
      chat.loadMessages();
    }
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

  void _sendTextMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final chat = context.read<ChatProvider>();
    final auth = context.read<AuthProvider>();

    if (auth.currentUser == null) return;

    if (widget.isAdmin) {
      chat.sendMessage(text, widget.userId);
    } else {
      chat.sendMessage(text, null);
    }

    _messageController.clear();
    _scrollToBottom();
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );
      if (image != null) {
        await _sendFile(image.path, 'image');
      }
    } catch (e) {
      _showError('Ошибка выбора фото');
    }
  }

  Future<void> _pickVideo() async {
    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
      );
      if (video != null) {
        await _sendFile(video.path, 'video');
      }
    } catch (e) {
      _showError('Ошибка выбора видео');
    }
  }

  Future<void> _pickDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles();
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final fileName = result.files.single.name;
        await _sendFile(path, 'document', fileName: fileName);
      }
    } catch (e) {
      _showError('Ошибка выбора документа');
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        _showError('Нет разрешения на запись аудио');
        return;
      }

      final path = '${Directory.systemTemp.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );

      setState(() {
        _isRecording = true;
        _recordingPath = path;
      });
    } catch (e) {
      _showError('Ошибка начала записи');
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      if (path != null) {
        setState(() {
          _isRecording = false;
          _recordingPath = path;
        });
        await _sendFile(path, 'audio');
      }
    } catch (e) {
      setState(() => _isRecording = false);
      _showError('Ошибка остановки записи');
    }
  }

  Future<void> _sendFile(String filePath, String fileType, {String? fileName}) async {
    final chat = context.read<ChatProvider>();
    final auth = context.read<AuthProvider>();
    if (auth.currentUser == null) return;

    try {
      final fileUrl = await chat.uploadFile(filePath);
      if (fileUrl != null) {
        if (widget.isAdmin) {
          await chat.sendMessage('', widget.userId, attachments: [fileUrl]);
        } else {
          await chat.sendMessage('', null, attachments: [fileUrl]);
        }
        _scrollToBottom();
      }
    } catch (e) {
      _showError('Ошибка отправки файла');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showAttachmentSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Прикрепить файл',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _attachmentButton(
                    icon: Icons.photo,
                    label: 'Фото',
                    color: Colors.blue,
                    onTap: () {
                      Navigator.pop(context);
                      _pickImage();
                    },
                  ),
                  _attachmentButton(
                    icon: Icons.videocam,
                    label: 'Видео',
                    color: Colors.green,
                    onTap: () {
                      Navigator.pop(context);
                      _pickVideo();
                    },
                  ),
                  _attachmentButton(
                    icon: Icons.description,
                    label: 'Документ',
                    color: Colors.orange,
                    onTap: () {
                      Navigator.pop(context);
                      _pickDocument();
                    },
                  ),
                  _attachmentButton(
                    icon: Icons.mic,
                    label: 'Голосовое',
                    color: Colors.red,
                    onTap: () {
                      Navigator.pop(context);
                      _toggleRecording();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attachmentButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  void _confirmDeleteMessage(Message message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить сообщение'),
        content: const Text('Вы уверены, что хотите удалить это сообщение?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<ChatProvider>().deleteMessage(message.id);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }

  /// Определяет цвет индикатора онлайн-статуса
  Color _onlineStatusColor(bool isOnline, String status) {
    if (status == 'BLOCKED') return Colors.red;
    return isOnline ? Colors.green : Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Consumer<ChatProvider>(
          builder: (context, chat, _) {
            // Для admin — берём статус из selectedUser (обновляется через WebSocket)
            // Для user — используем widget.isOnline (передаётся при навигации)
            bool isOnline;
            String status;
            if (widget.isAdmin && chat.selectedUser != null) {
              isOnline = chat.selectedUser!.isOnline;
              status = chat.selectedUser!.status;
            } else {
              isOnline = widget.isOnline;
              status = 'ACTIVE';
            }

            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _onlineStatusColor(isOnline, status),
                  ),
                ),
                const SizedBox(width: 8),
                Text(widget.userName),
              ],
            );
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.videocam),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CallScreen(
                    userId: widget.userId,
                    userName: widget.userName,
                    isIncoming: false,
                  ),
                ),
              );
            },
          ),
          if (!widget.isAdmin)
            IconButton(
              icon: const Icon(Icons.exit_to_app),
              onPressed: () {
                context.read<AuthProvider>().logout();
                Navigator.pushReplacementNamed(context, '/login');
              },
            ),
        ],
      ),
      body: Consumer2<ChatProvider, AuthProvider>(
        builder: (context, chat, auth, _) {
          return Column(
            children: [
              // Сообщения
              Expanded(
                child: chat.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : chat.messages.isEmpty
                        ? const Center(
                            child: Text(
                              'Нет сообщений. Напишите что-нибудь!',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(12),
                            itemCount: chat.messages.length,
                            itemBuilder: (context, index) {
                              final message = chat.messages[index];
                              final isMine = message.senderId == auth.currentUser?.id;

                              // Отмечаем как прочитанное, если сообщение не наше и статус SENT
                              if (!isMine && message.status == 'SENT') {
                                chat.markAsRead(message.id);
                              }

                              return MessageBubble(
                                message: message,
                                isAdmin: widget.isAdmin,
                                isMine: isMine,
                                onDelete: widget.isAdmin
                                    ? () => _confirmDeleteMessage(message)
                                    : null,
                              );
                            },
                          ),
              ),
              // Индикатор записи
              if (_isRecording)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  color: Colors.red[50],
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.red,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Запись голосового сообщения...',
                        style: TextStyle(color: Colors.red),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: _stopRecording,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Стоп',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              // Поле ввода
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withValues(alpha: 0.3),
                      blurRadius: 4,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Кнопка прикрепления
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      color: Theme.of(context).colorScheme.primary,
                      onPressed: _showAttachmentSheet,
                    ),
                    const SizedBox(width: 4),
                    // Текстовое поле
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        decoration: InputDecoration(
                          hintText: _isRecording
                              ? 'Идёт запись...'
                              : 'Введите сообщение...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          filled: true,
                          fillColor: Colors.grey[100],
                        ),
                        onSubmitted: (_) => _sendTextMessage(),
                        textInputAction: TextInputAction.send,
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Кнопка голосового сообщения / отправки
                    if (_messageController.text.isEmpty)
                      IconButton(
                        icon: Icon(
                          _isRecording ? Icons.stop_circle : Icons.mic,
                          color: _isRecording ? Colors.red : Colors.grey,
                        ),
                        onPressed: _toggleRecording,
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.send),
                        color: Theme.of(context).colorScheme.primary,
                        onPressed: _sendTextMessage,
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}