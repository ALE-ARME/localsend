import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:collection/collection.dart';
import 'package:common/model/device.dart';
import 'package:common/model/session_status.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/send_mode.dart';
import 'package:localsend_app/pages/receive_history_page.dart';
import 'package:localsend_app/pages/selected_files_page.dart';
import 'package:localsend_app/pages/tabs/receive_tab_vm.dart';
import 'package:localsend_app/pages/tabs/send_tab_vm.dart';
import 'package:localsend_app/pages/tabs/settings_tab.dart';
import 'package:localsend_app/pages/troubleshoot_page.dart';
import 'package:localsend_app/provider/animation_provider.dart';
import 'package:localsend_app/provider/favorites_provider.dart';
import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/network/scan_facade.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/progress_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/favorites.dart';
import 'package:localsend_app/util/file_size_helper.dart';
import 'package:localsend_app/util/ip_helper.dart';
import 'package:localsend_app/util/native/file_picker.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/widget/big_button.dart';
import 'package:localsend_app/widget/custom_icon_button.dart';
import 'package:localsend_app/widget/dialogs/add_file_dialog.dart';
import 'package:localsend_app/widget/dialogs/send_mode_help_dialog.dart';
import 'package:localsend_app/widget/file_thumbnail.dart';
import 'package:localsend_app/widget/list_tile/device_list_tile.dart';
import 'package:localsend_app/widget/list_tile/device_placeholder_list_tile.dart';
import 'package:localsend_app/widget/local_send_logo.dart';
import 'package:localsend_app/widget/opacity_slideshow.dart';
import 'package:localsend_app/widget/responsive_builder.dart';
import 'package:localsend_app/widget/responsive_list_view.dart';
import 'package:localsend_app/widget/rotating_widget.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

const _horizontalPadding = 15.0;
final _options = FilePickerOption.getOptionsForPlatform();

enum _QuickSaveMode {
  off,
  favorites,
  on,
}

