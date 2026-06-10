class Call {
  final int id;
  final int callerId;
  final int calleeId;
  final String status; // 'PENDING' | 'ACCEPTED' | 'REJECTED' | 'ENDED' | 'MISSED'
  final String? startedAt;
  final String? endedAt;
  final String createdAt;

  Call({
    required this.id,
    required this.callerId,
    required this.calleeId,
    required this.status,
    this.startedAt,
    this.endedAt,
    required this.createdAt,
  });

  factory Call.fromJson(Map<String, dynamic> json) => Call(
        id: json['id'] as int,
        callerId: json['callerId'] as int,
        calleeId: json['calleeId'] as int,
        status: json['status'] as String? ?? 'MISSED',
        startedAt: json['startedAt'] as String?,
        endedAt: json['endedAt'] as String?,
        createdAt: json['createdAt'] as String? ?? DateTime.now().toIso8601String(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'callerId': callerId,
        'calleeId': calleeId,
        'status': status,
        'startedAt': startedAt,
        'endedAt': endedAt,
        'createdAt': createdAt,
      };
}