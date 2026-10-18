import 'package:flutter/material.dart';

import 'settings_section.dart';

/// Keeps the settings row and its modal choice interaction together.
class SettingsChoiceTile<T> extends StatelessWidget {
  const SettingsChoiceTile({
    super.key,
    required this.title,
    required this.sheetTitle,
    required this.leadingIcon,
    required this.current,
    required this.values,
    required this.label,
    required this.icon,
    required this.onSelected,
  });

  final String title;
  final String sheetTitle;
  final IconData leadingIcon;
  final T current;
  final List<T> values;
  final String Function(T) label;
  final IconData Function(T) icon;
  final Future<void> Function(T) onSelected;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: settingsLeading(context, leadingIcon),
    title: Text(title),
    subtitle: Text(label(current)),
    trailing: const Icon(Icons.chevron_right, size: 20),
    onTap: () => _choose(context),
  );

  Future<void> _choose(BuildContext context) async {
    final selected = await showModalBottomSheet<T>(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (context) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Text(
                  sheetTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              for (final value in values)
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  selected: value == current,
                  selectedTileColor: Theme.of(context)
                      .colorScheme
                      .secondaryContainer,
                  selectedColor: Theme.of(context)
                      .colorScheme
                      .onSecondaryContainer,
                  leading: settingsLeading(context, icon(value)),
                  title: Text(label(value)),
                  trailing: value == current
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () => Navigator.pop(context, value),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) await onSelected(selected);
  }
}
