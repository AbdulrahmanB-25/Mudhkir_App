import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/medication_repository.dart';
import '../../domain/models/local_date.dart';
import '../../domain/models/medication.dart';
import '../../l10n/app_localizations.dart';
import '../shared/common_widgets.dart';
import '../shared/formatters.dart';
import '../shared/medication_avatar.dart';

/// All of the user's medications, current and finished.
class MedicationsScreen extends StatelessWidget {
  const MedicationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ownerId = context.select<AuthRepository, String>((a) => a.ownerId);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.myMedications)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.newMedication()),
        icon: const Icon(Icons.add_rounded),
        label: Text(l10n.addMedication),
      ),
      body: WatchBuilder<List<Medication>>(
        streamKey: ownerId,
        create: () => context.read<MedicationRepository>().watchAll(ownerId),
        builder: (context, snapshot) {
          final all = snapshot.data;
          if (all == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (all.isEmpty) {
            return Center(
              child: EmptyState(
                icon: Icons.medication_outlined,
                title: l10n.homeEmptyTitle,
                message: l10n.homeEmptyMessage,
              ),
            );
          }
          final today = LocalDate.fromDateTime(DateTime.now());
          final current = all.where((m) => !m.isFinishedOn(today)).toList();
          final finished = all.where((m) => m.isFinishedOn(today)).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              if (current.isNotEmpty) SectionTitle(l10n.currentMedications),
              for (final m in current) _MedicationCard(medication: m),
              if (finished.isNotEmpty) SectionTitle(l10n.finishedMedications),
              for (final m in finished)
                _MedicationCard(medication: m, finished: true),
            ],
          );
        },
      ),
    );
  }
}

class _MedicationCard extends StatelessWidget {
  const _MedicationCard({required this.medication, this.finished = false});

  final Medication medication;
  final bool finished;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Opacity(
        opacity: finished ? 0.6 : 1,
        child: Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 8,
            ),
            leading: MedicationAvatar(medication: medication),
            title: Text(medication.name, style: theme.textTheme.titleMedium),
            subtitle: Text(
              '${context.dosageText(medication)} • ${context.scheduleSummary(medication)}',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push(Routes.medication(medication.id)),
          ),
        ),
      ),
    );
  }
}
