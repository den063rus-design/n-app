import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
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
  bool _isSending = false;
  bool _isSendingText = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMessages();
    });
    // Слушаем изменения текста для обновления кнопки отправки
    _messageController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageController.removeListener(_onTextChanged);
    _messageController.dispose();
    _scrollController.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    // Перестраиваем UI при изменении текста (для кнопки отправки)
    setState(() {});
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

  Future<void> _sendTextMessage() async {
    if (_isSendingText) return;
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _isSendingText = true;
    final chat = context.read<ChatProvider>();
    final auth = context.read<AuthProvider>();

    if (auth.currentUser == null) {
      _isSendingText = false;
      return;
    }

    try {
      if (widget.isAdmin) {
        await chat.sendMessage(text, widget.userId);
      } else {
        await chat.sendMessage(text, null);
      }
      _messageController.clear();
      _scrollToBottom();
    } finally {
      _isSendingText = false;
    }
  }

  Future<void> _pickImageFromSource(ImageSource source) async {
    // Запрашиваем разрешение в зависимости от источника
    if (source == ImageSource.camera) {
      final status = await Permission.camera.request();
      if (status.isPermanentlyDenied) {
        _showPermissionDenied('камеру');
        return;
      }
      if (!status.isGranted) {
        _showError('Нет разрешения на использование камеры');
        return;
      }
    } else {
      // Для Android 13+ (API 33+) нужно разрешение READ_MEDIA_IMAGES
      // Для Android < 13 нужно READ_EXTERNAL_STORAGE
      Permission photosPermission;
      try {
        // Проверяем, доступно ли Permission.photos (Android 13+)
        final photosStatus = await Permission.photos.status;
        photosPermission = Permission.photos;
      } catch (_) {
        // Permission.photos не доступен (Android < 13)
        photosPermission = Permission.storage;
      }

      final status = await photosPermission.request();
      if (status.isPermanentlyDenied) {
        _showPermissionDenied('галерею');
        return;
      }
      if (!status.isGranted) {
        _showError('Нет разрешения на доступ к галерее');
        return;
      }
    }

    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 80,
      );
      if (image != null) {
        await _sendFile(image.path, 'image');
      } else {
        _showError('Фото не выбрано');
      }
    } catch (e) {
      _showError('Ошибка выбора фото: $e');
    }
  }

  void _showImageSourcePicker() {
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
                'Выберите источник',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _attachmentButton(
                    icon: Icons.photo_library,
                    label: 'Галерея',
                    color: Colors.blue,
                    onTap: () {
                      Navigator.pop(context);
                      _pickImageFromSource(ImageSource.gallery);
                    },
                  ),
                  _attachmentButton(
                    icon: Icons.camera_alt,
                    label: 'Камера',
                    color: Colors.teal,
                    onTap: () {
                      Navigator.pop(context);
                      _pickImageFromSource(ImageSource.camera);
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

  Future<void> _pickVideo() async {
    // Запрашиваем разрешение на галерею для видео
    Permission photosPermission;
    try {
      await Permission.photos.status;
      photosPermission = Permission.photos;
    } catch (_) {
      photosPermission = Permission.storage;
    }

    final status = await photosPermission.request();
    if (status.isPermanentlyDenied) {
      _showPermissionDenied('галерею');
      return;
    }
    if (!status.isGranted) {
      _showError('Нет разрешения на доступ к галерее');
      return;
    }

    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
      );
      if (video != null) {
        await _sendFile(video.path, 'video');
      }
    } catch (e) {
      _showError('Ошибка выбора видео: $e');
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
      // Явно запрашиваем разрешение на микрофон через permission_handler
      final micStatus = await Permission.microphone.request();
      if (micStatus.isPermanentlyDenied) {
        _showPermissionDenied('микрофон');
        return;
      }
      if (!micStatus.isGranted) {
        _showError('Нет разрешения на запись аудио');
        return;
      }

      final path =
          '${Directory.systemTemp.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
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
      _showError('Ошибка начала записи: $e');
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

  Future<void> _cancelRecording() async {
    try {
      await _audioRecorder.stop();
    } catch (_) {}
    setState(() {
      _isRecording = false;
      _recordingPath = null;
    });
  }

  Future<void> _sendFile(String filePath, String fileType,
      {String? fileName}) async {
    if (_isSending) return;
    _isSending = true;

    final chat = context.read<ChatProvider>();
    final auth = context.read<AuthProvider>();
    if (auth.currentUser == null) return;

    try {
      final result = await chat.uploadFile(filePath);
      if (result != null) {
        final fileKey = result['key'] as String;
        final files = [
          {
            'key': fileKey,
            'originalName':
                result['originalName'] as String? ?? fileName ?? fileKey,
            'fileSize': result['fileSize'] as int? ?? 0,
            'mimeType':
                result['mimeType'] as String? ?? 'application/octet-stream',
          },
        ];
        if (widget.isAdmin) {
          await chat.sendMessage('', widget.userId, files: files);
        } else {
          await chat.sendMessage('', null, files: files);
        }
        _scrollToBottom();
      } else {
        _showError('Не удалось загрузить файл на сервер');
      }
    } catch (e) {
      _showError('Ошибка отправки файла: $e');
    } finally {
      _isSending = false;
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showPermissionDenied(String permissionName) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Доступ запрещён'),
        content: Text(
            'Разрешение на $permissionName было отклонено навсегда. Пожалуйста, включите его в настройках приложения.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('Открыть настройки'),
          ),
        ],
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
                      _showImageSourcePicker();
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
                              final isMine =
                                  message.senderId == auth.currentUser?.id;

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
                                onEdit: isMine
                                    ? (newText) async {
                                        await context
                                            .read<ChatProvider>()
                                            .updateMessage(
                                              message.id,
                                              newText,
                                            );
                                      }
                                    : null,
                              );
                            },
                          ),
              ),
              // Поле ввода
              _buildInputBar(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInputBar() {
    // Режим записи голосового — показываем шкалу как в Telegram
    if (_isRecording) {
      return SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
              // Кнопка отмены записи
              IconButton(
                icon: const Icon(Icons.close),
                color: Colors.red,
                onPressed: _cancelRecording,
              ),
              const SizedBox(width: 8),
              // Анимированная шкала записи
              Expanded(
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Row(
                    children: [
                      SizedBox(width: 16),
                      Icon(Icons.mic, color: Colors.red, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Запись голосового сообщения...',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Кнопка отправки записи
              IconButton(
                icon: const Icon(Icons.send),
                color: Colors.red,
                onPressed: _stopRecording,
              ),
            ],
          ),
        ),
      );
    }

    // Обычный режим ввода
    final hasText = _messageController.text.isNotEmpty;

    return SafeArea(
      top: false,
      child: Container(
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
                  hintText: 'Введите сообщение...',
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
            // Кнопка микрофона (когда нет текста) или отправки (когда есть текст)
            if (hasText)
              IconButton(
                icon: const Icon(Icons.send),
                color: Theme.of(context).colorScheme.primary,
                onPressed: _sendTextMessage,
              )
            else
              IconButton(
                icon: const Icon(Icons.mic),
                color: Colors.grey,
                onPressed: _toggleRecording,
              ),
          ],
        ),
      ),
    );
  }
}
