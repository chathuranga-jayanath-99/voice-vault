class Recording {
  final String id;
  String name;
  final String filePath;
  final DateTime createdAt;
  int durationMs;

  Recording({
    required this.id,
    required this.name,
    required this.filePath,
    required this.createdAt,
    this.durationMs = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'filePath': filePath,
        'createdAt': createdAt.toIso8601String(),
        'durationMs': durationMs,
      };

  factory Recording.fromJson(Map<String, dynamic> json) => Recording(
        id: json['id'] as String,
        name: json['name'] as String,
        filePath: json['filePath'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      );

  String get formattedDuration {
    final d = Duration(milliseconds: durationMs);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
