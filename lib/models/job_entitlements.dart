class JobEntitlements {
  final bool highlight;
  final bool urgent;
  final bool priority;
  final bool bump;
  final bool contacts;

  const JobEntitlements({
    required this.highlight,
    required this.urgent,
    required this.priority,
    required this.bump,
    required this.contacts,
  });

  factory JobEntitlements.fromJson(Map<String, dynamic> json) {
    return JobEntitlements(
      highlight: json['highlight'] == true,
      urgent: json['urgent'] == true,
      priority: json['priority'] == true,
      bump: json['bump'] == true,
      contacts: json['contacts'] == true,
    );
  }

  Set<String> toFeatureSet() {
    final feats = <String>{};
    if (highlight) feats.add('highlight');
    if (urgent) feats.add('urgent');
    if (priority) feats.add('priority');
    if (bump) feats.add('bump');
    if (contacts) feats.add('show_contacts');
    return feats;
  }
}
