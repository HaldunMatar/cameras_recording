/// Stub used on non-web platforms (Android, iOS, desktop).
/// The real implementation is in download_web.dart.
void downloadViaAnchor(String url, String filename) {
  // No-op on non-web platforms.
  // Dio handles the download directly in api_service.dart.
}
