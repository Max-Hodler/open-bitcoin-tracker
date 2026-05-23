import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/stack.dart' as model;
import '../../theme/theme.dart';

/// Centered, underlined TextField used by the new-stack and edit-stack name
/// screens. Caps the input at [model.Stack.maxNameLength] and matches the
/// caret height used by [BlinkingCaret] elsewhere in the app so the cursor
/// reads consistently across screens.
class StackNameField extends StatelessWidget {
  const StackNameField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final p = context.palette;
    // Hide the Material selection drop handle (the orange "tear" under the
    // caret). Long-press still reveals the system Cut/Copy/Paste toolbar.
    return Theme(
      data: theme.copyWith(
        textSelectionTheme: theme.textSelectionTheme.copyWith(
          selectionHandleColor: Colors.transparent,
        ),
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        textAlign: TextAlign.center,
        textInputAction: TextInputAction.done,
        textCapitalization: TextCapitalization.sentences,
        cursorColor: cs.onSurface,
        // Match BlinkingCaret on the amount/converter screens (fontSize * 1.2)
        // instead of the SDK default which renders to the full line height.
        cursorHeight: 28 * 1.2,
        inputFormatters: [
          LengthLimitingTextInputFormatter(model.Stack.maxNameLength),
        ],
        onSubmitted: onSubmitted,
        style: AppTypography.title.copyWith(
          fontSize: 28,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          filled: false,
          contentPadding: const EdgeInsets.only(bottom: AppSpacing.xs),
          border: UnderlineInputBorder(
            borderSide: BorderSide(color: cs.outlineVariant),
          ),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: cs.outlineVariant),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: p.bitcoinOrange),
          ),
        ),
      ),
    );
  }
}
