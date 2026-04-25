import 'package:chatmcp/page/layout/widgets/mcp_tools.dart';
import 'package:chatmcp/provider/provider_manager.dart';
import 'package:chatmcp/provider/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:chatmcp/utils/platform.dart';
import 'package:file_picker/file_picker.dart';
import 'package:chatmcp/widgets/upload_menu.dart';
import 'package:chatmcp/generated/app_localizations.dart';
import 'package:flutter/cupertino.dart';
import 'package:chatmcp/widgets/ink_icon.dart';
import 'package:chatmcp/utils/color.dart';
import 'package:chatmcp/page/layout/widgets/conv_setting.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'dart:io' as io;
import 'package:pdfrx/pdfrx.dart';
import 'package:path_provider/path_provider.dart';
import 'package:chatmcp/utils/file_upload_handler.dart';
import 'package:chatmcp/utils/file_content.dart';

class SubmitData {
  final String text;
  final List<PlatformFile> files;

  SubmitData(this.text, this.files);

  @override
  String toString() {
    return 'SubmitData(text: $text, files: $files)';
  }
}

class InputArea extends StatefulWidget {
  final bool isComposing;
  final bool disabled;
  final ValueChanged<String> onTextChanged;
  final ValueChanged<SubmitData> onSubmitted;
  final VoidCallback? onCancel;
  final ValueChanged<List<PlatformFile>>? onFilesSelected;
  final Future<bool> Function(PlatformFile)? onPdfPageSubmitted;
  final bool autoFocus;

  const InputArea({
    super.key,
    required this.isComposing,
    required this.disabled,
    required this.onTextChanged,
    required this.onSubmitted,
    this.onFilesSelected,
    this.onPdfPageSubmitted,
    this.onCancel,
    this.autoFocus = false,
  });

  @override
  State<InputArea> createState() => InputAreaState();
}

class InputAreaState extends State<InputArea> {
  List<PlatformFile> _selectedFiles = [];
  final TextEditingController textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isImeComposing = false;

  // Speech recognition
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechEnabled = false;
  bool _isListening = false;
  String _lastWords = '';
  bool _isLoading = false;
  bool _isCancelled = false;
  List<stt.LocaleName> _availableLocales = [];
  stt.LocaleName? _selectedLocale;

