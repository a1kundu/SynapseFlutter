import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/chat_models.dart';
import '../models/llm_models.dart';
import '../settings/settings_repository.dart';

class LlmApiClient {
  final _client = http.Client();
  http.Client? _streamClient;

  /// Abort an ongoing stream request by closing its dedicated HTTP client.
  void abortStream() {
    _streamClient?.close();
    _streamClient = null;
  }

  /// Fetch available models from the provider's endpoint.
  Future<List<LlmModel>> fetchModels() async {
    final settings = SettingsRepository.instance;
    final baseUrl = settings.resolvedBaseUrl;
    final apiKey = settings.llmApiKey;
    final provider = settings.llmProvider;
    final isGitHub = provider == LlmProvider.githubModels;

    if (apiKey.isEmpty) throw Exception('API key not configured');

    final modelsUrl = isGitHub ? '$baseUrl/catalog/models' : '$baseUrl/models';

    final headers = isGitHub
        ? <String, String>{'Authorization': 'Bearer $apiKey'}
        : _buildHeaders(apiKey, provider);

    http.Response response;
    try {
      response = await _client
          .get(Uri.parse(modelsUrl), headers: headers)
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      // On Flutter web, the catalog endpoint is blocked by CORS.
      // Fall back to a curated list of known GitHub Models.
      if (isGitHub) return _fallbackGitHubModels();
      rethrow;
    }

    if (response.statusCode != 200) {
      final errorMsg = _parseError(response.body, response.statusCode);
      throw Exception(errorMsg);
    }

    final body = response.body;

    if (isGitHub) {
      // GitHub catalog can return a plain JSON array or an object with a list inside
      final decoded = jsonDecode(body);
      List<Map<String, dynamic>> catalogModels;
      if (decoded is List) {
        catalogModels = decoded.cast<Map<String, dynamic>>();
      } else if (decoded is Map<String, dynamic>) {
        // Handle wrapped response: {"value": [...]} or {"models": [...]} or {"data": [...]}
        final list =
            (decoded['value'] ?? decoded['models'] ?? decoded['data']) as List?;
        if (list == null || list.isEmpty) {
          throw Exception(
            'Unexpected GitHub Models response format: ${body.substring(0, (body.length).clamp(0, 200))}',
          );
        }
        catalogModels = list.cast<Map<String, dynamic>>();
      } else {
        throw Exception('Unexpected GitHub Models response type');
      }
      return catalogModels
          .where((m) {
            final outputs =
                (m['supported_output_modalities'] as List?)?.cast<String>() ??
                [];
            return outputs.contains('text');
          })
          .map((m) {
            final caps = (m['capabilities'] as List?)?.cast<String>() ?? [];
            return LlmModel(
              id: m['id'] as String,
              displayName: (m['name'] as String?)?.isNotEmpty == true
                  ? m['name'] as String
                  : _formatModelName(m['id'] as String),
              provider: (m['publisher'] as String?)?.isNotEmpty == true
                  ? m['publisher'] as String
                  : 'GitHub',
              supportsTools: caps.contains('tool-calling'),
            );
          })
          .toList()
        ..sort(
          (a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ),
        );
    } else {
      final modelsResponse = jsonDecode(body) as Map<String, dynamic>;
      final data =
          (modelsResponse['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      return data
          .where((info) {
            final id = (info['id'] as String).toLowerCase();
            return !id.contains('embedding') &&
                !id.contains('tts') &&
                !id.contains('whisper') &&
                !id.contains('dall-e') &&
                !id.contains('davinci') &&
                !id.contains('babbage') &&
                !id.contains('moderation');
          })
          .map(
            (info) => LlmModel(
              id: info['id'] as String,
              displayName: _formatModelName(info['id'] as String),
              provider: _formatProvider(info['owned_by'] as String? ?? ''),
            ),
          )
          .toList()
        ..sort(
          (a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ),
        );
    }
  }

  /// Stream chat completion with tool support. Returns StreamEvents via Stream.
  Stream<StreamEvent> streamWithTools({
    required LlmModel model,
    required List<ChatRequestMessage> conversationHistory,
    List<OpenAiTool>? tools,
  }) async* {
    final settings = SettingsRepository.instance;
    final baseUrl = settings.resolvedBaseUrl;
    final apiKey = settings.llmApiKey;
    final provider = settings.llmProvider;

    if (apiKey.isEmpty) {
      yield ErrorEvent('API key not configured');
      return;
    }

    final url = _chatCompletionsUrl(baseUrl, provider);
    final headers = _buildHeaders(apiKey, provider);
    headers['Content-Type'] = 'application/json';

    final requestBody = <String, dynamic>{
      'model': model.id,
      'messages': conversationHistory.map((m) => m.toJson()).toList(),
      'stream': true,
      'temperature': 0.7,
    };
    if (tools != null && tools.isNotEmpty) {
      requestBody['tools'] = tools.map((t) => t.toJson()).toList();
    }

    final toolCallMap = <int, _MutableToolCall>{};
    var doneEmitted = false;

    try {
      final request = http.Request('POST', Uri.parse(url));
      request.headers.addAll(headers);
      request.body = jsonEncode(requestBody);

      _streamClient = http.Client();
      final streamedResponse = await _streamClient!.send(request);

      if (streamedResponse.statusCode != 200) {
        final body = await streamedResponse.stream.bytesToString();
        final errorMsg = _parseError(body, streamedResponse.statusCode);
        yield ErrorEvent(errorMsg);
        doneEmitted = true;
        return;
      }

      final lineStream = streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in lineStream) {
        if (doneEmitted) continue;
        if (!line.startsWith('data:')) continue;
        final data = line.substring(5).trim();
        if (data == '[DONE]' || data.isEmpty) continue;

        try {
          final chunk = jsonDecode(data) as Map<String, dynamic>;
          final choices =
              (chunk['choices'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          if (choices.isEmpty) continue;
          final choice = choices.first;

          // Delta (streaming)
          final delta = choice['delta'] as Map<String, dynamic>?;
          if (delta != null) {
            final content = delta['content'] as String?;
            if (content != null && content.isNotEmpty) {
              yield TokenEvent(content);
            }

            // Accumulate tool call deltas
            final tcDeltas = (delta['tool_calls'] as List?)
                ?.cast<Map<String, dynamic>>();
            if (tcDeltas != null) {
              for (final tcd in tcDeltas) {
                final index = tcd['index'] as int? ?? 0;
                final tc = toolCallMap.putIfAbsent(
                  index,
                  () => _MutableToolCall(),
                );
                if (tcd['id'] != null) tc.id = tcd['id'] as String;
                if (tcd['type'] != null) tc.type = tcd['type'] as String;
                final fn = tcd['function'] as Map<String, dynamic>?;
                if (fn != null) {
                  if (fn['name'] != null) tc.name += fn['name'] as String;
                  if (fn['arguments'] != null)
                    tc.arguments += fn['arguments'] as String;
                }
              }
            }
          }

          // Non-streaming response (message instead of delta)
          final message = choice['message'] as Map<String, dynamic>?;
          if (message != null) {
            final c = message['content'] as String?;
            if (c != null && c.isNotEmpty) yield TokenEvent(c);
            final tcs = (message['tool_calls'] as List?)
                ?.cast<Map<String, dynamic>>();
            if (tcs != null && tcs.isNotEmpty) {
              yield DoneEvent(
                tcs.map((t) => ToolCallInfo.fromJson(t)).toList(),
              );
              doneEmitted = true;
            }
          }
        } catch (_) {
          // Skip malformed chunks
        }
      }

      if (!doneEmitted) {
        final finalToolCalls = toolCallMap.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        yield DoneEvent(
          finalToolCalls
              .map(
                (e) => ToolCallInfo(
                  id: e.value.id,
                  type: e.value.type,
                  function: ToolCallFunctionInfo(
                    name: e.value.name,
                    arguments: e.value.arguments,
                  ),
                ),
              )
              .toList(),
        );
      }
    } catch (e) {
      // When the client is closed mid-stream (cancelled), the error is expected.
      if (!e.toString().contains('Client is closed')) {
        yield ErrorEvent('Connection error: ${e.toString()}');
      }
    } finally {
      _streamClient = null;
    }
  }

  /// Build headers for inference/chat endpoints (NOT catalog).
  Map<String, String> _buildHeaders(String apiKey, LlmProvider provider) {
    final headers = <String, String>{'Authorization': 'Bearer $apiKey'};
    switch (provider) {
      case LlmProvider.openRouter:
        headers['HTTP-Referer'] = 'https://synapse.arijitk.in';
        headers['X-Title'] = 'Synapse';
        break;
      case LlmProvider.githubModels:
        headers['Accept'] = 'application/vnd.github+json';
        headers['X-GitHub-Api-Version'] = '2026-03-10';
        break;
      case LlmProvider.nvidia:
        headers['Accept'] = 'application/json';
        break;
      case LlmProvider.huggingFace:
        headers['Accept'] = 'application/json';
        break;
      case LlmProvider.openai:
        break;
    }
    return headers;
  }

  String _chatCompletionsUrl(String baseUrl, LlmProvider provider) {
    return provider == LlmProvider.githubModels
        ? '$baseUrl/inference/chat/completions'
        : '$baseUrl/chat/completions';
  }

  String _parseError(String body, int statusCode) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final error = json['error'] as Map<String, dynamic>?;
      return error?['message'] as String? ?? 'HTTP $statusCode';
    } catch (_) {
      return 'HTTP $statusCode';
    }
  }

  String _formatModelName(String id) {
    return id
        .split('/')
        .last
        .split(RegExp(r'[-_]'))
        .map((part) {
          if (RegExp(r'^[\d.]+$').hasMatch(part)) return part;
          if (part.length <= 3 && RegExp(r'^[a-zA-Z0-9]+$').hasMatch(part)) {
            return part.toUpperCase();
          }
          return part[0].toUpperCase() + part.substring(1);
        })
        .join(' ');
  }

  String _formatProvider(String ownedBy) {
    if (ownedBy.isEmpty) return 'Unknown';
    final lower = ownedBy.toLowerCase();
    if (lower.contains('openai')) return 'OpenAI';
    if (lower.contains('anthropic')) return 'Anthropic';
    if (lower.contains('google')) return 'Google';
    if (lower.contains('meta')) return 'Meta';
    if (lower.contains('mistral')) return 'Mistral';
    if (lower.contains('github')) return 'GitHub';
    if (lower.contains('nvidia')) return 'NVIDIA';
    if (lower.contains('hugging') || lower.contains('hf')) {
      return 'Hugging Face';
    }
    if (lower.contains('deepseek')) return 'DeepSeek';
    if (lower.contains('qwen')) return 'Qwen';
    if (lower.contains('microsoft')) return 'Microsoft';
    return ownedBy[0].toUpperCase() + ownedBy.substring(1);
  }

  /// Curated fallback list used when the catalog endpoint is unreachable
  /// (e.g. CORS on Flutter web).
  static List<LlmModel> _fallbackGitHubModels() {
    const models = <LlmModel>[
      LlmModel(
        id: 'openai/gpt-4.1',
        displayName: 'GPT-4.1',
        provider: 'OpenAI',
      ),
      LlmModel(
        id: 'openai/gpt-4.1-mini',
        displayName: 'GPT-4.1 Mini',
        provider: 'OpenAI',
      ),
      LlmModel(
        id: 'openai/gpt-4.1-nano',
        displayName: 'GPT-4.1 Nano',
        provider: 'OpenAI',
      ),
      LlmModel(id: 'openai/gpt-4o', displayName: 'GPT-4o', provider: 'OpenAI'),
      LlmModel(
        id: 'openai/gpt-4o-mini',
        displayName: 'GPT-4o Mini',
        provider: 'OpenAI',
      ),
      LlmModel(
        id: 'openai/o4-mini',
        displayName: 'o4-mini',
        provider: 'OpenAI',
      ),
      LlmModel(id: 'openai/o3', displayName: 'o3', provider: 'OpenAI'),
      LlmModel(
        id: 'openai/o3-mini',
        displayName: 'o3-mini',
        provider: 'OpenAI',
      ),
      LlmModel(id: 'openai/o1', displayName: 'o1', provider: 'OpenAI'),
      LlmModel(
        id: 'openai/o1-mini',
        displayName: 'o1-mini',
        provider: 'OpenAI',
      ),
      LlmModel(
        id: 'meta/llama-4-maverick',
        displayName: 'Llama 4 Maverick',
        provider: 'Meta',
      ),
      LlmModel(
        id: 'meta/llama-4-scout',
        displayName: 'Llama 4 Scout',
        provider: 'Meta',
      ),
      LlmModel(
        id: 'meta/llama-3.3-70b-instruct',
        displayName: 'Llama 3.3 70B',
        provider: 'Meta',
      ),
      LlmModel(
        id: 'mistral-ai/mistral-large-2411',
        displayName: 'Mistral Large',
        provider: 'Mistral',
      ),
      LlmModel(
        id: 'mistral-ai/mistral-small',
        displayName: 'Mistral Small',
        provider: 'Mistral',
      ),
      LlmModel(
        id: 'deepseek/DeepSeek-R1',
        displayName: 'DeepSeek R1',
        provider: 'DeepSeek',
      ),
      LlmModel(
        id: 'deepseek/DeepSeek-V3-0324',
        displayName: 'DeepSeek V3',
        provider: 'DeepSeek',
      ),
      LlmModel(
        id: 'cohere/cohere-command-a',
        displayName: 'Command A',
        provider: 'Cohere',
      ),
      LlmModel(id: 'xai/grok-3', displayName: 'Grok 3', provider: 'xAI'),
      LlmModel(
        id: 'xai/grok-3-mini',
        displayName: 'Grok 3 Mini',
        provider: 'xAI',
      ),
      LlmModel(
        id: 'microsoft/phi-4',
        displayName: 'Phi-4',
        provider: 'Microsoft',
      ),
      LlmModel(
        id: 'microsoft/mai-ds-r1',
        displayName: 'MAI-DS-R1',
        provider: 'Microsoft',
      ),
    ];
    return models.toList()..sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
  }
}

class _MutableToolCall {
  String id = '';
  String type = 'function';
  String name = '';
  String arguments = '';
}
