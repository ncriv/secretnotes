import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/sync_provider.dart';
import '../screens/sync_settings_screen.dart';

/// Adaptive cloud icon that doubles as a live/offline sync indicator:
///
///   cloud_done  → live (configured, up to date)
///   cloud_sync  → syncing
///   cloud_off   → offline (sync error)
///   cloud_off   → off (sync not configured)
///
/// Tapping syncs now when configured, or opens sync setup when not.
class SyncCloudIndicator extends StatelessWidget {
  const SyncCloudIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SyncProvider>(
      builder: (context, sync, _) {
        final IconData icon;
        final Color? color;
        final String tooltip;
        final VoidCallback? onTap;

        if (!sync.configured) {
          icon = Icons.cloud_off_outlined;
          color = null; // muted/default — sync is simply off
          tooltip = 'Sync off · tap to set up';
          onTap = () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SyncSettingsScreen()),
              );
        } else {
          switch (sync.status) {
            case SyncStatus.syncing:
              icon = Icons.cloud_sync;
              color = Colors.lightBlueAccent;
              tooltip = 'Syncing…';
              onTap = null;
            case SyncStatus.error:
              icon = Icons.cloud_off;
              color = Colors.redAccent;
              tooltip = 'Offline · tap to retry';
              onTap = () => sync.sync();
            case SyncStatus.idle:
              icon = Icons.cloud_done_outlined;
              color = Colors.teal;
              tooltip = 'Live · tap to sync now';
              onTap = () => sync.sync();
          }
        }

        return IconButton(
          icon: Icon(icon, color: color),
          tooltip: tooltip,
          onPressed: onTap,
        );
      },
    );
  }
}
