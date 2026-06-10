import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/message.dart';

class AttachmentViewer extends StatefulWidget {
  final Attachment attachment;

  const AttachmentViewer({super.key, required this.attachment});

  @override
  State<AttachmentViewer> createState() => _AttachmentViewerState();
}

class _AttachmentViewerState extends State<AttachmentViewer> {
  VideoPlayerController? _videoController;
  AudioPlayer? _audioPlayer;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  void _initPlayer() {
    final type = widget.attachment.type;
    if (type == 'video') {
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(widget.attachment.url),
      );
      _videoController!.initialize().then((_) {
        if (mounted) {
          setState(() => _isInitialized = true);
        }
      });
    } else if (type == 'audio') {
      _audioPlayer = AudioPlayer();
      _audioPlayer!.setSourceUrl(widget.attachment.url);
      _audioPlayer!.onPositionChanged.listen((pos) {
        if (mounted) setState(() => _position = pos);
      });
      _audioPlayer!.onDurationChanged.listen((dur) {
        if (mounted) setState(() => _duration = dur);
      });
      _audioPlayer!.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _isPlaying = false);
      });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _audioPlayer?.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    if (_videoController != null && _isInitialized) {
      setState(() {
        if (_videoController!.value.isPlaying) {
          _videoController!.pause();
        } else {
          _videoController!.play();
        }
      });
    } else if (_audioPlayer != null) {
      if (_isPlaying) {
        _audioPlayer!.pause();
      } else {
        _audioPlayer!.resume();
      }
      setState(() => _isPlaying = !_isPlaying);
    }
  }

  String _formatDuration(Duration d) {
    final min = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$min:$sec';
  }

  /// Открывает fullscreen просмотр фото с zoom (InteractiveViewer)
  void _openFullscreenImage(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullscreenImagePage(url: widget.attachment.url),
      ),
    );
  }

  /// Открывает fullscreen просмотр видео
  void _openFullscreenVideo(BuildContext context) {
    if (_videoController == null || !_isInitialized) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullscreenVideoPage(controller: _videoController!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.attachment.type;
    final fileName = widget.attachment.fileName;

    switch (type) {
      case 'image':
        return _buildImage(context);
      case 'video':
        return _buildVideo(context);
      case 'audio':
        return _buildAudio();
      case 'document':
      default:
        return _buildDocument(fileName);
    }
  }

  Widget _buildImage(BuildContext context) {
    return GestureDetector(
      onTap: () => _openFullscreenImage(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          widget.attachment.url,
          fit: BoxFit.cover,
          width: 200,
          height: 150,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Container(
              width: 200,
              height: 150,
              color: Colors.grey[200],
              child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return Container(
              width: 200,
              height: 150,
              color: Colors.grey[200],
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.broken_image, color: Colors.grey, size: 32),
                  SizedBox(height: 4),
                  Text('Ошибка загрузки', style: TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildVideo(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (_isInitialized) {
          _openFullscreenVideo(context);
        } else {
          _togglePlayPause();
        }
      },
      child: SizedBox(
        width: 200,
        height: 150,
        child: Stack(
          alignment: Alignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _isInitialized
                  ? FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        width: _videoController!.value.size.width,
                        height: _videoController!.value.size.height,
                        child: VideoPlayer(_videoController!),
                      ),
                    )
                  : Container(
                      width: 200,
                      height: 150,
                      color: Colors.grey[300],
                      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
            ),
            Container(
              decoration: const BoxDecoration(
                color: Colors.black26,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(8),
              child: Icon(
                _isInitialized && _videoController!.value.isPlaying
                    ? Icons.pause
                    : Icons.play_arrow,
                color: Colors.white,
                size: 32,
              ),
            ),
            if (_isInitialized)
              Positioned(
                bottom: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(
                    Icons.fullscreen,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudio() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
              color: Theme.of(context).colorScheme.primary,
              size: 28,
            ),
            onPressed: _togglePlayPause,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          const SizedBox(width: 4),
          Text(
            _duration != Duration.zero
                ? '${_formatDuration(_position)} / ${_formatDuration(_duration)}'
                : '00:00 / 00:00',
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.volume_up, size: 16, color: Colors.grey),
        ],
      ),
    );
  }

  Widget _buildDocument(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    IconData icon;
    Color color;

    switch (extension) {
      case 'pdf':
        icon = Icons.picture_as_pdf;
        color = Colors.red;
        break;
      case 'doc':
      case 'docx':
        icon = Icons.description;
        color = Colors.blue;
        break;
      case 'xls':
      case 'xlsx':
        icon = Icons.table_chart;
        color = Colors.green;
        break;
      case 'zip':
      case 'rar':
        icon = Icons.folder_zip;
        color = Colors.orange;
        break;
      default:
        icon = Icons.insert_drive_file;
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              fileName,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Fullscreen Image Page с InteractiveViewer (zoom пальцами)
// ============================================================
class _FullscreenImagePage extends StatelessWidget {
  final String url;

  const _FullscreenImagePage({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        child: Center(
          child: Image.network(
            url,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.broken_image, color: Colors.white54, size: 64),
                  SizedBox(height: 16),
                  Text(
                    'Не удалось загрузить изображение',
                    style: TextStyle(color: Colors.white54, fontSize: 16),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Fullscreen Video Page
// ============================================================
class _FullscreenVideoPage extends StatefulWidget {
  final VideoPlayerController controller;

  const _FullscreenVideoPage({required this.controller});

  @override
  State<_FullscreenVideoPage> createState() => _FullscreenVideoPageState();
}

class _FullscreenVideoPageState extends State<_FullscreenVideoPage> {
  late VideoPlayerController _controller;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller;
    _controller.addListener(_onControllerUpdate);
    // Автостарт при открытии fullscreen
    if (!_controller.value.isPlaying) {
      _controller.play();
    }
    setState(() => _isPlaying = _controller.value.isPlaying);
  }

  void _onControllerUpdate() {
    if (mounted) {
      setState(() {
        _isPlaying = _controller.value.isPlaying;
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerUpdate);
    // Не диспозим controller — он принадлежит AttachmentViewer
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              _isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
            ),
            onPressed: () {
              if (_isPlaying) {
                _controller.pause();
              } else {
                _controller.play();
              }
            },
          ),
        ],
      ),
      body: Center(
        child: _controller.value.isInitialized
            ? InteractiveViewer(
                minScale: 0.5,
                maxScale: 3.0,
                child: AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: VideoPlayer(_controller),
                ),
              )
            : const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
      ),
      // Тап по экрану — play/pause
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (_isPlaying) {
            _controller.pause();
          } else {
            _controller.play();
          }
        },
        backgroundColor: Colors.white24,
        child: Icon(
          _isPlaying ? Icons.pause : Icons.play_arrow,
          color: Colors.white,
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}