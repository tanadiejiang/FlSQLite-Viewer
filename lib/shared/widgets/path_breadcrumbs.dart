import 'package:flutter/material.dart';

class PathBreadcrumbs extends StatelessWidget {
  final List<String> segments;
  final ValueChanged<String> onSegmentTap;
  final bool compact;

  const PathBreadcrumbs({
    super.key,
    required this.segments,
    required this.onSegmentTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (compact) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (int i = 0; i < segments.length; i++) ...[
              _buildSegmentChip(context, i),
              if (i < segments.length - 1)
                Icon(Icons.chevron_right,
                    size: 16, color: theme.colorScheme.onSurfaceVariant),
            ],
          ],
        ),
      );
    }

    return Wrap(
      spacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (int i = 0; i < segments.length; i++) ...[
          _buildSegmentChip(context, i),
          if (i < segments.length - 1)
            Icon(Icons.chevron_right,
                size: 16, color: theme.colorScheme.onSurfaceVariant),
        ],
      ],
    );
  }

  Widget _buildSegmentChip(BuildContext context, int index) {
    final path = segments.take(index + 1).join('/').replaceAll('//', '/');
    if (path.isEmpty || path == '/') {
      return ActionChip(
        label: const Text('/'),
        onPressed: () => onSegmentTap('/'),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        visualDensity: VisualDensity.compact,
      );
    }
    return ActionChip(
      label: Text(segments[index]),
      onPressed: () => onSegmentTap(path),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      visualDensity: VisualDensity.compact,
    );
  }
}