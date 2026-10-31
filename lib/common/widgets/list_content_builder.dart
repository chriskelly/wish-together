import 'package:flutter/material.dart';

/// Defines a function signature for building a widget for an item of type T.
typedef EntityWidgetBuilder<T> = Widget Function(BuildContext context, T item);

/// Renders the four states of a list from plain values.
///
/// `StreamListBuilder` adapts a `Stream` to this widget. A caller that already
/// holds the current data — the home page, whose state owns its subscriptions —
/// passes it directly, so both paths render the same thing: an error, a loading
/// indicator, an empty placeholder, or the entries.
class ListContentBuilder<T> extends StatelessWidget {
  /// The current entries, or `null` while nothing has arrived yet.
  final List<T>? items;

  /// The failure to show in place of the entries, if any.
  final Object? error;

  final EntityWidgetBuilder<T> entityWidgetBuilder;
  final Widget? loadingWidget;
  final Widget? errorWidget;
  final Widget? emptyWidget;

  /// Will only show if not using [emptyWidget].
  final String? emptyMessage;
  final bool isScrollable;
  final EdgeInsets? listPadding;

  const ListContentBuilder({
    super.key,
    this.items,
    this.error,
    required this.entityWidgetBuilder,
    this.loadingWidget,
    this.errorWidget,
    this.emptyWidget,
    this.emptyMessage,
    this.isScrollable = true,
    this.listPadding,
  });

  @override
  Widget build(BuildContext context) {
    // An error outranks a missing value: a failed read has no entries to show,
    // and the caller that holds state keeps the two independent.
    if (error != null) {
      // Reported at the data seam (FirebaseRepository); this widget only
      // decides what to render.
      return errorWidget ?? Center(child: Text('An error occurred: $error'));
    }
    if (items == null) {
      return loadingWidget ?? const Center(child: CircularProgressIndicator());
    }

    final entries = items!;
    if (entries.isEmpty) {
      return emptyWidget ??
          Center(
            child: Text(
              emptyMessage ?? "No items found",
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          );
    }

    return ListView.builder(
      // Control scrolling behavior based on the isScrollable flag
      physics: isScrollable
          ? const AlwaysScrollableScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      shrinkWrap: !isScrollable, // Must be true for non-scrollable lists
      padding: listPadding,
      itemCount: entries.length,
      itemBuilder: (context, index) {
        return entityWidgetBuilder(context, entries[index]);
      },
    );
  }
}

/// The bordered, fixed-height box a data section shows when it has no entries.
class ListEmptyPlaceholder extends StatelessWidget {
  final String message;

  const ListEmptyPlaceholder({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 100,
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
      ),
    );
  }
}
