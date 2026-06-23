import 'dart:async';
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
  Future<void> _openFullscreenVideo(BuildContext context) async {
    if (_videoController == null || !_isInitialized) return;
    final currentPosition = _videoController!.value.position;
    _videoController!.pause();
    final returnedPosition = await Navigator.of(context).push<Duration>(
      MaterialPageRoute(
        builder: (_) => _FullscreenVideoPage(
          url: widget.attachment.url,
          initialPosition: currentPosition,
        ),
      ),
    );
    if (!mounted || _videoController == null) return;
    final seekTo = returnedPosition ?? currentPosition;
    if (seekTo > Duration.zero) {
      _videoController!.seekTo(seekTo);
    }
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
  final String url;
  final Duration initialPosition;

  const _FullscreenVideoPage({
    required this.url,
    required this.initialPosition,
  });

  @override
  State<_FullscreenVideoPage> createState() => _FullscreenVideoPageState();
}

class _FullscreenVideoPageState extends State<_FullscreenVideoPage>
    with WidgetsBindingObserver {
  late VideoPlayerController _controller;
  bool _isPlaying = false;
  bool _showOverlay = true;
  Timer? _overlayTimer;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isScrubbing = false;
  double _scrubPositionMs = 0;
  bool _wasPlayingBeforePause = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.url),
    );
    _controller.addListener(_onControllerUpdate);
    _initFullscreenController();
  }

  Future<void> _initFullscreenController() async {
    try {
      await _controller.initialize();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    if (widget.initialPosition > Duration.zero) {
      try {
        await _controller.seekTo(widget.initialPosition);
      } catch (_) {}
    }
    try {
      await _controller.play();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _isPlaying = _controller.value.isPlaying);
    _startOverlayTimer();
  }

  void _startOverlayTimer() {
    _overlayTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showOverlay = false);
    });
  }

  void _onControllerUpdate() {
    if (mounted) {
      setState(() {
        _isPlaying = _controller.value.isPlaying;
        _position = _controller.value.position;
        _duration = _controller.value.duration;
      });
    }
  }

  void _handleTap() {
    if (_isPlaying) {
      try {
        _controller.pause();
      } catch (_) {}
      setState(() => _showOverlay = true);
    } else {
      try {
        _controller.play();
      } catch (_) {}
      setState(() => _showOverlay = true);
      _startOverlayTimer();
    }
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      final h = d.inHours.toString().padLeft(2, '0');
      final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
      final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
      return '$h:$m:$s';
    }
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onControllerUpdate);
    try {
      _controller.pause();
    } catch (_) {}
    _controller.dispose();
    _overlayTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _wasPlayingBeforePause = _isPlaying;
      if (_isPlaying) {
        try {
          _controller.pause();
        } catch (_) {}
      }
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _showOverlay = true);
      });
    } else if (state == AppLifecycleState.inactive) {
      _wasPlayingBeforePause = _isPlaying;
      if (_isPlaying) {
        try {
          _controller.pause();
        } catch (_) {}
      }
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _showOverlay = true);
      });
    } else if (state == AppLifecycleState.resumed) {
      if (!_controller.value.isInitialized) {
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() => _showOverlay = true);
        });
        return;
      }
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {});
      });
      if (_wasPlayingBeforePause) {
        try {
          _controller.play();
        } catch (_) {}
      }
      // Если было на паузе — оставляем на паузе, ничего не делаем
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaPadding = MediaQuery.of(context).padding;
    final durationMs = _duration.inMilliseconds.toDouble();
    final maxSl = durationMs > 0 ? durationMs : 1.0;
    final sliderValue = _isScrubbing
        ? _scrubPositionMs
        : _position.inMilliseconds.toDouble().clamp(0, maxSl).toDouble();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop(_position);
      },
      child: Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: GestureDetector(
        onTap: _handleTap,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Видео
            Center(
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
            // Центральный overlay play/pause
            if (_showOverlay)
              AnimatedOpacity(
                opacity: _showOverlay ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.black26,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Icon(
                    _isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 48,
                  ),
                ),
              ),
            // Нижняя панель управления
            if (_controller.value.isInitialized)
              Positioned(
                left: mediaPadding.left + 12,
                right: mediaPadding.right + 12,
                bottom: mediaPadding.bottom + 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Полоса перемотки — Slider
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 8,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 10,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 20,
                          ),
                          activeTrackColor: Colors.white,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: Colors.white,
                          overlayColor: Colors.white12,
                        ),
                        child: Slider(
                          min: 0,
                          max: maxSl,
                          value: sliderValue,
                          onChanged: (v) {
                            setState(() {
                              _isScrubbing = true;
                              _scrubPositionMs = v;
                            });
                          },
                          onChangeEnd: (v) {
                            try {
                              _controller.seekTo(
                                Duration(milliseconds: v.round()),
                              );
                            } catch (_) {}
                            setState(() => _isScrubbing = false);
                          },
                        ),
                      ),
                      // Время слева / длительность справа
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(
                              Duration(
                                milliseconds: sliderValue.round(),
                              ),
                            ),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            _formatDuration(_duration),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
  }
}