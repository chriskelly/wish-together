import 'package:flutter/material.dart';
import 'package:wishtogether/common/widgets/list_content_builder.dart';

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
        // A new stream identity — a parent rebuild passing a freshly built
        // stream — makes the snapshot report `waiting` while it keeps the
        // previous data and error. Both are cleared here so the resubscribe
        // shows the loading state, which is what this widget has always done.
        final waiting = snapshot.connectionState == ConnectionState.waiting;
        return ListContentBuilder<T>(
          items: waiting ? null : (snapshot.hasData ? snapshot.data : <T>[]),
          error: waiting ? null : (snapshot.hasError ? snapshot.error : null),
          entityWidgetBuilder: entityWidgetBuilder,
          loadingWidget: loadingWidget,
          errorWidget: errorWidget,
          emptyWidget: emptyWidget,
          emptyMessage: emptyMessage,
          isScrollable: isScrollable,
          listPadding: listPadding,
        );
      },
    );
  }
}
