import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:correctv1/services/exercise_video_service.dart';
import 'package:correctv1/theme/app_theme.dart';

String _fmtDuration(int sec) =>
    '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';

class ExerciseVideosPage extends StatefulWidget {
  const ExerciseVideosPage({super.key});

  @override
  State<ExerciseVideosPage> createState() => _ExerciseVideosPageState();
}

class _ExerciseVideosPageState extends State<ExerciseVideosPage> {
  final _service = ExerciseVideoService.instance;
  List<ExerciseVideo>? _videos;
  Object? _error;
  String? _category;
  final Set<String> _downloaded = {};
  final Map<String, double> _progress = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final videos = await _service.fetchVideos();
      final downloaded = <String>{};
      for (final v in videos) {
        if (await _service.localPath(v) != null) downloaded.add(v.id);
      }
      if (!mounted) return;
      setState(() {
        _videos = videos;
        _downloaded
          ..clear()
          ..addAll(downloaded);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _download(ExerciseVideo v) async {
    setState(() => _progress[v.id] = 0);
    try {
      await _service.download(
        v,
        onProgress: (p) {
          if (mounted) setState(() => _progress[v.id] = p);
        },
      );
      if (mounted) setState(() => _downloaded.add(v.id));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download failed. Check your internet.')),
        );
      }
    } finally {
      if (mounted) setState(() => _progress.remove(v.id));
    }
  }

  Future<void> _confirmDelete(ExerciseVideo v) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove download?'),
        content: Text('"${v.title}" will be removed from this phone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _service.delete(v);
    if (mounted) setState(() => _downloaded.remove(v.id));
  }

  Future<void> _play(ExerciseVideo v) async {
    final local = await _service.localPath(v);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExerciseVideoPlayerPage(
          title: v.title,
          localPath: local,
          url: local == null ? _service.publicUrl(v.videoPath) : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Exercise Videos'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: BoxDecoration(
          gradient: AppTheme.pageBackgroundGradientFor(context),
        ),
        child: SafeArea(child: _body(scheme)),
      ),
    );
  }

  Widget _body(ColorScheme scheme) {
    if (_error != null && _videos == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Could not load videos',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    final videos = _videos;
    if (videos == null) return const Center(child: CircularProgressIndicator());
    if (videos.isEmpty) {
      return Center(
        child: Text(
          'No videos yet',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }

    final categories = {
      for (final v in videos)
        if (v.category.isNotEmpty) v.category,
    }.toList();
    final shown = _category == null
        ? videos
        : videos.where((v) => v.category == _category).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (categories.length > 1)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final c in [null, ...categories])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(c ?? 'All'),
                        selected: _category == c,
                        onSelected: (_) => setState(() => _category = c),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          for (final v in shown) _tile(v, scheme),
        ],
      ),
    );
  }

  Widget _tile(ExerciseVideo v, ColorScheme scheme) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final progress = _progress[v.id];
    final downloaded = _downloaded.contains(v.id);

    Widget action;
    if (progress != null) {
      action = SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
          value: progress > 0 ? progress : null,
          strokeWidth: 3,
        ),
      );
    } else if (downloaded) {
      action = IconButton(
        tooltip: 'Remove download',
        icon: const Icon(Icons.download_done_rounded, color: Color(0xFF34D399)),
        onPressed: () => _confirmDelete(v),
      );
    } else {
      action = IconButton(
        tooltip: 'Download',
        icon: Icon(Icons.download_rounded, color: scheme.onSurfaceVariant),
        onPressed: () => _download(v),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: isDark ? const Color(0xFF0D1117) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _play(v),
          onLongPress: downloaded ? () => _confirmDelete(v) : null,
          child: Row(
            children: [
              SizedBox(
                width: 120,
                height: 80,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (v.thumbPath != null)
                      Image.network(
                        ExerciseVideoService.instance.publicUrl(v.thumbPath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            Container(color: const Color(0xFF0D1A1D)),
                      )
                    else
                      Container(color: const Color(0xFF0D1A1D)),
                    const Center(
                      child: Icon(
                        Icons.play_circle_fill_rounded,
                        color: Colors.white70,
                        size: 34,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      v.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (v.durationSec > 0) _fmtDuration(v.durationSec),
                        if (v.category.isNotEmpty) v.category,
                      ].join(' · '),
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(padding: const EdgeInsets.only(right: 8), child: action),
            ],
          ),
        ),
      ),
    );
  }
}

/// Plays a downloaded file when [localPath] is set, otherwise streams [url].
class ExerciseVideoPlayerPage extends StatefulWidget {
  final String title;
  final String? localPath;
  final String? url;

  const ExerciseVideoPlayerPage({
    super.key,
    required this.title,
    this.localPath,
    this.url,
  });

  @override
  State<ExerciseVideoPlayerPage> createState() =>
      _ExerciseVideoPlayerPageState();
}

class _ExerciseVideoPlayerPageState extends State<ExerciseVideoPlayerPage> {
  late final VideoPlayerController _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.localPath != null
        ? VideoPlayerController.file(File(widget.localPath!))
        : VideoPlayerController.networkUrl(Uri.parse(widget.url!));
    _controller.addListener(_onTick);
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      _controller.play();
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
    WakelockPlus.enable();
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _controller.removeListener(_onTick);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = _controller.value;
    return Scaffold(
      backgroundColor: const Color(0xFF0D1A1D),
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: _failed
            ? const Text(
                'Could not play this video',
                style: TextStyle(color: Colors.white70),
              )
            : !value.isInitialized
                ? const CircularProgressIndicator()
                : GestureDetector(
                    onTap: () =>
                        value.isPlaying ? _controller.pause() : _controller.play(),
                    child: AspectRatio(
                      aspectRatio: value.aspectRatio,
                      child: Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          VideoPlayer(_controller),
                          if (!value.isPlaying)
                            const Center(
                              child: Icon(
                                Icons.play_circle_fill_rounded,
                                color: Colors.white,
                                size: 64,
                              ),
                            ),
                          VideoProgressIndicator(
                            _controller,
                            allowScrubbing: true,
                            colors: const VideoProgressColors(
                              playedColor: Color(0xFFEC4899),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }
}
