import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/recording.dart';
import '../services/recording_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final _service = RecordingService();
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();

  List<Recording> _recordings = [];
  bool _isRecording = false;
  Duration _recDuration = Duration.zero;
  Timer? _recTimer;

  String? _playingId;
  bool _isPaused = false;
  Duration _playPos = Duration.zero;
  Duration _playDur = Duration.zero;

  late final AnimationController _waveAnim;
  late final AnimationController _pulseAnim;

  @override
  void initState() {
    super.initState();
    _waveAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pulseAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _player.onPositionChanged.listen((p) => setState(() => _playPos = p));
    _player.onDurationChanged.listen((d) => setState(() => _playDur = d));
    _player.onPlayerComplete.listen((_) => setState(() {
          _playingId = null;
          _isPaused = false;
          _playPos = Duration.zero;
        }));

    _loadRecordings();
  }

  Future<void> _loadRecordings() async {
    final list = await _service.load();
    setState(() => _recordings = list.reversed.toList());
  }

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) return;
    if (_playingId != null) {
      await _player.stop();
      setState(() {
        _playingId = null;
        _isPaused = false;
      });
    }
    final path = await _service.newFilePath();
    await _recorder.start(
      RecordConfig(encoder: kIsWeb ? AudioEncoder.opus : AudioEncoder.aacLc),
      path: path,
    );
    setState(() {
      _isRecording = true;
      _recDuration = Duration.zero;
    });
    _waveAnim.repeat();
    _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _recDuration += const Duration(seconds: 1));
    });
  }

  Future<void> _stopRecording() async {
    _recTimer?.cancel();
    _waveAnim.stop();
    _waveAnim.reset();
    final path = await _recorder.stop();
    if (path == null) {
      setState(() {
        _isRecording = false;
        _recDuration = Duration.zero;
      });
      return;
    }
    final n = _recordings.length + 1;
    final rec = Recording(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: 'Recording $n',
      filePath: path,
      createdAt: DateTime.now(),
      durationMs: _recDuration.inMilliseconds,
    );
    setState(() {
      _recordings.insert(0, rec);
      _isRecording = false;
      _recDuration = Duration.zero;
    });
    await _service.save(_recordings);
  }

  Future<void> _togglePlay(Recording rec) async {
    if (_playingId == rec.id) {
      if (_isPaused) {
        await _player.resume();
        setState(() => _isPaused = false);
      } else {
        await _player.pause();
        setState(() => _isPaused = true);
      }
    } else {
      await _player.stop();
      setState(() {
        _playingId = rec.id;
        _isPaused = false;
        _playPos = Duration.zero;
      });
      await _player.play(
        kIsWeb ? UrlSource(rec.filePath) : DeviceFileSource(rec.filePath),
      );
    }
  }

  Future<void> _rename(Recording rec) async {
    final ctrl = TextEditingController(text: rec.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Rename Recording',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Enter recording name',
            hintStyle: TextStyle(color: Color(0xFF666666)),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF444444)),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFE53935)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF888888))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save', style: TextStyle(color: Color(0xFFE53935))),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty && name != rec.name) {
      setState(() => rec.name = name);
      await _service.save(_recordings);
    }
  }

  Future<void> _delete(Recording rec) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Recording',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: Text(
          'Are you sure you want to delete "${rec.name}"?',
          style: const TextStyle(color: Color(0xFF888888)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF888888))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (_playingId == rec.id) {
      await _player.stop();
      setState(() {
        _playingId = null;
        _isPaused = false;
      });
    }
    await _service.deleteFile(rec.filePath);
    setState(() => _recordings.remove(rec));
    await _service.save(_recordings);
  }

  @override
  void dispose() {
    _recTimer?.cancel();
    _waveAnim.dispose();
    _pulseAnim.dispose();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  String _fmtDur(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _fmtDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dDay = DateTime(dt.year, dt.month, dt.day);
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final min = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final time = '$h:$min $ampm';
    if (dDay == today) return 'Today, $time';
    if (dDay == today.subtract(const Duration(days: 1))) return 'Yesterday, $time';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFE53935).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.mic, color: Color(0xFFE53935), size: 20),
            ),
            const SizedBox(width: 12),
            const Text(
              'Voice Vault',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _recordings.isEmpty ? _buildEmpty() : _buildList(),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: const BoxDecoration(
              color: Color(0xFF1A1A1A),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.mic_none, size: 52, color: Color(0xFF3A3A3A)),
          ),
          const SizedBox(height: 20),
          const Text(
            'No recordings yet',
            style: TextStyle(color: Color(0xFF888888), fontSize: 16),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tap the mic button to start recording',
            style: TextStyle(color: Color(0xFF555555), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: _recordings.length,
      itemBuilder: (_, i) {
        final rec = _recordings[i];
        final isActive = _playingId == rec.id;
        final isPlaying = isActive && !_isPaused;
        final progress = isActive && _playDur.inMilliseconds > 0
            ? (_playPos.inMilliseconds / _playDur.inMilliseconds).clamp(0.0, 1.0)
            : 0.0;
        return _RecordingCard(
          key: ValueKey(rec.id),
          rec: rec,
          isPlaying: isPlaying,
          isActive: isActive,
          progress: progress,
          durationLabel: isActive ? _fmtDur(_playPos) : rec.formattedDuration,
          dateLabel: _fmtDate(rec.createdAt),
          onPlayPause: () => _togglePlay(rec),
          onRename: () => _rename(rec),
          onDelete: () => _delete(rec),
        );
      },
    );
  }

  Widget _buildBottomBar() {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(24, 20, 24, 20 + bottomPad),
      decoration: const BoxDecoration(
        color: Color(0xFF141414),
        border: Border(top: BorderSide(color: Color(0xFF252525))),
      ),
      child: _isRecording ? _buildActiveRecorder() : _buildIdleMic(),
    );
  }

  Widget _buildIdleMic() {
    return Center(
      child: GestureDetector(
        onTap: _startRecording,
        child: AnimatedBuilder(
          animation: _pulseAnim,
          builder: (_, _) => Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFE53935),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE53935)
                      .withValues(alpha: 0.15 + 0.2 * _pulseAnim.value),
                  blurRadius: 16 + 14 * _pulseAnim.value,
                  spreadRadius: 2 + 4 * _pulseAnim.value,
                ),
              ],
            ),
            child: const Icon(Icons.mic, color: Colors.white, size: 32),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveRecorder() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedBuilder(
          animation: _waveAnim,
          builder: (_, _) => Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(7, (i) {
              final phase =
                  i / 7.0 * 2 * math.pi + _waveAnim.value * 2 * math.pi;
              final h = 6.0 + 22.0 * ((math.sin(phase) + 1) / 2);
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                width: 4,
                height: h,
                decoration: BoxDecoration(
                  color: const Color(0xFFE53935),
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          ),
        ),
        const SizedBox(width: 20),
        Text(
          _fmtDur(_recDuration),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w300,
            letterSpacing: 3,
          ),
        ),
        const SizedBox(width: 20),
        GestureDetector(
          onTap: _stopRecording,
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFE53935),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE53935).withValues(alpha: 0.4),
                  blurRadius: 14,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(Icons.stop_rounded, color: Colors.white, size: 28),
          ),
        ),
      ],
    );
  }
}

