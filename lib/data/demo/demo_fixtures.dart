/// Fixture data for the UI-only build.
///
/// Content mirrors the workspace shown in Mukai's own screenshots, so the clone
/// is recognisably the same product rather than a generic chat shell.
library;

import '../../domain/models.dart';

abstract final class DemoFixtures {
  static const MukaiWorkspace workspace = MukaiWorkspace(
    name: 'Test workspace',
    tagline: 'A little momentum, every day.',
    kind: 'Folder workspace',
  );

  static const List<MukaiBot> bots = <MukaiBot>[
    MukaiBot(
      id: 'scout',
      name: 'Scout',
      role: 'Main Bot/Orchestrator',
      mascot: 'muka-mascot-2-blue',
      identity: BotIdentity.scout,
      isMain: true,
    ),
    MukaiBot(
      id: 'atlas',
      name: 'Atlas',
      role: 'Project builder',
      mascot: 'muka-mascot-1-green',
      identity: BotIdentity.atlas,
    ),
    MukaiBot(
      id: 'nova',
      name: 'Nova',
      role: 'Research and writing',
      mascot: 'muka-mascot-3-purple',
      identity: BotIdentity.nova,
    ),
  ];

  static List<Conversation> conversationsFor(String botId) => <Conversation>[
    Conversation(
      id: '$botId-today',
      title: 'New conversation',
      botId: botId,
      updatedAt: DateTime.now().subtract(const Duration(minutes: 2)),
      preview: 'Q1 revenue, charted',
    ),
    Conversation(
      id: '$botId-notes',
      title: 'Project notes cleanup',
      botId: botId,
      updatedAt: DateTime.now().subtract(const Duration(hours: 5)),
      preview: 'Trimmed it down to three files and dropped the legacy copies.',
    ),
    Conversation(
      id: '$botId-week',
      title: 'Weekly momentum review',
      botId: botId,
      updatedAt: DateTime.now().subtract(const Duration(days: 2)),
      preview: 'Two pursuits closed, one still waiting on you.',
    ),
  ];

  static const ChatActivity revenueActivity = ChatActivity(
    bots: <String>['scout', 'nova'],
    links: <ActivityLink>[
      ActivityLink(title: 'localhost:62266', state: 'Running'),
    ],
    outputs: <ActivityOutput>[
      ActivityOutput(name: 'project-notes.md', kind: 'Workspace file'),
      ActivityOutput(
        name: '18baf1d6-c646-4d7c-a655-bb21f0c9e3f1.webp',
        kind: 'Workspace image',
      ),
      ActivityOutput(name: 'copied-image.png', kind: 'Workspace image'),
      ActivityOutput(name: 'legacy-copy.png', kind: 'Workspace image'),
    ],
    changes: <ActivityChange>[
      ActivityChange(
        file: 'Project.tsx',
        path: 'src/Project.tsx',
        added: 2,
        removed: 1,
      ),
    ],
  );

  static const ChatActivity idleActivity = ChatActivity(
    bots: <String>['scout'],
    outputs: <ActivityOutput>[
      ActivityOutput(name: 'workpad.md', kind: 'Workspace file'),
    ],
  );

  static List<ChatMessage> threadFor(String botId) {
    final DateTime now = DateTime.now();
    if (botId != 'scout') {
      return <ChatMessage>[
        ChatMessage(
          id: '$botId-1',
          fromUser: false,
          botId: botId,
          at: now.subtract(const Duration(minutes: 9)),
          blocks: const <ChatBlock>[
            TextBlock('Woken and ready. Nothing is waiting on you right now.'),
            BulletBlock(<String>[
              'Workpad is clear — no blockers.',
              'Last run finished about five hours ago.',
            ]),
          ],
        ),
      ];
    }

    return <ChatMessage>[
      ChatMessage(
        id: 'scout-1',
        fromUser: true,
        at: now.subtract(const Duration(minutes: 12)),
        blocks: const <ChatBlock>[
          TextBlock(
            'Chart Q1 revenue from the workspace CSV and tell me what changed.',
          ),
        ],
      ),
      ChatMessage(
        id: 'scout-2',
        fromUser: false,
        botId: 'scout',
        at: now.subtract(const Duration(minutes: 11)),
        blocks: const <ChatBlock>[
          ToolBlock(
            label: 'read_file',
            detail: 'data/q1-revenue.csv · 3 rows',
            state: ToolState.done,
          ),
          TextBlock(
            'Q1 came in uneven. January opened at \$9k, February dipped to -\$2k, '
            'and March recovered hard at \$14k — the strongest month in the file.',
          ),
          HeadingBlock('What moved'),
          BulletBlock(<String>[
            'February carried one refund cycle that outweighed new bookings.',
            'March added two enterprise signups, which covers the gap on its own.',
            'Net across the quarter is still positive at \$21k.',
          ]),
          ChartBlock(
            title: 'Example revenue',
            seriesLabel: 'Revenue',
            points: <({String label, double value})>[
              (label: 'Jan', value: 9),
              (label: 'Feb', value: -2),
              (label: 'Mar', value: 14),
            ],
          ),
          TableBlock(
            columns: <String>['month', 'Revenue'],
            rows: <List<String>>[
              <String>['Jan', '9'],
              <String>['Feb', '-2'],
            ],
            summary: 'Feb · Revenue: -2',
          ),
          LinkBlock(
            title: 'localhost:62266',
            url: 'http://localhost:62266',
            state: 'Running',
          ),
          SubBotBlock(
            botId: 'atlas',
            status: 'Returned',
            result: 'Chart component wired into src/Project.tsx',
          ),
          TextBlock(
            'I left the chart in the workspace and noted the February refund cycle on '
            'the Workpad, so the next wake picks it up with the rest of the context.',
          ),
        ],
      ),
    ];
  }

  /// Scripted assistant turns, alternating so repeat sends look different.
  static List<ChatBlock> replyScript(String input, {required int turn}) {
    if (turn.isOdd) {
      return <ChatBlock>[
        ToolBlock(
          label: 'search_workspace',
          detail: input.length > 34 ? '${input.substring(0, 34)}…' : input,
          state: ToolState.done,
        ),
        const TextBlock(
          'Looked across the workspace. Here is what I can stand behind from what is '
          'in there, with the parts I could not verify kept separate.',
        ),
        const BulletBlock(<String>[
          'Three files match, all touched in the last two days.',
          'Nothing is currently blocked on a human.',
        ]),
        const ApprovalBlock(
          toolName: 'write_file',
          reason: 'I want to save a summary to notes/reply.md.',
          fullAccessAvailable: true,
        ),
      ];
    }
    return const <ChatBlock>[
      TextBlock(
        'Noted. I will keep that on the Workpad and pick it up on the next wake.',
      ),
      SubBotBlock(botId: 'nova', status: 'Working'),
    ];
  }
}