class UnifiedTab extends StatelessWidget {
  const UnifiedTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder(
      provider: (ref) => sendTabVmProvider,
      init: (context) async => context.global.dispatchAsync(SendTabInitAction(context)), // ignore: discarded_futures
      builder: (context, sendVm) {
        final receiveVm = context.watch(receiveTabVmProvider);
        final ref = context.ref;
        final animations = ref.watch(animationProvider);

        return Stack(
          children: [
            ResponsiveListView(
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 10),
              children: [
                // Top Header Row: Logo, Name, ID on Left | History, Info, Settings on Right
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding, vertical: 10),
                  child: Row(
                    children: [
                      // Left: Logo + Name & ID
                      Expanded(
                        child: Row(
                          children: [
                            RotatingWidget(
                              duration: const Duration(seconds: 15),
                              spinning: receiveVm.serverState != null && animations,
                              child: const LocalSendLogo(
                                withText: false,
                                size: 36,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      receiveVm.serverState?.alias ?? receiveVm.aliasSettings,
                                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  Text(
                                    receiveVm.serverState == null
                                        ? t.general.offline
                                        : receiveVm.localIps.map((ip) => '#${ip.visualId}').toSet().join(' '),
                                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Right: Buttons
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!receiveVm.showAdvanced && receiveVm.showHistoryButton)
                            CustomIconButton(
                              onPressed: () async {
                                await context.push(() => const ReceiveHistoryPage());
                              },
                              child: const Icon(Icons.history),
                            ),
                          CustomIconButton(
                            key: const ValueKey('info-btn'),
                            onPressed: receiveVm.toggleAdvanced,
                            child: const Icon(Icons.info),
                          ),
                          CustomIconButton(
                            key: const ValueKey('settings-btn'),
                            onPressed: () async {
                              await context.push(() => const SettingsTab(showAppBar: true));
                            },
                            child: const Icon(Icons.settings),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Selection Section
                if (sendVm.selectedFiles.isEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
                    child: Text(
                      t.sendTab.selection.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 5),
                  // Grid-like Selection: 2 rows of 3 columns
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
                    child: _buildSelectionGrid(context, ref),
                  ),
                ] else ...[
                  Card(
                    margin: const EdgeInsets.only(bottom: 10, left: _horizontalPadding, right: _horizontalPadding),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 15, right: 15, top: 5, bottom: 15),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                t.sendTab.selection.title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const Spacer(),
                              CustomIconButton(
                                onPressed: () => ref.redux(selectedSendingFilesProvider).dispatch(ClearSelectionAction()),
                                child: Icon(Icons.close, color: Theme.of(context).colorScheme.secondary),
                              ),
                              const SizedBox(width: 5),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(t.sendTab.selection.files(files: sendVm.selectedFiles.length)),
                          Text(t.sendTab.selection.size(size: sendVm.selectedFiles.fold(0, (prev, curr) => prev + curr.size).asReadableFileSize)),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: defaultThumbnailSize,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: sendVm.selectedFiles.length,
                              itemBuilder: (context, index) {
                                final file = sendVm.selectedFiles[index];
                                return Padding(
                                  padding: const EdgeInsets.only(right: 10),
                                  child: SmartFileThumbnail.fromCrossFile(file),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                style: TextButton.styleFrom(
                                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                                ),
                                onPressed: () async {
                                  await context.push(() => const SelectedFilesPage());
                                },
                                child: Text(t.general.edit),
                              ),
                              const SizedBox(width: 15),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Theme.of(context).colorScheme.primary,
                                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                                ),
                                onPressed: () async {
                                  if (_options.length == 1) {
                                    await ref.global.dispatchAsync(
                                      PickFileAction(
                                        option: _options.first,
                                        context: context,
                                      ),
                                    );
                                    return;
                                  }
                                  await AddFileDialog.open(
                                    context: context,
                                    options: _options,
                                  );
                                },
                                icon: const Icon(Icons.add),
                                label: Text(t.general.add),
                              ),
                              const SizedBox(width: 15),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                // Nearby Devices Section
                Row(
                  children: [
                    const SizedBox(width: _horizontalPadding),
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(t.sendTab.nearbyDevices, style: Theme.of(context).textTheme.titleMedium),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _ScanButton(
                      ips: sendVm.localIps,
                    ),
                    Tooltip(
                      message: t.sendTab.manualSending,
                      child: CustomIconButton(
                        onPressed: () async => sendVm.onTapAddress(context),
                        child: const Icon(Icons.ads_click),
                      ),
                    ),
                    Tooltip(
                      message: t.dialogs.favoriteDialog.title,
                      child: CustomIconButton(
                        onPressed: () async => await sendVm.onTapFavorite(context),
                        child: const Icon(Icons.favorite),
                      ),
                    ),
                    _SendModeButton(
                      onSelect: (mode) async => sendVm.onTapSendMode(context, mode),
                    ),
                  ],
                ),
                if (sendVm.nearbyDevices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10, left: _horizontalPadding, right: _horizontalPadding),
                    child: Opacity(
                      opacity: 0.3,
                      child: DevicePlaceholderListTile(),
                    ),
                  ),
                ...sendVm.nearbyDevices.map((device) {
                  final favoriteEntry = sendVm.favoriteDevices.findDevice(device);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10, left: _horizontalPadding, right: _horizontalPadding),
                    child: Hero(
                      tag: 'device-${device.ip}',
                      child: sendVm.sendMode == SendMode.multiple
                          ? _MultiSendDeviceListTile(
                              device: device,
                              isFavorite: favoriteEntry != null,
                              nameOverride: favoriteEntry?.alias,
                              vm: sendVm,
                            )
                          : DeviceListTile(
                              device: device,
                              isFavorite: favoriteEntry != null,
                              nameOverride: favoriteEntry?.alias,
                              onFavoriteTap: () async => await sendVm.onToggleFavorite(context, device),
                              onTap: () async => await sendVm.onTapDevice(context, device),
                            ),
                    ),
                  );
                }),
                const SizedBox(height: 10),

                // Quick Save Section at the bottom
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 15),
                  child: Center(
                    child: Column(
                      children: [
                        Text(t.general.quickSave),
                        const SizedBox(height: 10),
                        SegmentedButton<_QuickSaveMode>(
                          multiSelectionEnabled: false,
                          emptySelectionAllowed: false,
                          showSelectedIcon: false,
                          onSelectionChanged: (selection) async {
                            if (selection.contains(_QuickSaveMode.off)) {
                              await receiveVm.onSetQuickSave(context, false);
                              if (context.mounted) {
                                await receiveVm.onSetQuickSaveFromFavorites(context, false);
                              }
                            } else if (selection.contains(_QuickSaveMode.favorites)) {
                              await receiveVm.onSetQuickSave(context, false);
                              if (context.mounted) {
                                await receiveVm.onSetQuickSaveFromFavorites(context, true);
                              }
                            } else if (selection.contains(_QuickSaveMode.on)) {
                              await receiveVm.onSetQuickSaveFromFavorites(context, false);
                              if (context.mounted) {
                                await receiveVm.onSetQuickSave(context, true);
                              }
                            }
                          },
                          selected: {
                            if (!receiveVm.quickSaveSettings && !receiveVm.quickSaveFromFavoritesSettings) _QuickSaveMode.off,
                            if (receiveVm.quickSaveFromFavoritesSettings) _QuickSaveMode.favorites,
                            if (receiveVm.quickSaveSettings) _QuickSaveMode.on,
                          },
                          segments: [
                            ButtonSegment(
                              value: _QuickSaveMode.off,
                              label: Text(t.receiveTab.quickSave.off),
                            ),
                            ButtonSegment(
                              value: _QuickSaveMode.favorites,
                              label: Text(t.receiveTab.quickSave.favorites),
                            ),
                            ButtonSegment(
                              value: _QuickSaveMode.on,
                              label: Text(t.receiveTab.quickSave.on),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                Center(
                  child: TextButton(
                    onPressed: () async {
                      await context.push(() => const TroubleshootPage());
                    },
                    child: Text(t.troubleshootPage.title),
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
                  child: OpacitySlideshow(
                    durationMillis: 6000,
                    running: animations,
                    children: [
                      Text(
                        t.sendTab.help,
                        style: const TextStyle(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                      if (checkPlatformCanReceiveShareIntent())
                        Text(
                          t.sendTab.shareIntentInfo,
                          style: const TextStyle(color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 50),
              ],
            ),
            
            // Info Box Overlay
            _InfoBox(receiveVm),

            // Top Drag Handle for macOS (Desktop only)
            if (checkPlatform([TargetPlatform.macOS]))
              SizedBox(height: 50, child: MoveWindow()),
          ],
        );
      },
    );
  }

  Widget _buildSelectionGrid(BuildContext context, Ref ref) {
    final chunks = <List<FilePickerOption>>[];
    for (var i = 0; i < _options.length; i += 3) {
      chunks.add(_options.sublist(i, i + 3 > _options.length ? _options.length : i + 3));
    }

    return Column(
      children: chunks.map((chunk) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              ...chunk.map((option) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: BigButton(
                        icon: option.icon,
                        label: option.label,
                        filled: false,
                        width: double.infinity,
                        onTap: () async => ref.global.dispatchAsync(
                          PickFileAction(
                            option: option,
                            context: context,
                          ),
                        ),
                      ),
                    ),
                  )),
              ...List.generate(3 - chunk.length, (_) => const Expanded(child: SizedBox())),
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// A button that opens a popup menu to select [T].
class _CircularPopupButton<T> extends StatelessWidget {
  final String tooltip;
  final PopupMenuItemBuilder<T> itemBuilder;
  final PopupMenuItemSelected<T>? onSelected;
  final Widget child;

  const _CircularPopupButton({
    required this.tooltip,
    required this.onSelected,
    required this.itemBuilder,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(9999),
      child: Material(
        type: MaterialType.transparency,
        child: DividerTheme(
          data: DividerThemeData(
            color: Theme.of(context).brightness == Brightness.light ? Colors.teal.shade100 : Colors.grey.shade700,
          ),
          child: PopupMenuButton(
            offset: const Offset(0, 40),
            onSelected: onSelected,
            tooltip: tooltip,
            itemBuilder: itemBuilder,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// The scan button that uses [_CircularPopupButton].
class _ScanButton extends StatelessWidget {
  final List<String> ips;

  const _ScanButton({
    required this.ips,
  });

  @override
  Widget build(BuildContext context) {
    final (scanningFavorites, scanningIps) = context.ref.watch(nearbyDevicesProvider.select((s) => (s.runningFavoriteScan, s.runningIps)));
    final animations = context.ref.watch(animationProvider);

    final spinning = (scanningFavorites || scanningIps.isNotEmpty) && animations;
    final iconColor = !animations && scanningIps.isNotEmpty ? Theme.of(context).colorScheme.warning : null;

    if (ips.length <= StartSmartScan.maxInterfaces) {
      return Tooltip(
        message: t.sendTab.scan,
        child: RotatingWidget(
          duration: const Duration(seconds: 2),
          spinning: spinning,
          reverse: true,
          child: CustomIconButton(
            onPressed: () async {
              context.redux(nearbyDevicesProvider).dispatch(ClearFoundDevicesAction());
              await context.global.dispatchAsync(StartSmartScan(forceLegacy: true));
            },
            child: Icon(Icons.sync, color: iconColor),
          ),
        ),
      );
    }

    return _CircularPopupButton(
      tooltip: t.sendTab.scan,
      onSelected: (ip) async {
        context.redux(nearbyDevicesProvider).dispatch(ClearFoundDevicesAction());
        await context.global.dispatchAsync(StartLegacySubnetScan(subnets: [ip]));
      },
      itemBuilder: (_) {
        return [
          ...ips.map(
            (ip) => PopupMenuItem(
              value: ip,
              padding: const EdgeInsets.only(left: 12, right: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _RotatingSyncIcon(ip),
                  const SizedBox(width: 10),
                  Text(ip),
                ],
              ),
            ),
          ),
        ];
      },
      child: RotatingWidget(
        duration: const Duration(seconds: 2),
        spinning: spinning,
        reverse: true,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(Icons.sync, color: iconColor),
        ),
      ),
    );
  }
}

/// A separate widget, so it gets the latest data from provider.
class _RotatingSyncIcon extends StatelessWidget {
  final String ip;

  const _RotatingSyncIcon(this.ip);

  @override
  Widget build(BuildContext context) {
    final scanningIps = context.ref.watch(nearbyDevicesProvider.select((s) => s.runningIps));
    return RotatingWidget(
      duration: const Duration(seconds: 2),
      spinning: scanningIps.contains(ip),
      reverse: true,
      child: const Icon(Icons.sync),
    );
  }
}

class _SendModeButton extends StatelessWidget {
  final void Function(SendMode mode) onSelect;

  const _SendModeButton({required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return _CircularPopupButton<int>(
      tooltip: t.sendTab.sendMode,
      onSelected: (mode) async {
        switch (mode) {
          case 0:
            onSelect(SendMode.single);
            break;
          case 1:
            onSelect(SendMode.multiple);
            break;
          case 2:
            onSelect(SendMode.link);
            break;
          case -1:
            await showDialog(context: context, builder: (_) => const SendModeHelpDialog());
            break;
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 0,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Consumer(
                builder: (context, ref) {
                  final sendMode = ref.watch(settingsProvider.select((s) => s.sendMode));
                  return Visibility(
                    visible: sendMode == SendMode.single,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: const Icon(Icons.check_circle),
                  );
                },
              ),
              const SizedBox(width: 10),
              Text(t.sendTab.sendModes.single),
            ],
          ),
        ),
        PopupMenuItem(
          value: 1,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Consumer(
                builder: (context, ref) {
                  final sendMode = ref.watch(settingsProvider.select((s) => s.sendMode));
                  return Visibility(
                    visible: sendMode == SendMode.multiple,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: const Icon(Icons.check_circle),
                  );
                },
              ),
              const SizedBox(width: 10),
              Text(t.sendTab.sendModes.multiple),
            ],
          ),
        ),
        PopupMenuItem(
          value: 2,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Visibility(
                visible: false,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: Icon(Icons.check_circle),
              ),
              const SizedBox(width: 10),
              Text(t.sendTab.sendModes.link),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: -1,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Directionality(
                textDirection: TextDirection.ltr,
                child: Icon(Icons.help),
              ),
              const SizedBox(width: 10),
              Text(t.sendTab.sendModeHelp),
            ],
          ),
        ),
      ],
      child: const Padding(
        padding: EdgeInsets.all(8),
        child: Icon(Icons.settings),
      ),
    );
  }
}

/// An advanced list tile which shows the progress of the file transfer.
class _MultiSendDeviceListTile extends StatelessWidget {
  final Device device;
  final bool isFavorite;
  final String? nameOverride;
  final SendTabVm vm;

  const _MultiSendDeviceListTile({
    required this.device,
    required this.isFavorite,
    required this.nameOverride,
    required this.vm,
  });

  @override
  Widget build(BuildContext context) {
    final ref = context.ref;
    final session = ref.watch(sendProvider).values.firstWhereOrNull((s) => s.target.ip == device.ip);
    final double? progress;
    if (session != null) {
      final files = session.files.values.where((f) => f.token != null);
      final progressNotifier = ref.watch(progressProvider);
      final currBytes = files.fold<int>(
        0,
        (prev, curr) => prev + ((progressNotifier.getProgress(sessionId: session.sessionId, fileId: curr.file.id) * curr.file.size).round()),
      );
      final totalBytes = files.fold<int>(0, (prev, curr) => prev + curr.file.size);
      progress = totalBytes == 0 ? 0 : currBytes / totalBytes;
    } else {
      progress = null;
    }
    return DeviceListTile(
      device: device,
      info: session?.status.humanString,
      progress: progress,
      isFavorite: isFavorite,
      nameOverride: nameOverride,
      onFavoriteTap: device.ip == null ? null : () async => await vm.onToggleFavorite(context, device),
      onTap: () async => await vm.onTapDeviceMultiSend(context, device),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final ReceiveTabVm vm;

  const _InfoBox(this.vm);

  @override
  Widget build(BuildContext context) {
    return AnimatedCrossFade(
      crossFadeState: vm.showAdvanced ? CrossFadeState.showSecond : CrossFadeState.showFirst,
      duration: const Duration(milliseconds: 200),
      firstChild: Container(),
      secondChild: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Table(
                columnWidths: const {
                  0: IntrinsicColumnWidth(),
                  1: IntrinsicColumnWidth(),
                  2: IntrinsicColumnWidth(),
                },
                children: [
                  TableRow(
                    children: [
                      Text(t.receiveTab.infoBox.alias),
                      const SizedBox(width: 10),
                      Padding(
                        padding: const EdgeInsets.only(right: 30),
                        child: SelectableText(vm.serverState?.alias ?? '-'),
                      ),
                    ],
                  ),
                  TableRow(
                    children: [
                      Text(t.receiveTab.infoBox.ip),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (vm.localIps.isEmpty) Text(t.general.unknown),
                          ...vm.localIps.map((ip) => SelectableText(ip)),
                        ],
                      ),
                    ],
                  ),
                  TableRow(
                    children: [
                      Text(t.receiveTab.infoBox.port),
                      const SizedBox(width: 10),
                      SelectableText(vm.serverState?.port.toString() ?? '-'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

extension on SessionStatus {
  String? get humanString {
    switch (this) {
      case SessionStatus.waiting:
        return t.sendPage.waiting;
      case SessionStatus.recipientBusy:
        return t.sendPage.busy;
      case SessionStatus.declined:
        return t.sendPage.rejected;
      case SessionStatus.tooManyAttempts:
        return t.sendPage.tooManyAttempts;
      case SessionStatus.sending:
        return null;
      case SessionStatus.finished:
        return t.general.finished;
      case SessionStatus.finishedWithErrors:
        return t.progressPage.total.title.finishedError;
      case SessionStatus.canceledBySender:
        return t.progressPage.total.title.canceledSender;
      case SessionStatus.canceledByReceiver:
        return t.progressPage.total.title.canceledReceiver;
    }
  }
}
