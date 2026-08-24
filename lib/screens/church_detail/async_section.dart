import 'package:flutter/material.dart';

/// Wraps any Future<T> and handles loading/error/empty states the same
/// way everywhere - the exact bug we kept hitting (a missing snap.hasError
/// check silently hanging on a permission error) can't happen if every
/// async section in the app goes through this one place instead of a
/// hand-written FutureBuilder each time.
///
/// Usage:
///   AsyncSection<List<Foo>>(
///     future: FirestoreService().getFoos(id),
///     isEmpty: (list) => list.isEmpty,
///     emptyMessage: 'Nothing here yet.',
///     builder: (context, foos) => Column(children: foos.map(...).toList()),
///   )
class AsyncSection<T> extends StatelessWidget {
  final Future<T> future;
  final Widget Function(BuildContext context, T data) builder;
  final bool Function(T data)? isEmpty;
  final String emptyMessage;
  final Widget? loading;

  const AsyncSection({
    super.key,
    required this.future,
    required this.builder,
    this.isEmpty,
    this.emptyMessage = 'Nothing here yet.',
    this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snap) {
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('Could not load this: ${snap.error}',
                style: const TextStyle(fontSize: 12, color: Colors.redAccent)),
          );
        }
        if (!snap.hasData) {
          return loading ?? const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: LinearProgressIndicator());
        }
        final data = snap.data as T;
        if (isEmpty != null && isEmpty!(data)) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(emptyMessage, style: const TextStyle(fontSize: 12, color: Colors.black45)),
          );
        }
        return builder(context, data);
      },
    );
  }
}
