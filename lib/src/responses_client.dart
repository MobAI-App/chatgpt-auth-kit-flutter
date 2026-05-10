import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'credentials.dart';
import 'credentials_provider.dart';

enum Role { system, user, assistant }

class Message {
  final Role role;
  final String content;
  const Message({required this.role, required this.content});
}

class Usage {
  final int inputTokens;
  final int outputTokens;
  final int totalTokens;
  const Usage({required this.inputTokens, required this.outputTokens, required this.totalTokens});
}

sealed class ResponseEvent {
  const ResponseEvent();
}

class DeltaEvent extends ResponseEvent {
  final String text;
  const DeltaEvent(this.text);
}

class CompletedEvent extends ResponseEvent {
  final Usage? usage;
  const CompletedEvent(this.usage);
}

class ResponsesClientException implements Exception {
  final String message;
  const ResponsesClientException(this.message);
  @override
  String toString() => message;
}

class ResponsesConfig {
  final Uri endpoint;
  final String model;
  final String instructionsFallback;
  final String reasoningEffort;
  final String originator;

  ResponsesConfig({
    Uri? endpoint,
    this.model = 'gpt-5.5',
    this.instructionsFallback = "Follow the user's instructions.",
    this.reasoningEffort = 'medium',
    this.originator = 'codex_cli_rs',
  }) : endpoint = endpoint ?? Uri.parse('https://chatgpt.com/backend-api/codex/responses');
}

/// Streaming client for the Codex Responses API.
class ResponsesClient {
  final CredentialsProvider provider;
  final ResponsesConfig config;

  ResponsesClient({required this.provider, ResponsesConfig? config})
      : config = config ?? ResponsesConfig();

  /// Convenience: wraps a single [Credentials] value. For long-lived callers,
  /// prefer the provider-based constructor with a [RefreshingCredentialsProvider]
  /// so tokens auto-refresh.
  ResponsesClient.fromCredentials(Credentials credentials, {ResponsesConfig? config})
      : this(provider: StaticCredentialsProvider(credentials), config: config);

  /// Streams [ResponseEvent]s as the model generates text.
  Stream<ResponseEvent> stream(List<Message> messages) async* {
    final credentials = await provider.currentCredentials();
    final body = _buildBody(messages);
    final request = http.Request('POST', config.endpoint);
    request.headers.addAll({
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${credentials.accessToken}',
      'OpenAI-Beta': 'responses=experimental',
      'originator': config.originator,
      'Accept': 'text/event-stream',
      if (credentials.accountID.isNotEmpty) 'ChatGPT-Account-ID': credentials.accountID,
    });
    request.body = jsonEncode(body);

    final response = await http.Client().send(request);
    if (response.statusCode == 401) {
      throw const ResponsesClientException('ChatGPT authentication failed - sign in again.');
    }
    if (response.statusCode == 429) {
      final retry = response.headers['x-codex-primary-reset-after-seconds'];
      throw ResponsesClientException('Rate limit hit${retry == null ? '' : '. Retry in ${retry}s'}.');
    }
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw ResponsesClientException('ChatGPT API error ${response.statusCode}: $body');
    }

    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in lines) {
      if (!line.startsWith('data: ')) continue;
      final data = line.substring(6);
      if (data == '[DONE]') break;
      Map<String, dynamic> json;
      try {
        json = jsonDecode(data) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      final type = json['type'] as String?;
      switch (type) {
        case 'response.output_text.delta':
          final delta = json['delta'] as String?;
          if (delta != null && delta.isNotEmpty) yield DeltaEvent(delta);
          break;
        case 'response.completed':
          final usage = (json['response'] as Map<String, dynamic>?)?['usage'] as Map<String, dynamic>?;
          yield CompletedEvent(usage == null
              ? null
              : Usage(
                  inputTokens: usage['input_tokens'] as int? ?? 0,
                  outputTokens: usage['output_tokens'] as int? ?? 0,
                  totalTokens: usage['total_tokens'] as int? ?? 0,
                ));
          break;
      }
    }
  }

  /// Convenience: collect the full text + final usage in one call.
  Future<({String text, Usage? usage})> complete(List<Message> messages) async {
    final buf = StringBuffer();
    Usage? usage;
    await for (final ev in stream(messages)) {
      if (ev is DeltaEvent) buf.write(ev.text);
      if (ev is CompletedEvent) usage = ev.usage;
    }
    return (text: buf.toString(), usage: usage);
  }

  Map<String, dynamic> _buildBody(List<Message> messages) {
    final pair = _buildInput(messages);
    return {
      'model': config.model,
      'store': false,
      'stream': true,
      'input': pair.input,
      'instructions': pair.instructions.isEmpty ? config.instructionsFallback : pair.instructions,
      'reasoning': {'effort': config.reasoningEffort, 'summary': 'auto'},
      'include': ['reasoning.encrypted_content'],
    };
  }

  static ({String instructions, List<Map<String, dynamic>> input}) _buildInput(List<Message> messages) {
    final instructions = StringBuffer();
    final input = <Map<String, dynamic>>[];
    for (final m in messages) {
      switch (m.role) {
        case Role.system:
          if (instructions.isNotEmpty) instructions.write('\n\n');
          instructions.write(m.content);
        case Role.user:
          input.add({
            'type': 'message',
            'role': 'user',
            'content': [
              {'type': 'input_text', 'text': m.content}
            ],
          });
        case Role.assistant:
          input.add({
            'type': 'message',
            'role': 'assistant',
            'content': [
              {'type': 'output_text', 'text': m.content}
            ],
          });
      }
    }
    return (instructions: instructions.toString(), input: input);
  }
}
