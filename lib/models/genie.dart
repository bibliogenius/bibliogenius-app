class GenieAction {
  final String actionType; // AddBook, SearchBook, None
  final String payload;
  final String label;

  GenieAction({
    required this.actionType,
    required this.payload,
    required this.label,
  });

  factory GenieAction.fromJson(Map<String, dynamic> json) {
    return GenieAction(
      actionType: json['action_type'] ?? 'None',
      payload: json['payload'] ?? '',
      label: json['label'] ?? '',
    );
  }
}

class GenieResponse {
  final String text;
  final List<GenieAction> actions;

  GenieResponse({
    required this.text,
    required this.actions,
  });

  factory GenieResponse.fromJson(Map<String, dynamic> json) {
    var actionsList = json['actions'] as List? ?? [];
    List<GenieAction> actions = actionsList
        .map((i) => GenieAction.fromJson(i))
        .toList();

    return GenieResponse(
      text: json['text'] ?? '',
      actions: actions,
    );
  }
}
