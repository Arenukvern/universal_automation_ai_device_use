// Library for validating reusable GitHub Actions workflow_call inputs.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

final usesReusablePattern = RegExp(
  r'^\s*uses:\s+([^/\s]+)/([^/\s]+)/\.github/workflows/([^@\s]+)@(\S+)\s*$',
);

class ReusableWorkflowCall {
  ReusableWorkflowCall({
    required this.callerPath,
    required this.jobName,
    required this.owner,
    required this.repo,
    required this.workflowFile,
    required this.ref,
    required this.withKeys,
  });

  final String callerPath;
  final String jobName;
  final String owner;
  final String repo;
  final String workflowFile;
  final String ref;
  final List<String> withKeys;

  String get slug => '$owner/$repo/.github/workflows/$workflowFile@$ref';

  String get rawUrl =>
      'https://raw.githubusercontent.com/$owner/$repo/$ref'
      '/.github/workflows/$workflowFile';
}

class WorkflowFetchException implements Exception {
  WorkflowFetchException(this.message, {this.retryable = true});

  final String message;
  final bool retryable;

  @override
  String toString() => message;
}

/// Parses `workflow_call` input names from a reusable workflow YAML document.
Set<String> parseWorkflowCallInputs(String yaml) {
  final lines = yaml.split('\n');
  var inWorkflowCall = false;
  var inInputs = false;
  var inputsIndent = 0;
  final names = <String>{};

  for (final line in lines) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('workflow_call:')) {
      inWorkflowCall = true;
      continue;
    }
    if (!inWorkflowCall) {
      continue;
    }
    if (trimmed.startsWith('inputs:')) {
      inInputs = true;
      inputsIndent = line.indexOf('inputs:');
      continue;
    }
    if (inInputs) {
      if (trimmed.isEmpty) {
        continue;
      }
      final indent = line.length - trimmed.length;
      if (indent <= inputsIndent) {
        inInputs = false;
        continue;
      }
      final key = RegExp(r'^([a-zA-Z0-9_-]+):').firstMatch(trimmed);
      if (key != null && indent == inputsIndent + 2) {
        names.add(key.group(1)!);
      }
    }
  }
  return names;
}

List<ReusableWorkflowCall> extractReusableCalls(String content, String path) {
  final lines = content.split('\n');
  final calls = <ReusableWorkflowCall>[];

  for (var i = 0; i < lines.length; i++) {
    final usesMatch = usesReusablePattern.firstMatch(lines[i]);
    if (usesMatch == null) {
      continue;
    }

    var jobName = 'unknown';
    for (var k = i - 1; k >= 0; k--) {
      if (lines[k].startsWith('jobs:')) {
        break;
      }
      final jobHeader = RegExp(r'^  ([a-zA-Z0-9_-]+):\s*$').firstMatch(lines[k]);
      if (jobHeader != null) {
        jobName = jobHeader.group(1)!;
        break;
      }
    }

    final withKeys = <String>[];
    for (var j = i + 1; j < lines.length; j++) {
      final next = lines[j];
      if (next.trim().isEmpty) {
        continue;
      }
      if (!next.startsWith('    ')) {
        break;
      }
      if (RegExp(r'^    with:\s*$').matchAsPrefix(next) != null) {
        for (var w = j + 1; w < lines.length; w++) {
          final wline = lines[w];
          if (wline.trim().isEmpty) {
            continue;
          }
          if (!wline.startsWith('      ')) {
            break;
          }
          final keyMatch = RegExp(r'^      ([a-zA-Z0-9_-]+):').firstMatch(wline);
          if (keyMatch != null) {
            withKeys.add(keyMatch.group(1)!);
          }
        }
        break;
      }
    }

    calls.add(
      ReusableWorkflowCall(
        callerPath: path,
        jobName: jobName,
        owner: usesMatch.group(1)!,
        repo: usesMatch.group(2)!,
        workflowFile: usesMatch.group(3)!,
        ref: usesMatch.group(4)!,
        withKeys: withKeys,
      ),
    );
  }

  return calls;
}

/// Returns validation errors for undeclared `with:` keys (empty if valid).
List<String> validateWithKeysAgainstDeclared(
  ReusableWorkflowCall call,
  Set<String> declaredInputs,
) {
  final errors = <String>[];
  for (final key in call.withKeys) {
    if (!declaredInputs.contains(key)) {
      errors.add(
        '${call.callerPath}: job "${call.jobName}" passes undeclared input '
        '"$key" to ${call.slug} (declared: ${declaredInputs.join(", ")})',
      );
    }
  }
  return errors;
}

