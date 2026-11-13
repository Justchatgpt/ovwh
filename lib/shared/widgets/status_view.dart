import 'package:flutter/material.dart';

/// Generic loading / empty / error placeholder.
class StatusView extends StatelessWidget {
  const StatusView({
    super.key,
    this.loading = false,
    this.error,
    this.empty = false,
    this.emptyText = '暂无内容',
    this.onRetry,
  });

  final bool loading;
  final String? error;
  final bool empty;
  final String emptyText;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 42, color: Colors.white38),
              const SizedBox(height: 10),
              Text(error!, textAlign: TextAlign.center),
              if (onRetry != null) ...[
                const SizedBox(height: 12),
                OutlinedButton(onPressed: onRetry, child: const Text('重试')),
              ],
            ],
          ),
        ),
      );
    }
    if (empty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.inbox_outlined, size: 42, color: Colors.white38),
              const SizedBox(height: 10),
              Text(emptyText),
            ],
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
