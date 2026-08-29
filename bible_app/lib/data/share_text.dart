import 'package:share_plus/share_plus.dart';

/// The system share sheet, as an assignable function so tests can capture
/// what the app shares instead of touching the platform channel.
Future<void> Function(String message) shareText = _systemShare;

/// Same seam for a file export (the notes dump): tests capture the path.
Future<void> Function(String filePath, {String? subject}) shareTextFile =
    _systemShareFile;

Future<void> _systemShare(String message) async {
  await SharePlus.instance.share(ShareParams(text: message));
}

Future<void> _systemShareFile(String filePath, {String? subject}) async {
  await SharePlus.instance.share(
    ShareParams(files: [XFile(filePath)], subject: subject),
  );
}
