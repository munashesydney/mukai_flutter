# Mukai for iOS · V2

A native Flutter client for the same owner API used by Mukai's React client.
The server owns workspaces, bots, chats, pursuits, spaces, and shared settings.
There is no separate mobile API and no VM viewer in this release.

## Run

Requires Flutter 3.41+ / Dart 3.11+, Xcode, and iOS 15+. If the generated iOS
host is missing, run `scripts/bootstrap.sh` first.

```bash
flutter pub get
scripts/ios.sh run
```

`ios.sh` and the generated Xcode build phases keep the selected Xcode visible to native plugin build hooks without
changing global command-line-tools settings. Set `DEVELOPER_DIR` to use another
Xcode installation. The dependency lockfile is retained for reproducible builds.

Enter your **Server URL**, such as `https://mukai.example` (no `/api` needed), tap **Connect**, then sign in with your
**Mukai username and password**. Both `https://mukai.example` and
`https://mukai.example/api` work. Set up the owner account in the web app first;
the backend must include this release's device-session authentication support.
Use HTTPS for remote connections. On an iPhone, `127.0.0.1` refers to the phone;
the Simulator can reach the Mac's loopback server.

The password is exchanged for a seven-day device session and never stored.
The session stays in iOS Keychain and restores on relaunch. Disconnect revokes
that device session when the server is reachable and removes local credentials.
Offline sessions expire on the server. Appearance is local to the phone.
Existing owner API tokens remain available for integrations through web Settings
→ API; the mobile app does not need one.

### Cloudflare Zero Trust

The login screen's **Using Cloudflare Zero Trust?** sheet links to the dashboard
and [official Managed OAuth guide](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/managed-oauth/).
On the Access application, enable **Managed OAuth** and **Dynamic Client
Registration**, and allow exactly this native redirect URI:

```text
com.mukai.mobile:/oauth/callback
```

Connect detects Access challenges and opens the system browser for authorization
code + PKCE sign-in. Cloudflare access/refresh tokens stay in Keychain, refresh
silently when possible, and accompany requests in `Authorization: Bearer …`.
The Mukai device session uses `X-Mukai-Session`, so both layers work together.
The ordinary cookie-only Access login needs Managed OAuth enabled first.
Background requests never open a browser; expired authorization returns to login.

The generated iOS URL scheme is configured by `scripts/bootstrap.sh`. Cloudflare
requires no API key, administrator token, or pasted service credentials on the
phone. OAuth discovery/registration is tested with isolated HTTP fixtures; a
live Cloudflare application is needed to verify its policy and browser callback.

## Connected surfaces

- Workspace switching, real bots, recent private and bot conversations.
- Conversation creation, saved history, real SSE responses, stop and retry,
  queued follow-ups, approval decisions (including denial reasons) and clarification answers.
  Work transcripts stay collapsed until opened, with server compaction and memory-recovery status.
- Files up to the backend's 10 MB / four-file limit in private/bot chats;
  authenticated image previews with pinch-to-zoom, workspace file references with
  line highlights, native Quick Look for supported documents/media, and original-file sharing.
- Markdown responses, code, tables, tool activity, delegation, saved messages,
  and a server-backed activity panel. Local workspace server links stay on the
  desktop; the phone does not launch a VM or desktop viewer.
- Updates inbox with a conditional sidebar item and unread count, read/dismiss, and continue-in-chat.
- Pursuit list/detail, Workpad pagination, run history, pause/resume, run/stop,
  retry and delete. Pursuit creation remains an AI action.
- Spaces created with the existing React contract; messages can select a space
  member bot or be posted without requesting a bot response. Space attachments
  are omitted because the current server contract does not support them.
- Tool assignments and synced approval mode, profile and API-key provider
  settings. Existing desktop-connected providers remain available for chat;
  provider OAuth sign-in remains a desktop/browser flow.

Foreground refresh reconciles changes made elsewhere and recovers saved chat
state after app resume. Switching conversations cancels the local stream without
stopping server work. Drafts are scoped to conversations, and uncertain sends
retain their request ID so retrying does not create a second request.

Appearance opens below the top safe area, supports drag-to-dismiss, and has an
explicit close button. Its default-on **Minimalism** switch shows a compact bot
list: tap a bot to reveal its three latest chats, then load three more at a time.
The sidebar destination is **Bots** in this mode. Switch Minimalism off to restore
the original **Workspace** landing page. The choice is saved locally.

## Verify

```bash
flutter analyze
flutter test
python3 scripts/test_live_backend.py -d <booted-iphone-simulator-id>
```

The native test starts an isolated real Mukai backend with a deterministic local
OpenAI-compatible provider, three bots, a pursuit, a Workpad and a space. It checks
Keychain persistence and restore, username/password login, help/appearance sheet dismissal, streaming chat, approval decisions, collapsed work history,
authenticated image/file previews, Updates, pursuit pause and space messaging. It cleans up its server and temporary data afterward. Install
`../mukai`'s Node dependencies first; no external AI provider or user workspace is
used. Do not run `integration_test/live_backend_test.dart` against real user data.

The default unit/widget suite includes HTTP/SSE integration fixtures for routing,
fragmented streams, auth rejection, uploads/mutations, cancellation, ambiguous
sends, draft preservation, and stale workspace responses. Demo injection remains
available to widget tests; the production entry point always uses a real connection.
