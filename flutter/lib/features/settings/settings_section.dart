import 'package:flutter/material.dart';

class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.label,
    required this.children,
  });

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: Theme.of(context).colorScheme.primary),
          ),
        ),
        Card(
          child: Column(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                if (index > 0)
                  Divider(
                    height: 1,
                    indent: MediaQuery.textScalerOf(context).scale(1) >= 1.5
                        ? 16
                        : 52,
                    endIndent: 16,
                  ),
                children[index],
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

Widget? settingsLeading(BuildContext context, IconData icon) =>
    MediaQuery.textScalerOf(context).scale(1) >= 1.5
    ? null
    : Icon(icon, size: 24);
