import 'dart:io';

import 'package:flutter/material.dart';

import '../../domain/models/medication.dart';

/// The medication's photo, or a pill icon when there is none.
class MedicationAvatar extends StatelessWidget {
  const MedicationAvatar({required this.medication, this.size = 52, super.key});

  final Medication medication;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final path = medication.imagePath;
    final radius = BorderRadius.circular(size * 0.3);
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: radius,
      ),
      child: Icon(
        Icons.medication_rounded,
        color: scheme.onPrimaryContainer,
        size: size * 0.55,
      ),
    );
    if (path == null) return fallback;
    return ClipRRect(
      borderRadius: radius,
      child: Image.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * 3).round(),
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}
