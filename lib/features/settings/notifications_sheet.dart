import 'package:flutter/material.dart';
import '../../core/push_notifications.dart';
import '../../design/widgets.dart';

class NotificationsSheet extends StatelessWidget {
  const NotificationsSheet({super.key, required this.push});
  final MobilePushController push;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: push,
    builder: (context, _) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetGrabber(label: 'Notifications'),
            SwitchListTile.adaptive(
              title: const Text('Push notifications'),
              subtitle: const Text(
                'Replies, approval requests, pursuit results, and bot updates.',
              ),
              value: push.enabled,
              onChanged: (value) => push.setEnabled(value),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(push.status),
            ),
            if (push.enabled && !push.ready)
              TextButton(
                onPressed: () => push.setEnabled(true),
                child: const Text('Retry connection'),
              ),
            TextButton(
              onPressed: push.native.openSettings,
              child: const Text('iPhone notification settings'),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: MukaiButton(
                label: 'Send test notification',
                onPressed: push.ready
                    ? () async {
                        try {
                          await push.test();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Test notification queued.'),
                              ),
                            );
                          }
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Could not send the test. Try reconnecting notifications.',
                                ),
                              ),
                            );
                          }
                        }
                      }
                    : null,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
