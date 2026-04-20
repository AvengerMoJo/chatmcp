import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class LlmIcon extends StatelessWidget {
  final String icon;
  final Color? color;
  final double size;
  final String? tooltip;

  const LlmIcon({
    super.key,
    required this.icon,
    this.color,
    this.size = 16, // 基础默认值保持为常量16
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    // 在build方法中根据平台动态设置尺寸
    final double effectiveSize = size != 16
        ? size
        : (kIsWeb
              ? 16.0
              : (Platform.isAndroid || Platform.isIOS)
              ? 24.0
              : 16.0);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultColor = isDark ? Colors.white : Colors.black;

    final Widget iconWidget;
    if (icon.isNotEmpty) {
      final svgPath = 'assets/logo/$icon.svg';
      final pngPath = 'assets/logo/$icon.png';
      iconWidget = ColorAwareSvg(assetName: svgPath, fallbackPngPath: pngPath, size: effectiveSize, color: color ?? defaultColor);
    } else {
      iconWidget = ColorAwareSvg(assetName: 'assets/logo/ai-chip.svg', size: effectiveSize, color: color ?? defaultColor);
    }

    if (tooltip == null) {
      return iconWidget;
    }

    return Tooltip(message: tooltip!, child: iconWidget);
  }
}

class ColorAwareSvg extends StatelessWidget {
  final String assetName;
  final String? fallbackPngPath;
  final double size;
  final Color color;

  const ColorAwareSvg({
    super.key,
    required this.assetName,
    this.fallbackPngPath,
    required this.size,
    required this.color,
  });

  // 保存检测结果的静态缓存，避免重复检测
  static final Map<String, bool> _colorCache = {};

  // 检测SVG是否包含非黑白颜色
  Future<bool> _detectSvgHasColors(BuildContext context) async {
    // 如果缓存中有结果，直接返回
    if (_colorCache.containsKey(assetName)) {
      return _colorCache[assetName]!;
    }

    try {
      // 加载SVG文件内容
      final String svgString = await rootBundle.loadString(assetName);

      // 检查是否包含颜色相关属性（简化版）
      bool hasColor = false;

      // 检查是否包含除了黑白之外的颜色
      if (svgString.contains('fill="#') || svgString.contains('stroke="#')) {
        // 排除纯黑色 (#000000) 和纯白色 (#FFFFFF)
        hasColor =
            !svgString.contains('fill="#000000"') &&
            !svgString.contains('fill="#ffffff"') &&
            !svgString.contains('stroke="#000000"') &&
            !svgString.contains('stroke="#ffffff"');
      }

      // 检查是否包含 rgb/rgba/hsl 颜色
      if (!hasColor) {
        hasColor =
            svgString.contains('fill="rgb') ||
            svgString.contains('stroke="rgb') ||
            svgString.contains('fill="hsl') ||
            svgString.contains('stroke="hsl');
      }

      if (svgString.contains("style") || svgString.contains("color")) {
        hasColor = true;
      }

      _colorCache[assetName] = hasColor;
      return hasColor;
    } catch (e) {
      // 出错时假设没有颜色
      _colorCache[assetName] = false;
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final assetExists = _assetExistsSync(assetName);
    
    if (!assetExists && fallbackPngPath != null) {
      return Image.asset(
        fallbackPngPath!,
        width: size,
        height: size,
        errorBuilder: (context, error, stackTrace) => Icon(CupertinoIcons.cloud, size: size),
      );
    }
    
    return FutureBuilder<bool>(
      future: _detectSvgHasColors(context),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return SizedBox(width: size, height: size, child: const CircularProgressIndicator(strokeWidth: 2));
        }

        final hasOwnColors = snapshot.data ?? false;
        return SvgPicture.asset(
          assetName,
          width: size,
          height: size,
          allowDrawingOutsideViewBox: true,
          placeholderBuilder: (context) => Icon(CupertinoIcons.cloud, size: size),
          colorFilter: hasOwnColors ? null : ColorFilter.mode(color, BlendMode.srcIn),
        );
      },
    );
  }
  
  bool _assetExistsSync(String path) {
    try {
      rootBundle.load(path);
      return true;
    } catch (e) {
      return false;
    }
  }
}
