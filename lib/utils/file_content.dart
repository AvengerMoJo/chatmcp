import 'dart:io' as io;
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import "package:chatmcp/llm/model.dart";
import 'package:file_picker/file_picker.dart';

File platformFileToFile(PlatformFile platformFile) {
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
      // fileContent: "data:$fileType;base64,${base64Encode(fileBytes)}",
    );
  }

  debugPrint('fileType: $fileType');

  // 判断是否为文本类型文件
  bool isTextFile =
      fileType.startsWith('text/') ||
      fileType.startsWith('application/') &&
          (fileType.contains('json') ||
              fileType.contains('javascript') ||
              fileType.contains('xml') ||
              fileType.contains('yaml') ||
              fileType.contains('x-yaml') ||
              fileType.contains('toml') ||
              fileType.contains('markdown') ||
              fileType.contains('x-httpd-php') ||
              fileType.contains('x-sh') ||
              fileType.contains('x-python'));

  if (isTextFile) {
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

bool isTextFile(String fileType) {
  return fileType.startsWith('text/') ||
      fileType.startsWith('application/') &&
          (fileType.contains('json') ||
              fileType.contains('javascript') ||
              fileType.contains('xml') ||
              fileType.contains('yaml') ||
              fileType.contains('x-yaml') ||
              fileType.contains('toml') ||
              fileType.contains('markdown') ||
              fileType.contains('x-httpd-php') ||
              fileType.contains('x-sh') ||
              fileType.contains('x-python')) ||
      // 常见文本文件类型
      fileType == 'json' ||
      fileType == 'javascript' ||
      fileType == 'xml' ||
      fileType == 'yaml' ||
      fileType == 'toml' ||
      fileType == 'markdown' ||
      fileType == 'md' ||
      fileType == 'txt' ||
      fileType == 'php' ||
      fileType == 'sh' ||
      fileType == 'py' ||
      fileType == 'js' ||
      fileType == 'ts' ||
      fileType == 'html' ||
      fileType == 'css' ||
      fileType == 'scss' ||
      fileType == 'less' ||
      fileType == 'dart' ||
      // 编程语言
      fileType == 'java' ||
      fileType == 'c' ||
      fileType == 'cpp' ||
      fileType == 'cc' ||
      fileType == 'h' ||
      fileType == 'hpp' ||
      fileType == 'cs' ||
      fileType == 'go' ||
      fileType == 'rb' ||
      fileType == 'rs' ||
      fileType == 'swift' ||
      fileType == 'kt' ||
      fileType == 'jsx' ||
      fileType == 'tsx' ||
      fileType == 'd.ts' ||
      fileType == 'phtml' ||
      fileType == 'sql' ||
      fileType == 'bash' ||
      fileType == 'zsh' ||
      fileType == 'vue' ||
      fileType == 'svelte' ||
      fileType == 'graphql' ||
      fileType == 'gql' ||
      fileType == 'proto' ||
      fileType == 'sol' ||
      fileType == 'lua' ||
      fileType == 'ex' ||
      fileType == 'exs' ||
      fileType == 'erl' ||
      fileType == 'hrl' ||
      fileType == 'clj' ||
      fileType == 'scala' ||
      fileType == 'pl' ||
      fileType == 'pm' ||
      fileType == 'r' ||
      fileType == 'rmd' ||
      // 配置文件
      fileType == 'env' ||
      fileType == 'ini' ||
      fileType == 'conf' ||
      fileType == 'config' ||
      fileType == 'dockerfile' ||
      fileType == 'dockerignore' ||
      fileType == 'gitignore' ||
      fileType == 'gitconfig' ||
      fileType == 'editorconfig' ||
      fileType == 'prettierrc' ||
      fileType == 'eslintrc' ||
      fileType == 'babelrc' ||
      fileType == 'npmrc' ||
      fileType == 'properties' ||
      // 文档和标记语言
      fileType == 'adoc' ||
      fileType == 'rst' ||
      fileType == 'tex' ||
      fileType == 'rtf' ||
      fileType == 'wiki' ||
      fileType == 'org' ||
      // 数据文件
      fileType == 'csv' ||
      fileType == 'tsv' ||
      fileType == 'svg' ||
      fileType == 'wat' ||
      fileType == 'wasm' ||
      fileType == 'log' ||
      // 其他常见纯文本文件
      fileType == 'lock' ||
      fileType == 'license' ||
      fileType == 'makefile' ||
      fileType == 'cmake' ||
      fileType == 'csproj' ||
      fileType == 'sln' ||
      fileType == 'gradle' ||
      fileType == 'pom';
}

bool isImageFile(String fileType) {
  return fileType.startsWith('image/');
}

Future<String> extractTextFromPDF(String filePath) async {
  try {
    final file = io.File(filePath);
    if (!await file.exists()) {
      return '[Error: PDF file not found]';
    }

    final bytes = await file.readAsBytes();
    return _extractPDFTextFromBytes(bytes, file.uri.pathSegments.last);
  } catch (e) {
    debugPrint('Failed to extract text from PDF: $e');
    return '[Error reading PDF file: $e]';
  }
}

Future<String> extractTextFromPDFBytes(Uint8List bytes, String fileName) async {
  try {
    return _extractPDFTextFromBytes(bytes, fileName);
  } catch (e) {
    debugPrint('Failed to extract text from PDF bytes: $e');
    return '[Error reading PDF file: $e]';
  }
}

String _extractPDFTextFromBytes(Uint8List bytes, String pdfName) {
  return '[PDF file: $pdfName]\n'
      '[PDF text extraction is not available.]\n'
      '[If the PDF contains readable text, try selecting and copying the text directly, '
      'or convert the PDF to images first and re-attach.]';
}

Future<String> extractTextFromExcel(String filePath) async {
  try {
    final file = io.File(filePath);

    // For now, just return a placeholder since Excel parsing is complex
    // TODO: Implement proper Excel text extraction
    return '[Excel file detected: ${file.uri.pathSegments.last}. Text extraction not yet implemented. Please copy and paste the content as CSV.]';
  } catch (e) {
    debugPrint('Failed to extract text from Excel: $e');
    return '[Error reading Excel file: $e]';
  }
}