  @override
  void initState() {
    super.initState();
    // Auto focus on desktop when autoFocus is true
    if (!kIsMobile && widget.autoFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });
    }
    // Initialize speech recognition
    _initSpeech();
  }

  void _initSpeech() async {
    _speechEnabled = await _speech.initialize(
      onError: (error) {
        debugPrint('Speech error: $error');
        setState(() => _isListening = false);
      },
      onStatus: (status) {
        debugPrint('Speech status: $status');
        if (status == 'done' || status == 'notListening') {
          setState(() => _isListening = false);
        }
      },
    );
    if (_speechEnabled) {
      final allLocales = await _speech.locales();
      // Filter locales - keep English simplified, keep important Chinese variants, keep one per other languages
      final seenLanguages = <String>{};
      _availableLocales = [];
      for (final locale in allLocales) {
        final langCode = locale.localeId.split('_').first;

        // For English, keep only en_US if available, otherwise first English locale
        if (langCode == 'en') {
          if (locale.localeId == 'en_US' && !seenLanguages.contains('en')) {
            seenLanguages.add('en');
            _availableLocales.add(locale);
          } else if (!seenLanguages.contains('en') && locale.localeId.startsWith('en')) {
            // Keep first English locale if en_US not found
            seenLanguages.add('en');
            _availableLocales.add(locale);
          }
        }
        // For Chinese, keep important variants (Mandarin, Taiwan, Hong Kong)
        else if (langCode == 'zh') {
          if (locale.localeId == 'zh_CN' || locale.localeId == 'zh_TW' || locale.localeId == 'zh_HK') {
            if (!seenLanguages.contains(locale.localeId)) {
              seenLanguages.add(locale.localeId);
              _availableLocales.add(locale);
            }
          }
        }
        // For other languages, keep only one locale per language
        else {
          if (!seenLanguages.contains(langCode)) {
            seenLanguages.add(langCode);
            _availableLocales.add(locale);
          }
        }
      }
      // Try to match device locale or default to first available
      final deviceLocale = Localizations.localeOf(context).languageCode;
      _selectedLocale = _availableLocales.isNotEmpty
          ? _availableLocales.firstWhere((l) => l.localeId.startsWith(deviceLocale), orElse: () => _availableLocales.first)
          : null;
    }
    setState(() {});
  }

  @override
  void didUpdateWidget(InputArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto focus on desktop when autoFocus changes to true
    if (!kIsMobile && widget.autoFocus && !oldWidget.autoFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _speech.stop();
    super.dispose();
  }

  void requestFocus() {
    if (!kIsMobile && mounted) {
      _focusNode.requestFocus();
    }
  }

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: [
          'txt',
          'md',
          'json',
          'csv',
          'xml',
          'yaml',
          'yml',
          'py',
          'js',
          'ts',
          'dart',
          'java',
          'cpp',
          'c',
          'h',
          'html',
          'css',
          'scss',
          'php',
          'sh',
          'go',
          'rs',
          'pdf',
          'xlsx',
          'xls',
        ],
      );

      if (result != null && result.files.isNotEmpty) {
        final pdfFiles = result.files.where((f) => f.extension?.toLowerCase() == 'pdf').toList();
        final otherFiles = result.files.where((f) => f.extension?.toLowerCase() != 'pdf').toList();

        if (otherFiles.isNotEmpty) {
          setState(() {
            _selectedFiles = [..._selectedFiles, ...otherFiles];
          });
          widget.onFilesSelected?.call(_selectedFiles);
        }

        if (pdfFiles.isNotEmpty) {
          await _processPdfPagesSequentially(pdfFiles);
        }
      }
    } catch (e) {
      debugPrint('Error picking files: $e');
    }
  }
  
  Future<List<PlatformFile>> _convertPdfToImages(String pdfPath) async {
    final convertedFiles = <PlatformFile>[];

    try {
      final document = await PdfDocument.openFile(pdfPath);
      final pageCount = document.pages.length;
      final pdfName = pdfPath.split('/').last.split('.').first;

      if (pageCount == 0) {
        await document.dispose();
        throw Exception('PDF has no pages');
      }

      for (int i = 0; i < pageCount; i++) {
        final page = document.pages[i];
        const scaleFactor = 1;
        final image = await page.render(
          width: page.width.toInt() * scaleFactor,
          height: page.height.toInt() * scaleFactor,
          backgroundColor: Colors.white,
        );

        if (image != null && image.pixels != null) {
          final bgraBytes = image.pixels;
          final rgbaBytes = Uint8List(bgraBytes.length);
          
          for (int j = 0; j < bgraBytes.length; j += 4) {
            rgbaBytes[j] = bgraBytes[j + 2];
            rgbaBytes[j + 1] = bgraBytes[j + 1];
            rgbaBytes[j + 2] = bgraBytes[j];
            rgbaBytes[j + 3] = bgraBytes[j + 3];
          }
          
          final tempDir = await getTemporaryDirectory();
          final outputPath = '${tempDir.path}/${pdfName}_page_${i + 1}.png';
          final outputFile = io.File(outputPath);
          await outputFile.writeAsBytes(rgbaBytes);

          convertedFiles.add(PlatformFile(name: '${pdfName}_page_${i + 1}.png', path: outputPath, size: rgbaBytes.length));
        }

        image?.dispose();
      }

      await document.dispose();

      if (convertedFiles.isEmpty) {
        throw Exception('No pages were successfully rendered');
      }

      return convertedFiles;
    } catch (e) {
      debugPrint('Error converting PDF to images: $e');
      rethrow;
    }
  }

  Future<void> _pickImages() async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.image);

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _selectedFiles = [..._selectedFiles, ...result.files];
        });
        widget.onFilesSelected?.call(_selectedFiles);
      }
    } catch (e) {
      debugPrint('Error picking images: $e');
    }
  }

  void _removeFile(int index) {
    setState(() {
      _selectedFiles.removeAt(index);
    });
    widget.onFilesSelected?.call(_selectedFiles);
  }

  void _afterSubmitted() {
    textController.clear();
    _selectedFiles.clear();
  }

  Future<List<String>> _extractPdfText(String pdfPath) async {
    final pages = <String>[];
    try {
      final document = await PdfDocument.openFile(pdfPath);
      final pageCount = document.pages.length;

      for (int i = 0; i < pageCount; i++) {
        final page = document.pages[i];
        final text = await page.loadText();
        pages.add(text?.fullText ?? '');
      }

      await document.dispose();
    } catch (e) {
      debugPrint('Error extracting PDF text: $e');
    }
    return pages;
  }

  Future<void> _processPdfPagesSequentially(List<PlatformFile> pdfFiles) async {
    setState(() {
      _isLoading = true;
      _isCancelled = false;
    });

    final newFiles = <PlatformFile>[];

    try {
      for (final pdfFile in pdfFiles) {
        if (_isCancelled) break;

        // First check: is the PDF text-rich? (fast sample of 3 pages)
        final isTextRich = await _classifyPdfGraphic(pdfFile.path!);

        if (isTextRich) {
          // Text-rich: extract text pages (fast, works for all models)
          final extractedPages = await _extractPdfText(pdfFile.path!);
          for (int p = 0; p < extractedPages.length; p++) {
            final pageText = extractedPages[p];
            if (pageText.trim().isEmpty) continue;
            final tempDir = await getTemporaryDirectory();
            final pdfName = pdfFile.path!.split('/').last.split('.').first;
            final textFilePath = '${tempDir.path}/${pdfName}_page_${p + 1}.txt';
            await io.File(textFilePath).writeAsString(pageText);
            newFiles.add(PlatformFile(
              name: '${pdfName}_page_${p + 1}.txt',
              path: textFilePath,
              size: pageText.length,
            ));
          }
        } else {
          // Graphic-heavy: try first page as image to see if provider accepts it
          final firstPageImage = await _convertSinglePdfPageToImage(pdfFile.path!, 1);
          if (firstPageImage != null && widget.onPdfPageSubmitted != null) {
            final succeeded = await widget.onPdfPageSubmitted!(firstPageImage);
            // Clean up the test page image
            if (firstPageImage.path != null) {
              try { await io.File(firstPageImage.path!).delete(); } catch (_) {}
            }

            if (succeeded) {
              debugPrint('Image test page succeeded, converting remaining pages for: ${pdfFile.name}');
              final remainingPages = await _convertPdfToImages(pdfFile.path!);
              int cumulativeBytes = firstPageImage.size;
              for (final page in remainingPages) {
                if (page.path == firstPageImage.path) continue;
                if (_isCancelled) break;

                // Stop sending pages if cumulative image data exceeds 5MB
                // (most nginx/proxy limits are ~10MB for request body)
                cumulativeBytes += page.size;
                if (cumulativeBytes > 5 * 1024 * 1024) {
                  debugPrint('Cumulative image size ${cumulativeBytes ~/ 1024}KB exceeds 5MB limit, stopping');
                  if (page.path != null) {
                    try { await io.File(page.path!).delete(); } catch (_) {}
                  }
                  break;
                }

                await widget.onPdfPageSubmitted!(page);
                if (page.path != null) {
                  try { await io.File(page.path!).delete(); } catch (_) {}
                }
              }
            } else {
              // Provider rejected image — fall back to text extraction
              debugPrint('Image test page failed, falling back to text for: ${pdfFile.name}');
              final extractedPages = await _extractPdfText(pdfFile.path!);
              for (int p = 0; p < extractedPages.length; p++) {
                final pageText = extractedPages[p];
                if (pageText.trim().isEmpty) continue;
                final tempDir = await getTemporaryDirectory();
                final pdfName = pdfFile.path!.split('/').last.split('.').first;
                final textFilePath = '${tempDir.path}/${pdfName}_page_${p + 1}.txt';
                await io.File(textFilePath).writeAsString(pageText);
                newFiles.add(PlatformFile(
                  name: '${pdfName}_page_${p + 1}.txt',
                  path: textFilePath,
                  size: pageText.length,
                ));
              }
            }
          } else {
            // No callback available — add file as-is
            newFiles.add(PlatformFile(
              name: pdfFile.name,
              path: pdfFile.path,
              size: pdfFile.size,
              bytes: pdfFile.bytes,
            ));
          }
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _selectedFiles = [..._selectedFiles, ...newFiles];
          _isLoading = false;
        });
        widget.onFilesSelected?.call(_selectedFiles);
      }
    }
  }

  /// Quickly sample first 3 pages to check if PDF has meaningful extractable text.
  Future<bool> _classifyPdfGraphic(String pdfPath, {int samplePages = 3}) async {
    try {
      final document = await PdfDocument.openFile(pdfPath);
      final pageCount = document.pages.length;
      final pagesToSample = pageCount < samplePages ? pageCount : samplePages;
      int totalChars = 0;

      for (int i = 0; i < pagesToSample; i++) {
        final page = document.pages[i];
        final text = await page.loadText();
        totalChars += text?.fullText.trim().length ?? 0;
      }

      await document.dispose();
      return pagesToSample > 0 && (totalChars / pagesToSample) > 50;
    } catch (e) {
      debugPrint('Error classifying PDF: $e');
      return false;
    }
  }

  /// Convert a single PDF page to a PlatformFile image (for test probe)
  Future<PlatformFile?> _convertSinglePdfPageToImage(String pdfPath, int pageNumber) async {
    try {
      final document = await PdfDocument.openFile(pdfPath);
      if (pageNumber > document.pages.length) {
        await document.dispose();
        return null;
      }

      const scaleFactor = 1;
      final page = document.pages[pageNumber - 1];
      final image = await page.render(
        width: page.width.toInt() * scaleFactor,
        height: page.height.toInt() * scaleFactor,
        backgroundColor: Colors.white,
      );

      if (image == null || image.pixels == null) {
        await document.dispose();
        return null;
      }

      final bgraBytes = image.pixels;
      final rgbaBytes = Uint8List(bgraBytes.length);
      for (int j = 0; j < bgraBytes.length; j += 4) {
        rgbaBytes[j] = bgraBytes[j + 2];
        rgbaBytes[j + 1] = bgraBytes[j + 1];
        rgbaBytes[j + 2] = bgraBytes[j];
        rgbaBytes[j + 3] = bgraBytes[j + 3];
      }

      final pdfName = pdfPath.split('/').last.split('.').first;
      final tempDir = await getTemporaryDirectory();
      final outputPath = '${tempDir.path}/${pdfName}_page_$pageNumber.png';
      await io.File(outputPath).writeAsBytes(rgbaBytes);
      image.dispose();
      await document.dispose();

      return PlatformFile(name: '${pdfName}_page_$pageNumber.png', path: outputPath, size: rgbaBytes.length);
    } catch (e) {
      debugPrint('Error converting single PDF page to image: $e');
      return null;
    }
  }

  void _startListening() {
    if (!_speechEnabled) {
      debugPrint('Speech not available');
      return;
    }
    _lastWords = '';
    _speech.listen(
      onResult: (result) {
        setState(() {
          _lastWords = result.recognizedWords;
          if (result.finalResult) {
            // Append recognized text to input
            if (_lastWords.isNotEmpty) {
              final currentText = textController.text;
              textController.text = currentText.isEmpty ? _lastWords : '$currentText $_lastWords';
              textController.selection = TextSelection.fromPosition(TextPosition(offset: textController.text.length));
            }
            _isListening = false;
          }
        });
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      localeId: _selectedLocale?.localeId,
      listenOptions: stt.SpeechListenOptions(partialResults: true, cancelOnError: true),
    );
    setState(() => _isListening = true);
  }

  void _stopListening() {
    _speech.stop();
    setState(() => _isListening = false);
  }

  String _truncateFileName(String fileName) {
    const int maxLength = 20;
    if (fileName.length <= maxLength) return fileName;

    final extension = fileName.contains('.') ? '.${fileName.split('.').last}' : '';
    final nameWithoutExt = fileName.contains('.') ? fileName.substring(0, fileName.lastIndexOf('.')) : fileName;

    if (nameWithoutExt.length <= maxLength - extension.length - 3) {
      return fileName;
    }

    final truncatedLength = (maxLength - extension.length - 3) ~/ 2;
    return '${nameWithoutExt.substring(0, truncatedLength)}'
        '...'
        '${nameWithoutExt.substring(nameWithoutExt.length - truncatedLength)}'
        '$extension';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        // color: Theme.of(context).cardColor,
        color: AppColors.getInputAreaBackgroundColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.getInputAreaBorderColor(context), width: 1),
      ),
      margin: const EdgeInsets.only(left: 12.0, right: 12.0, top: 2.0, bottom: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_selectedFiles.isNotEmpty)
            Container(
              padding: const EdgeInsets.only(left: 12.0, right: 12.0, top: 8.0),
              constraints: const BoxConstraints(maxHeight: 65),
              width: double.infinity,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: _selectedFiles.asMap().entries.map((entry) {
                    final index = entry.key;
                    final file = entry.value;
                    final isImage =
                        file.extension?.toLowerCase() == 'jpg' ||
                        file.extension?.toLowerCase() == 'jpeg' ||
                        file.extension?.toLowerCase() == 'png' ||
                        file.extension?.toLowerCase() == 'gif';

                    final isPdf = file.extension?.toLowerCase() == 'pdf';

                    final isExcel = file.extension?.toLowerCase() == 'xlsx' || file.extension?.toLowerCase() == 'xls';

                    IconData getFileIcon() {
                      if (isImage) return Icons.image;
                      if (isPdf) return Icons.picture_as_pdf;
                      if (isExcel) return Icons.table_chart;
                      return Icons.insert_drive_file;
                    }

                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.getInputAreaFileItemBackgroundColor(context),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.getInputAreaBorderColor(context), width: 1),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
                              child: Row(
                                children: [
                                  Icon(getFileIcon(), size: 16, color: AppColors.getInputAreaFileIconColor(context)),
                                  const SizedBox(width: 6),
                                  Text(
                                    _truncateFileName(file.name),
                                    style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodyMedium?.color),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => _removeFile(index),
                                borderRadius: const BorderRadius.only(topRight: Radius.circular(8), bottomRight: Radius.circular(8)),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 6.0),
                                  child: Icon(Icons.close, size: 14, color: AppColors.getInputAreaIconColor(context)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
            child: Container(
              decoration: BoxDecoration(color: AppColors.getInputAreaBackgroundColor(context)),
              child: Focus(
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
                    final settings = Provider.of<SettingsProvider>(context, listen: false);
                    bool shouldAddNewLine = false;

                    switch (settings.generalSetting.newLineKey) {
                      case NewLineKey.ctrlEnter:
                        shouldAddNewLine = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
                        break;
                      case NewLineKey.shiftEnter:
                        shouldAddNewLine = HardwareKeyboard.instance.isShiftPressed;
                        break;
                      case NewLineKey.ctrlShiftEnter:
                        shouldAddNewLine = HardwareKeyboard.instance.isControlPressed && HardwareKeyboard.instance.isShiftPressed;
                        break;
                    }

                    if (shouldAddNewLine) {
                      // Insert newline at cursor position
                      final selection = textController.selection;
                      final text = textController.text;
                      final newText = text.replaceRange(selection.start, selection.end, '\n');
                      textController.value = TextEditingValue(
                        text: newText,
                        selection: TextSelection.collapsed(offset: selection.start + 1),
                      );
                      return KeyEventResult.handled;
                    }

                    if (shouldAddNewLine) {
                      // Insert newline at cursor position
                      final selection = textController.selection;
                      final text = textController.text;
                      final newText = text.replaceRange(selection.start, selection.end, '\n');
                      textController.value = TextEditingValue(
                        text: newText,
                        selection: TextSelection.collapsed(offset: selection.start + 1),
                      );
                      return KeyEventResult.handled;
                    }

                    if (_isImeComposing) {
                      return KeyEventResult.ignored;
                    }

                    if (widget.isComposing && textController.text.trim().isNotEmpty) {
                      widget.onSubmitted(SubmitData(textController.text, _selectedFiles));
                      _afterSubmitted();
                    }
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  enabled: !widget.disabled,
                  controller: textController,
                  focusNode: _focusNode,
                  onChanged: widget.onTextChanged,
                  maxLines: 5,
                  minLines: 1,
                  onAppPrivateCommand: (value, map) {
                    debugPrint('onAppPrivateCommand: $value');
                  },
                  buildCounter: (context, {required currentLength, required isFocused, maxLength}) {
                    return null;
                  },
                  textInputAction: kIsMobile ? TextInputAction.newline : TextInputAction.done,
                  onSubmitted: null,
                  inputFormatters: [
                    TextInputFormatter.withFunction((oldValue, newValue) {
                      _isImeComposing = newValue.composing != TextRange.empty;
                      return newValue;
                    }),
                  ],
                  keyboardType: TextInputType.multiline,
                  style: TextStyle(fontSize: 14.0, color: AppColors.getInputAreaTextColor(context)),
                  scrollPhysics: const BouncingScrollPhysics(),
                  decoration: InputDecoration(
                    hintText: l10n.askMeAnything,
                    hintStyle: TextStyle(fontSize: 14.0, color: AppColors.getInputAreaHintTextColor(context)),
                    filled: true,
                    fillColor: AppColors.getInputAreaBackgroundColor(context),
                    hoverColor: Colors.transparent,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 10),
                    isDense: true,
                  ),
                  cursorColor: AppColors.getInputAreaCursorColor(context),
                  mouseCursor: WidgetStateMouseCursor.textable,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12.0, right: 12.0, bottom: 6.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (!widget.disabled)
                  Row(
                    children: [
                      FutureBuilder<int>(
                        future: ProviderManager.mcpServerProvider.installedServersCount,
                        builder: (context, snapshot) {
                          return const McpTools();
                        },
                      ),
                      const SizedBox(width: 10),
                      if (kIsMobile) ...[
                        UploadMenu(disabled: widget.disabled, onPickImages: _pickImages, onPickFiles: _pickFiles),
                      ] else ...[
                        Row(
                          children: [
                            InkIcon(
                              icon: CupertinoIcons.photo,
                              onTap: () {
                                if (widget.disabled) return;
                                _pickImages();
                              },
                              disabled: widget.disabled,
                              hoverColor: Theme.of(context).hoverColor,
                              tooltip: AppLocalizations.of(context)!.selectFromGallery,
                            ),
                            const SizedBox(width: 10),
                            InkIcon(
                              icon: CupertinoIcons.doc,
                              onTap: () {
                                if (widget.disabled) return;
                                _pickFiles();
                              },
                              disabled: widget.disabled,
                              hoverColor: Theme.of(context).hoverColor,
                              tooltip: AppLocalizations.of(context)!.selectFile,
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(width: 10),
                      const ConvSetting(),
                      const SizedBox(width: 10),
                      // Voice input button (always show, will show error if not available)
                      InkIcon(
                        icon: _isListening ? CupertinoIcons.stop_circle : CupertinoIcons.mic,
                        onTap: () {
                          if (widget.disabled) return;
                          if (!_speechEnabled) {
                            debugPrint('Speech recognition not available');
                            return;
                          }
                          if (_isListening) {
                            _stopListening();
                          } else {
                            _startListening();
                          }
                        },
                        disabled: widget.disabled,
                        hoverColor: Theme.of(context).hoverColor,
                        tooltip: _isListening ? AppLocalizations.of(context)!.stopListening : AppLocalizations.of(context)!.voiceInput,
                        color: _isListening ? Colors.red : null,
                      ),
                      if (_speechEnabled && _availableLocales.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        PopupMenuButton<stt.LocaleName>(
                          icon: const Icon(CupertinoIcons.globe, size: 20),
                          tooltip: AppLocalizations.of(context)!.selectVoiceLanguage,
                          onSelected: (locale) {
                            setState(() => _selectedLocale = locale);
                          },
                          itemBuilder: (context) => _availableLocales
                              .map(
                                (locale) => PopupMenuItem(
                                  value: locale,
                                  child: Row(
                                    children: [
                                      if (locale.localeId == _selectedLocale?.localeId)
                                        const Icon(Icons.check, size: 16)
                                      else
                                        const SizedBox(width: 16),
                                      const SizedBox(width: 8),
                                      Text(locale.name),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                if (!widget.disabled) ...[
                  const Spacer(),
                  InkIcon(
                    icon: CupertinoIcons.arrow_up_circle,
                    onTap: () {
                      if (widget.disabled || textController.text.trim().isEmpty) {
                        return;
                      }
                      widget.onSubmitted(SubmitData(textController.text, _selectedFiles));
                      _afterSubmitted();
                    },
                    tooltip: AppLocalizations.of(context)!.send,
                  ),
                ] else ...[
                  const Spacer(),
                  InkIcon(
                    icon: CupertinoIcons.stop,
                    onTap: widget.onCancel != null
                        ? () {
                            widget.onCancel!();
                          }
                        : null,
                    tooltip: AppLocalizations.of(context)!.cancel,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
