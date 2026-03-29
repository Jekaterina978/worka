class JobEntitlements {
  final bool highlight;
  final bool urgent;
  final bool bump;

  const JobEntitlements({
    required this.highlight,
    required this.urgent,
    required this.bump,
  });

  factory JobEntitlements.fromJson(Map<String, dynamic> json) {
    return JobEntitlements(
      highlight: json['highlight'] == true,
      urgent: json['urgent'] == true,
      bump: json['bump'] == true,
    );
  }
}
