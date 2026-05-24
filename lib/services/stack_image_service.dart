import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

/// Thrown when the picked image can't be decoded or processed.
class StackImagePickFailure implements Exception {
  StackImagePickFailure(this.message);
  final String message;
  @override
  String toString() => 'StackImagePickFailure: $message';
}

// Reject files larger than this before decoding to avoid OOMing the isolate
// on a malicious or accidental huge gallery pick.
const int _maxSourceBytes = 25 * 1024 * 1024;

// Output dimensions: square, ~14-34 KB base64 at JPEG quality 85.
const int _outputSize = 256;
const int _jpegQuality = 85;

/// Open the system gallery and return the picked file's raw bytes, or null
/// if the user cancelled. Throws [StackImagePickFailure] if the file is over
/// [_maxSourceBytes] (guards against gallery picks that would OOM the decode).
Future<Uint8List?> pickStackImageBytes({ImagePicker? picker}) async {
  final p = picker ?? ImagePicker();
  final XFile? picked = await p.pickImage(source: ImageSource.gallery);
  if (picked == null) return null;
  final Uint8List bytes = await picked.readAsBytes();
  if (bytes.length > _maxSourceBytes) {
    throw StackImagePickFailure('source image too large');
  }
  return bytes;
}

/// Resize the (already-cropped) image to [_outputSize] square, JPEG-encode at
/// [_jpegQuality], and return as base64. Runs off the main isolate.
Future<String> processCroppedStackImage(Uint8List cropped) {
  return compute(_processImageBytes, cropped);
}

String _processImageBytes(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw StackImagePickFailure('could not decode image');
  }
  final side = decoded.width < decoded.height ? decoded.width : decoded.height;
  final cropX = (decoded.width - side) ~/ 2;
  final cropY = (decoded.height - side) ~/ 2;
  final square = img.copyCrop(
    decoded,
    x: cropX,
    y: cropY,
    width: side,
    height: side,
  );
  final resized = img.copyResize(
    square,
    width: _outputSize,
    height: _outputSize,
    interpolation: img.Interpolation.average,
  );
  final jpeg = img.encodeJpg(resized, quality: _jpegQuality);
  return base64Encode(jpeg);
}
