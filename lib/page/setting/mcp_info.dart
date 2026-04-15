import 'package:chatmcp/provider/provider_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../../provider/mcp_server_provider.dart';
import 'package:chatmcp/generated/app_localizations.dart';

// 定义工具的数据结构
class Tool {
  final String name;
  final String desc;

  Tool({required this.name, required this.desc});
}

class McpInfo extends StatelessWidget {
  final String serverName;

  const McpInfo({super.key, required this.serverName});

  Future<List<Tool>> _fetchTools(BuildContext context) async {
    final client = ProviderManager.mcpServerProvider.clients[serverName];
    if (client == null) {
      return [];
    }

    final resp = await client.sendToolList();
    if (resp.error != null) {
      return [];
    }
    final toolsData = resp.result['tools'] as List<dynamic>?; // Handle null case
    if (toolsData == null) {
      return [];
    }
    return toolsData.map((tool) => Tool(name: tool['name'] as String? ?? '', desc: tool['description'] as String? ?? '')).toList();
  }

  // Helper method to build an expandable card
  Widget _buildExpandableCard({
    required BuildContext context,
    required String title,
    required IconData iconData,
    required List<Widget> childrenWidgets,
    bool initiallyExpanded = false,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(iconData, color: Theme.of(context).colorScheme.primary),
          title: Text(
            title,
            style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
          ),
          initiallyExpanded: initiallyExpanded,
          childrenPadding: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
          children: childrenWidgets,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Consumer<McpServerProvider>(
      builder: (context, provider, child) {
        return FutureBuilder<List<Tool>>(
          future: _fetchTools(context),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CupertinoActivityIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(padding: const EdgeInsets.all(16.0), child: Text('${l10n.error}: ${snapshot.error}')),
              );
            }

            final tools = snapshot.data ?? <Tool>[];

            // Prepare children for the Tools card
            List<Widget> toolsChildren;
            if (tools.isNotEmpty) {
              toolsChildren = [
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: tools.length,
                  itemBuilder: (context, index) {
                    final tool = tools[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Theme.of(context).colorScheme.outline.withAlpha(26)),
                      ),
                      child: ListTile(
                        leading: Icon(CupertinoIcons.tag_fill, color: Theme.of(context).colorScheme.secondary),
                        title: Text(
                          tool.name,
                          style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
                        ),
                        subtitle: Text(tool.desc, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ),
                    );
                  },
                ),
              ];
            } else {
              toolsChildren = [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                  title: Text(
                    l10n.noToolsAvailable,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              ];
            }

            final sections = [
              {'title': l10n.mcpTools, 'icon': CupertinoIcons.wrench_fill, 'children': toolsChildren, 'initiallyExpanded': true},
              // {
              //   'title': "Resource", // TODO: Localize
              //   'icon': CupertinoIcons.archivebox_fill,
              //   'children': [
              //     ListTile(
              //       contentPadding: const EdgeInsets.symmetric(
              //           horizontal: 16.0, vertical: 16.0),
              //       title: Text(
              //         "No resource data available.", // TODO: Localize
              //         textAlign: TextAlign.center,
              //         style: TextStyle(
              //             color:
              //                 Theme.of(context).colorScheme.onSurfaceVariant),
              //       ),
              //     ),
              //   ],
              //   'initiallyExpanded': false,
              // },
              // {
              //   'title': "Prompt", // TODO: Localize
              //   'icon': CupertinoIcons.lightbulb_fill,
              //   'children': [
              //     ListTile(
              //       contentPadding: const EdgeInsets.symmetric(
              //           horizontal: 16.0, vertical: 16.0),
              //       title: Text(
              //         "No prompt data available.", // TODO: Localize
              //         textAlign: TextAlign.center,
              //         style: TextStyle(
              //             color:
              //                 Theme.of(context).colorScheme.onSurfaceVariant),
              //       ),
              //     ),
              //   ],
              //   'initiallyExpanded': false,
              // },
            ];

            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
              itemCount: sections.length,
              itemBuilder: (context, index) {
                final section = sections[index];
                return _buildExpandableCard(
                  context: context,
                  title: section['title'] as String,
                  iconData: section['icon'] as IconData,
                  childrenWidgets: section['children'] as List<Widget>,
                  initiallyExpanded: section['initiallyExpanded'] as bool,
                );
              },
              separatorBuilder: (context, index) => const SizedBox(height: 12),
            );
          },
        );
      },
    );
  }
}
