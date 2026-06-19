import 'package:flutter/material.dart';

import '../data/data.dart' as model;
import '../services/app_haptics.dart';
import '../theme/theme.dart';
import '../widgets/stack_name/stack_name.dart';

/// Shared state and scaffold builder for the new-stack and edit-stack name
/// screens. Callers set [initialText] before calling super.initState() to
/// seed the text field with an existing value (edit flow).
mixin StackNameScreenMixin<T extends StatefulWidget> on State<T> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  /// Override before calling super.initState() to pre-populate the field.
  String? initialText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: initialText)
      ..addListener(() => setState(() {}));
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String get trimmed => _controller.text.trim();
  bool get isValid => trimmed.isNotEmpty;
  bool get atLimit => _controller.text.length >= model.Stack.maxNameLength;

  Widget buildNameScaffold({
    required BuildContext context,
    required ColorScheme cs,
    required String title,
    required String confirmLabel,
    required VoidCallback onSubmit,
  }) {
    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerLow,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: BackButton(
          color: cs.onSurfaceVariant,
          onPressed: () {
            AppHaptics.light();
            Navigator.of(context).maybePop();
          },
        ),
        centerTitle: true,
        title: Text(
          title,
          style: AppTypography.title.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    StackNameField(
                      controller: _controller,
                      focusNode: _focusNode,
                      onSubmitted: (_) => onSubmit(),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    StackNameLimitLabel(visible: atLimit),
                  ],
                ),
              ),
              StackNameConfirmButton(
                isValid: isValid,
                onTap: onSubmit,
                label: confirmLabel,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
