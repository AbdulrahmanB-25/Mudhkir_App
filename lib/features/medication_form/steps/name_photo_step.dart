import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../data/services/medicine_catalog.dart';
import '../../../l10n/app_localizations.dart';
import '../../shared/common_widgets.dart';
import '../medication_form_view_model.dart';

class NamePhotoStep extends StatelessWidget {
  const NamePhotoStep({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final vm = context.watch<MedicationFormViewModel>();
    final catalog = context.read<MedicineCatalog>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          l10n.medicationNameLabel,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Autocomplete<String>(
          initialValue: TextEditingValue(text: vm.name),
          optionsBuilder: (value) => catalog.search(value.text),
          onSelected: vm.setName,
          fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
              TextField(
                controller: controller,
                focusNode: focusNode,
                textInputAction: TextInputAction.done,
                textCapitalization: TextCapitalization.words,
                onChanged: vm.setName,
                onSubmitted: (_) => onSubmitted(),
                decoration: InputDecoration(
                  hintText: l10n.medicationNameHint,
                  prefixIcon: const Icon(Icons.medication_rounded),
                ),
              ),
        ),
        const SizedBox(height: 24),
        Text(
          l10n.medicationPhotoLabel,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          l10n.medicationPhotoHint,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        _PhotoBox(path: vm.imagePath),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pick(context, ImageSource.camera),
                icon: const Icon(Icons.photo_camera_rounded),
                label: Text(l10n.takePhoto),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pick(context, ImageSource.gallery),
                icon: const Icon(Icons.photo_library_rounded),
                label: Text(l10n.chooseFromGallery),
              ),
            ),
          ],
        ),
        if (vm.imagePath != null)
          TextButton.icon(
            onPressed: vm.removeImage,
            icon: const Icon(Icons.delete_outline_rounded),
            label: Text(l10n.removePhoto),
          ),
      ],
    );
  }

  Future<void> _pick(BuildContext context, ImageSource source) async {
    final vm = context.read<MedicationFormViewModel>();
    final l10n = AppLocalizations.of(context);
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1280,
        imageQuality: 80,
      );
      if (file != null) await vm.setImage(file.path);
    } catch (_) {
      if (context.mounted) showMessage(context, l10n.photoError, error: true);
    }
  }
}

class _PhotoBox extends StatelessWidget {
  const _PhotoBox({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final path = this.path;
    return AspectRatio(
      aspectRatio: 16 / 10,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: path == null
            ? Icon(
                Icons.add_a_photo_outlined,
                size: 56,
                color: scheme.primary.withValues(alpha: 0.6),
              )
            : Image.file(File(path), fit: BoxFit.cover),
      ),
    );
  }
}
