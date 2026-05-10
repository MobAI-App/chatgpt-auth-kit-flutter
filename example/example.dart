// Minimal usage of chatgpt_auth_kit. See the README for setup details
// (iOS Info.plist additions, in-app browser presentation, etc.).

import 'dart:io';

import 'package:chatgpt_auth_kit/chatgpt_auth_kit.dart';

Future<void> main() async {
  // 1. Sign the user in (launches the system browser by default; pass a
  //    `present` callback to drive an in-app SFSafariViewController).
  final store = CredentialsStore();
  Credentials? creds = await store.load();
  creds ??= await OAuthFlow().run();
  await store.save(creds);

  // 2. Wrap the credentials in a refreshing provider so near-expiry tokens
  //    get rotated automatically.
  final provider = RefreshingCredentialsProvider(creds, store: store);

  // 3. Stream a Codex Responses-API completion.
  final client = ResponsesClient(provider: provider);
  await for (final event in client.stream([
    const Message(role: Role.system, content: 'You are helpful.'),
    const Message(role: Role.user, content: 'Plan a weekend in Berlin.'),
  ])) {
    if (event is DeltaEvent) stdout.write(event.text);
  }
  stdout.writeln();
}
