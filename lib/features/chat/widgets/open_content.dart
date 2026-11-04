import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/scope.dart';
import '../../../core/response_reference.dart';
import '../../../data/api/api_client.dart';
import 'file_preview.dart';
import 'preview_source.dart';

class ChatContentScope extends InheritedWidget {
  const ChatContentScope({
    super.key,
    required this.conversationId,
    required this.messageId,
    required super.child,
  });
  final String conversationId, messageId;
  static ChatContentScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChatContentScope>();
  @override
  bool updateShouldNotify(ChatContentScope old) =>
      old.conversationId != conversationId || old.messageId != messageId;
}

PreviewSource previewSource(
  BuildContext context,
  String href, {
  String name = 'File',
  bool image = false,
}) {
  final scope = ChatContentScope.maybeOf(context);
  final session = MukaiScope.sessionOf(context);
  final target = parseResponseReference(href);
  final fallback = target?.type == 'file'
      ? target!.value.split(RegExp(r'[\\/]+')).last
      : 'File';
  return PreviewSource(
    href: href,
    name: name == 'File' ? fallback : name,
    image: image,
    conversationId:
        scope?.conversationId ??
        session.conversationId ??
        'bot-${session.bot.id}',
    messageId: scope?.messageId,
  );
}

Future<void> openChatContent(
  BuildContext context,
  String href, {
  String name = 'File',
  bool image = false,
  DownloadedContent? initialContent,
}) async {
  try {
    final uri = Uri.tryParse(href);
    if (uri == null) throw Exception('This link is not valid.');
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      if (['localhost', '127.0.0.1', '0.0.0.0', '::1'].contains(uri.host)) {
        throw Exception(
          'This link runs on your workspace computer. Open it in the desktop app.',
        );
      }
      if (uri.userInfo.isNotEmpty) {
        throw Exception('Links containing credentials cannot be opened.');
      }
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception('This link could not be opened.');
      }
      return;
    }
    if (parseResponseReference(href) == null &&
        !href.startsWith('mukai-activity:')) {
      throw Exception('This link cannot be opened.');
    }
    final source = previewSource(context, href, name: name, image: image);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) =>
            FilePreviewPage(source: source, initialContent: initialContent),
      ),
    );
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}
