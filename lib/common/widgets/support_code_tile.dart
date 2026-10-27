import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shows the session's six-character support code with a copy action.
///
/// The code is derived from the launch session, not from the signed-in user, so
/// it can be read out on any screen state that has a facade.
class SupportCodeTile extends StatelessWidget {
  const SupportCodeTile({super.key, required this.supportCode});

  static const String title = 'Support code';
  static const String explanation =
      'Give this code to support to look up this session.';
  static const String copyTooltip = 'Copy support code';
  static const String copiedMessage = 'Support code copied';

  /// The six Crockford base32 symbols a user reads out.
  final String supportCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.confirmation_number_outlined),
      title: Text(title),
      subtitle: Text(explanation),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SelectableText(
            supportCode,
            style: theme.textTheme.titleMedium?.copyWith(letterSpacing: 2),
          ),
          IconButton(
            tooltip: copyTooltip,
            icon: const Icon(Icons.copy),
            onPressed: () => _copy(context),
          ),
        ],
      ),
    );
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: supportCode));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text(copiedMessage)));
  }
}
