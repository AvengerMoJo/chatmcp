import 'package:chatmcp/components/widgets/base.dart';
import 'package:flutter/material.dart';

import 'package:markdown_widget/markdown_widget.dart';
import 'package:chatmcp/utils/color.dart';
import 'package:chatmcp/generated/app_localizations.dart';
import 'tag.dart';
import 'package:chatmcp/widgets/expandable_widget.dart';
import 'package:chatmcp/widgets/markdown/markit_widget.dart';

const _functionResultTag = 'call_function_result';

class FunctionResultInlineSyntax extends TagInlineSyntax {
  FunctionResultInlineSyntax() : super(tag: _functionResultTag);
}

class FunctionResultBlockSyntax extends TagBlockSyntax {
  FunctionResultBlockSyntax() : super(tag: _functionResultTag);
}

SpanNodeGeneratorWithTag functionResultGenerator = SpanNodeGeneratorWithTag(
  tag: _functionResultTag,
  generator: (e, config, visitor) => FunctionResultNode(e.attributes, e.textContent, config),
);

class FunctionResultNode extends SpanNode {
  final Map<String, String> attributes;
  final String textContent;
  final MarkdownConfig config;

  FunctionResultNode(this.attributes, this.textContent, this.config);

  @override
  InlineSpan build() {
    bool isClosed = attributes['closed'] == 'true';
    return WidgetSpan(child: FunctionResultWidget(textContent, isClosed, attributes));
  }
}

class FunctionResultWidget extends StatefulWidget {
  final String textContent;
  final bool isClosed;
  final Map<String, String> attributes;

  const FunctionResultWidget(this.textContent, this.isClosed, this.attributes, {super.key});

  @override
  State<FunctionResultWidget> createState() => _FunctionResultWidgetState();
}

class _FunctionResultWidgetState extends State<FunctionResultWidget> {
  bool _isExpanded = false;

  IconData _getToolIcon() {
    final toolName = widget.attributes['name']?.toLowerCase() ?? '';

    if (toolName == 'fetch') {
      return Icons.cloud_download;
    } else if (toolName.contains('search')) {
      return Icons.search;
    } else if (toolName.contains('google') || toolName.contains('sheet')) {
      return Icons.table_chart;
    }
    return Icons.build_outlined;
  }

  @override
  Widget build(BuildContext context) {
    var t = AppLocalizations.of(context)!;
    String toolName = widget.attributes['name'] ?? 'tool';
    String contentLength = widget.textContent.length.toString();

    return ExpandableWidget(
      backgroundColor: AppColors.getFunctionBackgroundColor(context),
      initiallyExpanded: false,
      onExpandChanged: () {
        setState(() {
          _isExpanded = !_isExpanded;
        });
      },
      header: ExpandableRow(
        isExpanded: _isExpanded,
        children: [
          Icon(_getToolIcon(), size: 14, color: AppColors.getFunctionIconColor(context)),
          Gap(size: 4),
          Expanded(
            child: Text(
              "${t.toolResult(toolName)} [$contentLength chars]",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.getFunctionTextColor(context), fontSize: 12),
            ),
          ),
          if (!widget.isClosed)
            SizedBox(width: 12, height: 12, child: CircularProgressIndicator(color: AppColors.getProgressIndicatorColor(context), strokeWidth: 1.5)),
        ],
      ),
      expandedContent: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: AppColors.getFunctionIconColor(context).withAlpha(128), width: 3)),
        ),
        padding: const EdgeInsets.only(left: 12),
        child: Markit(data: widget.textContent),
      ),
      contentPadding: const EdgeInsets.only(left: 5),
    );
  }
}
