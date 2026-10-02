import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/companion_repository.dart';
import '../../data/repositories/dose_log_repository.dart';
import '../../data/repositories/medication_repository.dart';
import '../../data/sync/sync_service.dart';
import '../../domain/models/companion_link.dart';
import '../../l10n/app_localizations.dart';
import '../schedule/schedule_view.dart';
import '../schedule/schedule_view_model.dart';
import '../shared/common_widgets.dart';
import 'invite_dialog.dart';

/// The schedule of someone the user looks after. The caregiver can record
/// doses and add or change their medications.
class CompanionDetailScreen extends StatelessWidget {
  const CompanionDetailScreen({required this.patientId, super.key});

  final String patientId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final me = context.select<AuthRepository, String>((a) => a.ownerId);
    final companions = context.read<CompanionRepository>();

    return WatchBuilder<List<CompanionLink>>(
      streamKey: me,
      create: () => companions.watchLinks(me),
      builder: (context, snapshot) {
        final link = snapshot.data
            ?.where(
              (l) =>
                  l.caregiverId == me &&
                  l.patientId == patientId &&
                  l.isAccepted,
            )
            .firstOrNull;
        if (snapshot.data == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (link == null) {
          return Scaffold(
            appBar: AppBar(),
            body: EmptyState(
              icon: Icons.link_off_rounded,
              title: l10n.companionNotAvailable,
            ),
          );
        }
        final name = link.patientName ?? link.patientEmail ?? '';
        return ChangeNotifierProvider(
          create: (context) => ScheduleViewModel(
            ownerId: patientId,
            medications: context.read<MedicationRepository>(),
            logs: context.read<DoseLogRepository>(),
          ),
          child: Scaffold(
            appBar: AppBar(
              title: Text(name),
              actions: [
                PopupMenuButton<String>(
                  onSelected: (value) => _onMenu(context, link, value),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text(l10n.editCompanion),
                    ),
                    PopupMenuItem(
                      value: 'remove',
                      child: Text(l10n.removeCompanion),
                    ),
                  ],
                ),
              ],
            ),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () =>
                  context.push(Routes.newMedication(ownerId: patientId)),
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.addMedicationFor(name)),
            ),
            body: RefreshIndicator(
              onRefresh: context.read<SyncService>().syncNow,
              child: ScheduleView(
                header: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.favorite_rounded),
                      ),
                      title: Text(name),
                      subtitle: Text(
                        [
                          link.relationship,
                          link.patientEmail,
                        ].whereType<String>().join(' • '),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _onMenu(
    BuildContext context,
    CompanionLink link,
    String value,
  ) async {
    final l10n = AppLocalizations.of(context);
    final companions = context.read<CompanionRepository>();
    switch (value) {
      case 'edit':
        final result = await showDialog<InviteRequest>(
          context: context,
          builder: (_) => InviteDialog(
            editOnly: true,
            initialName: link.patientName,
            initialRelationship: link.relationship,
          ),
        );
        if (result != null) {
          await companions.rename(link.id, result.name, result.relationship);
        }
      case 'remove':
        if (await confirm(
          context,
          title: l10n.removeCompanion,
          message: l10n.removeCompanionConfirm(link.patientName ?? ''),
          confirmLabel: l10n.removeCompanion,
          destructive: true,
        )) {
          await companions.remove(link.id);
          if (context.mounted) context.pop();
        }
    }
  }
}
