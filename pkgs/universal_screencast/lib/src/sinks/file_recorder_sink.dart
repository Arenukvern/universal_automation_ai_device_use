import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:universal_automation_interface/universal_automation_interface.dart';

import '../frame.dart';
import '../frame_sink.dart';

/// Durable frame recording with a receipt manifest per frame.
///
/// Two artifacts land in [directory]: `<base>.<ext>` — the raw frame
/// payloads concatenated (playable by any MJPEG tool when the frames are
/// JPEG) — and `<base>.meta.jsonl`, one JSON receipt per frame with its
/// byte offset, aligning with the established recording receipt contract
/// families (`recording`, `receipts`). Frames are evidence-grade bytes
/// here; the sink never invents content (`video != evidence`, but a
/// receipt makes it checkable).
///
/// The extension follows the frames actually written: JPEG frames land in
/// `.mjpeg`, PNG frames in `.png`. A file named for an encoding it does
/// not hold would misdescribe the evidence.
class FileRecorderSink implements FrameSink {
  /// Creates a recorder writing `<directory>/<base>.<ext>` and
  /// `<directory>/<base>.meta.jsonl`.
  ///
  /// [extension] overrides the extension the first frame's content type
  /// selects; `null` (the default) lets the content decide.
  FileRecorderSink({
    required this._directory,
    this._base = 'frames',
    this._extension,
  });

  final String _directory;
  final String _base;
  final String? _extension;
  String? _resolvedExtension;
  RandomAccessFile? _framesFile;
  RandomAccessFile? _metaFile;
  int _offset = 0;
  bool _closed = false;

  @override
  String get id => 'recorder';

  @override
  List<String> get acceptedContentTypes => const ['*'];

  /// Path of the frame payload file.
  ///
  /// Before the first frame the extension is the one the sink expects
  /// from its source; after it, the one the written frames actually use.
  String get framesPath =>
      '$_directory/$_base.${_resolvedExtension ?? _expectedExtension}';

  /// Path of the receipt manifest.
  String get metaPath => '$_directory/$_base.meta.jsonl';

  /// The extension the written frames select.
  String get _expectedExtension => 'mjpeg';

  @override
  Future<void> push(Frame frame) async {
    if (_closed) throw SinkClosedException(id);
    // The first frame decides the extension, so the file is named for the
    // encoding it actually holds. A later frame of another encoding would
    // make the name wrong, so it is refused rather than mislabeled.
    if (_resolvedExtension == null) {
      _resolvedExtension = _extension ?? _extensionFor(frame.contentType);
    } else if (_extension == null &&
        _extensionFor(frame.contentType) != _resolvedExtension) {
      throw ProtocolException(
        'the recorder holds $_resolvedExtension frames and cannot also '
        'write ${frame.contentType} frames',
        details: {'written': _resolvedExtension, 'offered': frame.contentType},
      );
    }
    _framesFile ??= await File(framesPath)
        .create(recursive: true)
        .then((file) => file.open(mode: FileMode.append));
    _metaFile ??= await File(metaPath)
        .create(recursive: true)
        .then((file) => file.open(mode: FileMode.append));
    await _framesFile!.writeFrom(frame.bytes);
    final receipt = jsonEncode({
      'sourceId': frame.sourceId,
      'sequence': frame.sequence,
      'revision': frame.revision,
      'offset': _offset,
      'byteLength': frame.bytes.length,
      'contentType': frame.contentType,
      'capturedAt': frame.capturedAt.toIso8601String(),
    });
    await _metaFile!.writeFrom(utf8.encode('$receipt\n'));
    _offset += frame.bytes.length;
  }

  /// The file extension a content type is recorded under.
  static String _extensionFor(String contentType) => switch (contentType) {
    'image/jpeg' => 'mjpeg',
    'image/png' => 'png',
    _ => 'frames',
  };

  @override
  Future<void> close({Object? error}) async {
    if (_closed) return;
    _closed = true;
    await _framesFile?.flush();
    await _framesFile?.close();
    await _metaFile?.flush();
    await _metaFile?.close();
    _framesFile = null;
    _metaFile = null;
  }
}
