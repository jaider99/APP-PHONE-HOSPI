import 'package:flutter/material.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';

enum AddOption { photoLibrary, chooseFile }

/// Modal bottom sheet for the Add button — pick from gallery or file system.
class AddOptionsSheet extends StatelessWidget {
  const AddOptionsSheet({super.key});

  static Future<AddOption?> show(BuildContext context) {
    return showModalBottomSheet<AddOption>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      builder: (_) => const AddOptionsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: EditorialColors.background,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: EditorialColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(9999),
                ),
              ),
            ),

            // Title
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Choose from options',
                  style: EditorialTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),

            // Photo Library option
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _OptionTile(
                icon: Icons.photo_library_outlined,
                title: 'Photo Library',
                subtitle: 'Pick an image from your gallery',
                onTap: () => Navigator.pop(context, AddOption.photoLibrary),
              ),
            ),

            const SizedBox(height: 8),

            // Choose File option
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _OptionTile(
                icon: Icons.folder_outlined,
                title: 'Choose File',
                subtitle: 'Import PDF, JPG, PNG or other docs',
                onTap: () => Navigator.pop(context, AddOption.chooseFile),
              ),
            ),

            // Extra clearance for floating nav pill
            SizedBox(
              height: 24 + MediaQuery.of(context).viewPadding.bottom + 72,
            ),
          ],
        ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _OptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: EditorialColors.surfaceContainerLowest,
      borderRadius: EditorialRadius.borderRadiusStandard,
      child: InkWell(
        onTap: onTap,
        borderRadius: EditorialRadius.borderRadiusStandard,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              // Leading icon box
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: EditorialColors.surfaceContainerLow,
                  borderRadius: EditorialRadius.borderRadiusMd,
                ),
                child: Icon(icon, color: EditorialColors.onSurface, size: 22),
              ),
              const SizedBox(width: 14),

              // Title & subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: EditorialTypography.labelLarge,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: EditorialTypography.bodySmall.copyWith(
                        color: EditorialColors.outline,
                      ),
                    ),
                  ],
                ),
              ),

              // Trailing chevron
              const Icon(
                Icons.chevron_right,
                color: EditorialColors.outlineVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
