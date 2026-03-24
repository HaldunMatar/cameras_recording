// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// On Flutter Web: creates a hidden <a href=url download=filename> element,
/// clicks it, then removes it. The browser shows its native Save dialog.
/// The server's Content-Disposition: attachment header ensures the file
/// is downloaded rather than opened in a new tab.
void downloadViaAnchor(String url, String filename) {
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
}
