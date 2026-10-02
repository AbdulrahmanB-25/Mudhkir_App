import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/dose_log_repository.dart';
import '../../data/repositories/medication_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../domain/models/dose.dart';
import '../../domain/models/profile.dart';
import '../../l10n/app_localizations.dart';
import '../shared/common_widgets.dart';
import '../shared/dose_actions.dart';
import '../shared/dose_tile.dart';
import '../shared/formatters.dart';
import '../shared/medication_avatar.dart';
import 'home_view_model.dart';
import 'reminder_permission_banner.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ownerId = context.select<AuthRepository, String>((a) => a.ownerId);
    return ChangeNotifierProvider(
      // A new view model when the account changes.
      key: ValueKey(ownerId),
      create: (context) => HomeViewModel(
        ownerId: ownerId,
        medications: context.read<MedicationRepository>(),
        logs: context.read<DoseLogRepository>(),
      ),
      child: const _HomeView(),
    );
  }
}

class _HomeView extends StatelessWidget {
  const _HomeView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final vm = context.watch<HomeViewModel>();
    final auth = context.watch<AuthRepository>();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.appTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.newMedication()),
        icon: const Icon(Icons.add_rounded),
        label: Text(l10n.addMedication),
      ),
      body: vm.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                WatchBuilder<Profile?>(
                  streamKey: auth.ownerId,
                  create: () =>
                      context.read<ProfileRepository>().watch(auth.ownerId),
                  builder: (context, snapshot) =>
                      _Greeting(name: snapshot.data?.name ?? auth.displayName),
                ),
                const ReminderPermissionBanner(),
                if (!auth.isSignedIn && auth.cloudAvailable)
                  const _AccountBanner(),
                const SizedBox(height: 12),
                if (!vm.hasMedications)
                  EmptyState(
                    icon: Icons.medication_outlined,
                    title: l10n.homeEmptyTitle,
                    message: l10n.homeEmptyMessage,
                    action: FilledButton.icon(
                      onPressed: () => context.push(Routes.newMedication()),
                      icon: const Icon(Icons.add_rounded),
                      label: Text(l10n.addFirstMedication),
                    ),
                  )
                else ...[
                  _NextDoseCard(dose: vm.nextDose),
                  SectionTitle(
                    l10n.todayDoses,
                    trailing: vm.todayDoses.isEmpty
                        ? null
                        : Text(
                            l10n.takenOfTotal(
                              vm.takenToday,
                              vm.todayDoses.length,
                            ),
                          ),
                  ),
                  if (vm.todayDoses.isEmpty)
                    EmptyState(
                      icon: Icons.event_available_rounded,
                      title: l10n.noDosesToday,
                    )
                  else
                    for (final dose in vm.todayDoses) ...[
                      DoseTile(dose: dose),
                      const SizedBox(height: 10),
                    ],
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => context.push(Routes.medications),
                    icon: const Icon(Icons.medication_rounded),
                    label: Text(l10n.myMedications),
                  ),
                ],
              ],
            ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({this.name});

  final String? name;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? l10n.goodMorning : l10n.goodEvening;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name == null || name!.isEmpty
                ? greeting
                : l10n.greetingWithName(greeting, name!),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            context.formatDayHeader(DateTime.now()),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _NextDoseCard extends StatelessWidget {
  const _NextDoseCard({required this.dose});

  final DoseInstance? dose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dose = this.dose;
    final onPrimary = theme.colorScheme.onPrimary;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [theme.colorScheme.primary, theme.colorScheme.secondary],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: dose == null
          ? Row(
              children: [
                Icon(Icons.celebration_rounded, color: onPrimary, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.noUpcomingDoses,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: onPrimary,
                    ),
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dose.status == DoseStatus.due
                      ? l10n.doseDueNow
                      : l10n.nextDose,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: onPrimary.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    MedicationAvatar(medication: dose.medication, size: 60),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dose.medication.name,
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: onPrimary,
                            ),
                          ),
                          Text(
                            context.dosageText(dose.medication),
                            style: TextStyle(color: onPrimary),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      children: [
                        Icon(Icons.alarm_rounded, color: onPrimary),
                        Text(
                          context.formatTime(dose.effectiveAt),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: onPrimary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: onPrimary,
                          foregroundColor: theme.colorScheme.primary,
                        ),
                        onPressed: () async {
                          await DoseActions.of(context).take(dose);
                          if (context.mounted) {
                            showMessage(context, l10n.doseMarkedTaken);
                          }
                        },
                        icon: const Icon(Icons.check_rounded),
                        label: Text(l10n.actionTake),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.outlined(
                      style: IconButton.styleFrom(
                        foregroundColor: onPrimary,
                        side: BorderSide(color: onPrimary),
                        minimumSize: const Size(54, 54),
                      ),
                      tooltip: l10n.moreActions,
                      onPressed: () => showDoseActionsSheet(context, dose),
                      icon: const Icon(Icons.more_horiz_rounded),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _AccountBanner extends StatelessWidget {
  const _AccountBanner();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        child: ListTile(
          leading: const Icon(Icons.cloud_upload_outlined),
          title: Text(l10n.accountBannerTitle),
          subtitle: Text(l10n.accountBannerMessage),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => context.push(Routes.signup),
        ),
      ),
    );
  }
}
