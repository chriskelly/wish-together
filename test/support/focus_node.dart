import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The focus node of the editable text inside [field].
///
/// A page can render other [EditableText]s — the support code is selectable
/// text — so the field scopes the lookup.
FocusNode focusNodeOf(WidgetTester tester, Finder field) => tester
    .widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    )
    .focusNode;
