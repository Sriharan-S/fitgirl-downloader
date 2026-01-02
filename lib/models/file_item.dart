class FileItem {
  final String id;
  final String name;
  final String size;
  final bool required;
  bool selected;
  final String? tag; // e.g., "REQ", "VIDEO", "AUDIO"
  final String? url;

  FileItem({
    required this.id,
    required this.name,
    required this.size,
    required this.required,
    this.selected = false,
    this.tag,
    this.url,
  });
}
