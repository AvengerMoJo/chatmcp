import 'dart:convert';
import 'dart:io' as io;
import 'package:chatmcp/llm/model.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import 'package:logging/logging.dart';
import 'package:chatmcp/utils/file_content.dart';

enum FileUploadStrategy { uploadApi, directEmbed, mcpTool }

class FileUploadHandler {
  static FileUploadStrategy getStrategy(String providerId, String? modelId) {
    if (providerId == 'gemini') {
      return FileUploadStrategy.uploadApi;
    }

    if (providerId == 'openai' && modelId != null && (modelId.contains('gpt-4o') || modelId.contains('gpt-4.1'))) {
      return FileUploadStrategy.uploadApi;
    }

    if (providerId == 'claude-code') {
      return FileUploadStrategy.mcpTool;
    }

    return FileUploadStrategy.directEmbed;
  }

  static Future<File> prepareFile(PlatformFile platformFile, FileUploadStrategy strategy) async {
    try {
      switch (strategy) {
        case FileUploadStrategy.uploadApi:
          return await _prepareForUploadApi(platformFile);

        case FileUploadStrategy.directEmbed:
          return await _prepareForDirectEmbed(platformFile);

        case FileUploadStrategy.mcpTool:
          return _prepareForMcpTool(platformFile);
      }
    } catch (e) {
      Logger.root.severe('Failed to prepare file ${platformFile.name}: $e');
      return platformFileToFile(platformFile);
    }
  }

  static Future<File> _prepareForUploadApi(PlatformFile platformFile) async {
    final fileType = lookupMimeType(platformFile.name) ?? platformFile.extension ?? '';

    if (fileType.startsWith('image/')) {
      List<int> fileBytes;
      if (platformFile.bytes != null) {
        fileBytes = platformFile.bytes!;
      } else {
        fileBytes = io.File(platformFile.path!).readAsBytesSync();
      }

      return File(
        name: platformFile.name,
        path: platformFile.path,
        size: platformFile.size,
        fileType: fileType,
        fileContent: base64Encode(fileBytes),
      );
    }

    return File(name: platformFile.name, path: platformFile.path, size: platformFile.size, fileType: fileType, fileContent: '');
  }

  static Future<File> _prepareForDirectEmbed(PlatformFile platformFile) async {
    final fileType = lookupMimeType(platformFile.name) ?? platformFile.extension ?? '';
    Logger.root.info('Preparing file for directEmbed: ${platformFile.name}, MIME type: $fileType');

    if (fileType.startsWith('image/')) {
      List<int> fileBytes;
      if (platformFile.bytes != null) {
        fileBytes = platformFile.bytes!;
      } else {
        fileBytes = io.File(platformFile.path!).readAsBytesSync();
      }

      Logger.root.info('Image file prepared, base64 length: ${base64Encode(fileBytes).length}');
      return File(
        name: platformFile.name,
        path: platformFile.path,
        size: platformFile.size,
        fileType: fileType,
        fileContent: base64Encode(fileBytes),
      );
    }

    if (isTextFile(fileType)) {
      List<int> fileBytes;
      if (platformFile.bytes != null) {
        fileBytes = platformFile.bytes!;
      } else {
        fileBytes = io.File(platformFile.path!).readAsBytesSync();
      }

      return File(name: platformFile.name, path: platformFile.path, size: platformFile.size, fileType: fileType, fileContent: utf8.decode(fileBytes));
    }

    return File(name: platformFile.name, path: platformFile.path, size: platformFile.size, fileType: fileType, fileContent: '');
  }

  static File _prepareForMcpTool(PlatformFile platformFile) {
    final fileType = lookupMimeType(platformFile.name) ?? platformFile.extension ?? '';

    return File(name: platformFile.name, path: platformFile.path, size: platformFile.size, fileType: fileType, fileContent: '');
  }
}