class _RecordingCard extends StatelessWidget {
  final Recording rec;
  final bool isPlaying;
  final bool isActive;
  final double progress;
  final String durationLabel;
  final String dateLabel;
  final VoidCallback onPlayPause;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _RecordingCard({
    super.key,
    required this.rec,
    required this.isPlaying,
    required this.isActive,
    required this.progress,
    required this.durationLabel,
    required this.dateLabel,
    required this.onPlayPause,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive
              ? const Color(0xFFE53935).withValues(alpha: 0.35)
              : Colors.transparent,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isActive
                        ? const Color(0xFFE53935).withValues(alpha: 0.15)
                        : const Color(0xFF252525),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isActive ? Icons.graphic_eq : Icons.audio_file,
                    color: isActive
                        ? const Color(0xFFE53935)
                        : const Color(0xFF777777),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rec.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        dateLabel,
                        style: const TextStyle(
                          color: Color(0xFF666666),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  durationLabel,
                  style: TextStyle(
                    color: isActive
                        ? const Color(0xFFE53935)
                        : const Color(0xFF777777),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                IconButton(
                  onPressed: onPlayPause,
                  icon: Icon(
                    isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                    color: isActive
                        ? const Color(0xFFE53935)
                        : const Color(0xFF555555),
                    size: 38,
                  ),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 44, minHeight: 44),
                ),
                PopupMenuButton<String>(
                  onSelected: (val) {
                    if (val == 'rename') onRename();
                    if (val == 'delete') onDelete();
                  },
                  color: const Color(0xFF2A2A2A),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  icon: const Icon(
                    Icons.more_vert,
                    color: Color(0xFF555555),
                    size: 20,
                  ),
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'rename',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined,
                              color: Colors.white70, size: 18),
                          SizedBox(width: 10),
                          Text('Rename',
                              style: TextStyle(color: Colors.white70)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline,
                              color: Colors.redAccent, size: 18),
                          SizedBox(width: 10),
                          Text('Delete',
                              style: TextStyle(color: Colors.redAccent)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (isActive)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(14),
              ),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: const Color(0xFF252525),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Color(0xFFE53935)),
                minHeight: 3,
              ),
            ),
        ],
      ),
    );
  }
}
