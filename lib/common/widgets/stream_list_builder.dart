import 'package:flutter/material.dart';

// Defines a function signature for building a widget for an item of type T.
typedef EntityWidgetBuilder<T> = Widget Function(BuildContext context, T item);

class StreamListBuilder<T> extends StatelessWidget {
  final Stream<List<T>> stream;
  final EntityWidgetBuilder<T> entityWidgetBuilder;
  final Widget? loadingWidget;
  final Widget? errorWidget;
  final Widget? emptyWidget;

  /// Will only show if not using emptyWidget
  final String? emptyMessage;
  final bool isScrollable;
  final EdgeInsets? listPadding;

  const StreamListBuilder({
    super.key,
    required this.stream,
    required this.entityWidgetBuilder,
    this.loadingWidget,
    this.errorWidget,
    this.emptyWidget,
    this.emptyMessage,
    this.isScrollable = true, // Default to a standard, scrollable list
    this.listPadding,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<T>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return loadingWidget ??
              const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          // Reported at the data seam (FirebaseRepository); this widget only
          // decides what to render.
          return errorWidget ??
              Center(child: Text('An error occurred: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return emptyWidget ??
              Center(
                child: Text(
                  emptyMessage ?? "No items found",
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              );
        }

        final items = snapshot.data!;

        return ListView.builder(
          // Control scrolling behavior based on the isScrollable flag
          physics: isScrollable
              ? const AlwaysScrollableScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          shrinkWrap: !isScrollable, // Must be true for non-scrollable lists
          padding: listPadding,
          itemCount: items.length,
          itemBuilder: (context, index) {
            return entityWidgetBuilder(context, items[index]);
          },
        );
      },
    );
  }
}
