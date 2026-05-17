import 'package:flutter/material.dart';

import '../../data/app_enums.dart';
import '../../format/fiat.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../services/app_haptics.dart';
import '../../theme/theme.dart';
import '../../widgets/scroll_hairline.dart';

const int _kCurrencyMajorsCount = 3;

/// Multi-select for the currencies that appear in the home-screen swipe ring.
/// Returns the current selection via Navigator.pop when the user taps back —
/// the gesture is intercepted with [PopScope] so even system-back returns the
/// list, not null.
class CurrencyPickerScreen extends StatefulWidget {
  const CurrencyPickerScreen({super.key, required this.initial});

  final List<Currency> initial;

  @override
  State<CurrencyPickerScreen> createState() => _CurrencyPickerScreenState();
}

class _CurrencyPickerScreenState extends State<CurrencyPickerScreen> {
  late final List<Currency> _picked = [...widget.initial];

  void _toggle(Currency c) {
    setState(() {
      if (_picked.contains(c)) {
        if (_picked.length == 1) return;
        _picked.remove(c);
      } else {
        _picked.add(c);
      }
    });
    AppHaptics.selection();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final all = Currency.values;

    Widget tile(Currency c) {
      final checked = _picked.contains(c);
      final blocked = checked && _picked.length == 1;
      return CheckboxListTile(
        key: ValueKey('currency-${c.code}'),
        value: checked,
        onChanged: blocked ? (_) {} : (_) => _toggle(c),
        controlAffinity: ListTileControlAffinity.leading,
        title: Text.rich(TextSpan(children: [
          TextSpan(text: c.code, style: const TextStyle(fontWeight: FontWeight.bold)),
          TextSpan(text: ' - ${currencyLabel(l10n, c)}'),
        ])),
      );
    }

    final cs = Theme.of(context).colorScheme;
    return PopScope<List<Currency>>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop(_picked);
      },
      child: Scaffold(
        backgroundColor: cs.surfaceContainerLow,
        appBar: AppBar(
          backgroundColor: cs.surfaceContainerLow,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: BackButton(
            color: cs.onSurfaceVariant,
            onPressed: () => Navigator.of(context).pop(_picked),
          ),
          centerTitle: true,
          title: Text(
            AppLocalizations.of(context).settingsCurrencies,
            style: AppTypography.title.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        body: ScrollHairline(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                child: Text(
                  AppLocalizations.of(context).currencyPickerHint,
                  style: AppTypography.body.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
              for (final c in all.take(_kCurrencyMajorsCount)) tile(c),
              Divider(
                height: 1,
                thickness: 1,
                indent: 16,
                endIndent: 16,
                color: cs.outlineVariant,
              ),
              for (final c in all.skip(_kCurrencyMajorsCount)) tile(c),
            ],
          ),
        ),
      ),
    );
  }
}
