import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/dose_log_repository.dart';
import '../../data/repositories/medication_repository.dart';
import '../../l10n/app_localizations.dart';
import 'schedule_view.dart';
import 'schedule_view_model.dart';

class ScheduleScreen extends StatelessWidget {
  const ScheduleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ownerId = context.select<AuthRepository, String>((a) => a.ownerId);
    return ChangeNotifierProvider(
      key: ValueKey(ownerId),
      create: (context) => ScheduleViewModel(
        ownerId: ownerId,
        medications: context.read<MedicationRepository>(),
        logs: context.read<DoseLogRepository>(),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.scheduleTitle),
          actions: [
            IconButton(
              tooltip: l10n.myMedications,
              onPressed: () => context.push(Routes.medications),
              icon: const Icon(Icons.medication_rounded),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          tooltip: l10n.addMedication,
          onPressed: () => context.push(Routes.newMedication()),
          child: const Icon(Icons.add_rounded),
        ),
        body: ScheduleView(
          emptyAction: FilledButton.icon(
            onPressed: () => context.push(Routes.newMedication()),
            icon: const Icon(Icons.add_rounded),
            label: Text(l10n.addFirstMedication),
          ),
        ),
      ),
    );
  }
}
