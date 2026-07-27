import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:random_movie/config/api_config.dart';
import 'package:random_movie/config/app_theme.dart';
import 'package:random_movie/models/models.dart';
import 'package:random_movie/providers/providers.dart';
import 'package:random_movie/widgets/collection/collection_icon.dart';
import 'package:random_movie/widgets/common/common_widgets.dart';

/// 合集页：手动合集 + 智能合集
class CollectionsPage extends StatefulWidget {
  const CollectionsPage({super.key});

  @override
  State<CollectionsPage> createState() => _CollectionsPageState();
}

class _CollectionsPageState extends State<CollectionsPage> {
  bool _requestedLoad = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requestedLoad) return;
    _requestedLoad = true;
    context.read<CollectionProvider>().ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的合集')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createCollection(context),
        icon: const Icon(Icons.add),
        label: const Text('新建合集'),
      ),
      body: Consumer<CollectionProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading && !provider.hasLoaded) {
            return const LoadingState(message: '加载中...');
          }
          if (provider.error != null &&
              provider.manualCollections.isEmpty &&
              provider.smartCollections.isEmpty) {
            return ErrorState(
              message: provider.error!,
              onRetry: provider.refresh,
            );
          }

          final manual = provider.manualCollections;
          final smart = provider.smartCollections;

          if (manual.isEmpty && smart.isEmpty) {
            return EmptyState(
              title: '还没有合集',
              subtitle: '把喜欢的电影归到一起，或等片库丰富后自动生成智能合集',
              icon: Icons.collections_bookmark_outlined,
              onAction: () => _createCollection(context),
              actionLabel: '新建合集',
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.spacingMedium,
              AppTheme.spacingMedium,
              AppTheme.spacingMedium,
              AppTheme.spacingXLarge * 3,
            ),
            children: [
              if (manual.isNotEmpty) ...[
                _sectionHeader(context, '手动合集'),
                const SizedBox(height: AppTheme.spacingSmall),
                _grid(context, manual, canDelete: true),
              ],
              if (smart.isNotEmpty) ...[
                const SizedBox(height: AppTheme.spacingLarge),
                _sectionHeader(
                  context,
                  '智能合集',
                  subtitle: '按类型 / 年代 / 导演 / 地区自动归类',
                ),
                const SizedBox(height: AppTheme.spacingSmall),
                _grid(context, smart, canDelete: false),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _sectionHeader(
    BuildContext context,
    String title, {
    String? subtitle,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(width: AppTheme.spacingSmall),
          Expanded(
            child: Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _grid(
    BuildContext context,
    List<MovieCollection> collections, {
    required bool canDelete,
  }) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.35,
        crossAxisSpacing: AppTheme.spacingMedium,
        mainAxisSpacing: AppTheme.spacingMedium,
      ),
      itemCount: collections.length,
      itemBuilder: (context, index) {
        final collection = collections[index];
        return _CollectionCard(
          collection: collection,
          onTap: () => context.push('/collections/detail', extra: collection),
          onLongPress: canDelete
              ? () => _collectionMenu(context, collection)
              : null,
        );
      },
    );
  }

  Future<void> _createCollection(BuildContext context) async {
    final result = await _showCollectionEditor(context);
    if (result == null) return;
    if (!context.mounted) return;
    await context.read<CollectionProvider>().createCollection(
      result.name,
      result.iconKey,
    );
  }

  Future<void> _collectionMenu(
    BuildContext context,
    MovieCollection collection,
  ) async {
    final provider = context.read<CollectionProvider>();
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('重命名 / 改图标'),
              onTap: () => Navigator.of(ctx).pop('edit'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: AppTheme.accent),
              title: Text('删除合集', style: TextStyle(color: AppTheme.accent)),
              onTap: () => Navigator.of(ctx).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (action == 'delete') {
      await provider.deleteCollection(collection.id);
    } else if (action == 'edit') {
      if (!context.mounted) return;
      final result = await _showCollectionEditor(context, existing: collection);
      if (result == null) return;
      await provider.renameCollection(collection, result.name);
      await provider.updateCollectionIcon(
        collection.copyWith(name: result.name),
        result.iconKey,
      );
    }
  }

  Future<({String name, String iconKey})?> _showCollectionEditor(
    BuildContext context, {
    MovieCollection? existing,
  }) {
    return showDialog<({String name, String iconKey})>(
      context: context,
      builder: (ctx) => _CollectionEditorDialog(existing: existing),
    );
  }
}

class _CollectionCard extends StatelessWidget {
  final MovieCollection collection;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _CollectionCard({
    required this.collection,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: SoftContainer(
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildPosterMosaic(context),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.1),
                      Colors.black.withValues(alpha: 0.75),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppTheme.spacingMedium),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        collectionIcon(collection.iconKey),
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          collection.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${collection.memberCount} 部',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPosterMosaic(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final posters = collection.previewPosters;
    if (posters.isEmpty) {
      return ColoredBox(color: colorScheme.surfaceContainerHighest);
    }
    if (posters.length == 1) {
      return _poster(posters.first, colorScheme);
    }
    return Row(
      children: [
        for (var i = 0; i < posters.length && i < 3; i++)
          Expanded(child: _poster(posters[i], colorScheme)),
      ],
    );
  }

  Widget _poster(String url, ColorScheme colorScheme) {
    return CachedNetworkImage(
      imageUrl: url,
      httpHeaders: ApiConfig.imageHeaders,
      fit: BoxFit.cover,
      memCacheWidth: 200,
      maxWidthDiskCache: 200,
      fadeInDuration: Duration.zero,
      placeholder: (_, _) =>
          ColoredBox(color: colorScheme.surfaceContainerHighest),
      errorWidget: (_, _, _) =>
          ColoredBox(color: colorScheme.surfaceContainerHighest),
    );
  }
}

class _CollectionEditorDialog extends StatefulWidget {
  final MovieCollection? existing;

  const _CollectionEditorDialog({this.existing});

  @override
  State<_CollectionEditorDialog> createState() =>
      _CollectionEditorDialogState();
}

class _CollectionEditorDialogState extends State<_CollectionEditorDialog> {
  late final TextEditingController _controller;
  late String _iconKey;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.existing?.name ?? '');
    _iconKey = widget.existing?.iconKey ?? MovieCollection.iconKeys.first;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      ),
      title: Text(widget.existing == null ? '新建合集' : '编辑合集'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: 20,
            decoration: const InputDecoration(
              hintText: '合集名称',
              counterText: '',
            ),
          ),
          const SizedBox(height: AppTheme.spacingMedium),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final key in MovieCollection.iconKeys)
                GestureDetector(
                  onTap: () => setState(() => _iconKey = key),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _iconKey == key
                          ? AppTheme.accent
                          : AppTheme.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      collectionIcon(key),
                      size: 20,
                      color: _iconKey == key ? Colors.white : AppTheme.accent,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
            final name = _controller.text.trim();
            if (name.isEmpty) return;
            Navigator.of(context).pop((name: name, iconKey: _iconKey));
          },
          style: TextButton.styleFrom(foregroundColor: AppTheme.accent),
          child: const Text(
            '保存',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