/// For tests: return synthetic HTTP results instead of using [HttpClient].
typedef ReusableWorkflowTestResponseProvider = Future<({int statusCode, String body})>
    Function(Uri url);

Future<String> fetchReusableWorkflowYaml(
  ReusableWorkflowCall call, {
  String? githubToken,
  HttpClient? httpClient,
  ReusableWorkflowTestResponseProvider? testResponseProvider,
  int maxAttempts = 3,
  Duration requestTimeout = const Duration(seconds: 30),
  Duration connectTimeout = const Duration(seconds: 15),
}) async {
  HttpClient? client;
  final ownsClient = httpClient == null && testResponseProvider == null;
  if (testResponseProvider == null) {
    client = httpClient ?? HttpClient();
    client!.connectionTimeout = connectTimeout;
    client.idleTimeout = connectTimeout;
  }

  try {
    Object? lastError;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(
          Duration(milliseconds: 500 * (1 << (attempt - 1))),
        );
      }
      try {
        if (testResponseProvider != null) {
          final synthetic = await testResponseProvider(Uri.parse(call.rawUrl));
          return _responseBodyOrThrow(call, synthetic.statusCode, synthetic.body);
        }
        return await _fetchOnce(
          client!,
          call,
          githubToken: githubToken,
          requestTimeout: requestTimeout,
        );
      } on WorkflowFetchException catch (e) {
        if (!e.retryable) {
          rethrow;
        }
        lastError = e;
      } on TimeoutException catch (e) {
        lastError = e;
      } on IOException catch (e) {
        lastError = e;
      }
    }
    throw WorkflowFetchException(
      'could not fetch ${call.slug}: $lastError',
    );
  } finally {
    if (ownsClient) {
      client?.close(force: true);
    }
  }
}

String _responseBodyOrThrow(
  ReusableWorkflowCall call,
  int statusCode,
  String body,
) {
  if (statusCode == 200) {
    return body;
  }
  if (statusCode >= 400 && statusCode < 500) {
    throw WorkflowFetchException(
      'could not fetch ${call.slug} (HTTP $statusCode)',
      retryable: false,
    );
  }
  if (statusCode >= 500) {
    throw WorkflowFetchException(
      'could not fetch ${call.slug} (HTTP $statusCode)',
      retryable: true,
    );
  }
  throw WorkflowFetchException(
    'could not fetch ${call.slug} (HTTP $statusCode)',
    retryable: false,
  );
}

Future<String> _fetchOnce(
  HttpClient client,
  ReusableWorkflowCall call, {
  required String? githubToken,
  required Duration requestTimeout,
}) async {
  final uri = Uri.parse(call.rawUrl);
  final request = await client.getUrl(uri);
  if (githubToken != null && githubToken.isNotEmpty) {
    request.headers.set('Authorization', 'Bearer $githubToken');
    request.headers.set('User-Agent', 'ua-reusable-workflow-input-check');
  }

  final response = await request.close().timeout(requestTimeout);
  if (response.statusCode != 200) {
    await response.drain<void>();
    return _responseBodyOrThrow(call, response.statusCode, '');
  }
  final body = await response.transform(utf8.decoder).join();
  return _responseBodyOrThrow(call, response.statusCode, body);
}

typedef ReusableWorkflowYamlFetcher = Future<String> Function(
  ReusableWorkflowCall call,
);

Future<List<String>> validateRepositoryWorkflows({
  required Directory workflowDirectory,
  String? githubToken,
  HttpClient? httpClient,
  ReusableWorkflowYamlFetcher? fetchYaml,
}) async {
  final fetch = fetchYaml ??
      (ReusableWorkflowCall call) => fetchReusableWorkflowYaml(
            call,
            githubToken: githubToken,
            httpClient: httpClient,
          );

  final errors = <String>[];
  for (final entity in workflowDirectory.listSync().whereType<File>()) {
    if (!entity.path.endsWith('.yml') && !entity.path.endsWith('.yaml')) {
      continue;
    }
    final content = entity.readAsStringSync();
    final calls = extractReusableCalls(content, entity.path);
    for (final call in calls) {
      if (call.withKeys.isEmpty) {
        continue;
      }
      final yaml = await fetch(call);
      final declared = parseWorkflowCallInputs(yaml);
      errors.addAll(validateWithKeysAgainstDeclared(call, declared));
    }
  }
  return errors;
}

Directory findRepoRootWithWorkflows() {
  var dir = Directory.current;
  while (true) {
    if (Directory('${dir.path}/.github/workflows').existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('Could not find .github/workflows');
    }
    dir = parent;
  }
}
