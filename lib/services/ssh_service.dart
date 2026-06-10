import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

/// Maximum output size to return from SSH commands (50KB).
const _maxOutputSize = 50000;

/// SSH client service for executing commands on remote servers.
class SshService {
  /// Execute a command on a remote SSH server and return formatted output.
  ///
  /// Supports password and private-key authentication.
  static Future<String> execute({
    required String host,
    required String username,
    required String command,
    int port = 22,
    String? password,
    String? privateKey,
    String? passphrase,
    int timeoutSeconds = 30,
  }) async {
    // Validate authentication — at least one method must be provided.
    if ((password == null || password.isEmpty) &&
        (privateKey == null || privateKey.isEmpty)) {
      return 'Error: Either "password" or "private_key" must be provided for authentication.';
    }

    final timeout = Duration(seconds: timeoutSeconds.clamp(1, 120));

    SSHClient? client;

    try {
      // ── Connect ────────────────────────────────────────────────────────
      final socket = await SSHSocket.connect(host, port, timeout: timeout);

      // ── Authenticate ───────────────────────────────────────────────────
      if (privateKey != null && privateKey.isNotEmpty) {
        final keyPairs = SSHKeyPair.fromPem(
          privateKey,
          passphrase,
        );
        client = SSHClient(
          socket,
          username: username,
          identities: keyPairs,
        );
      } else {
        client = SSHClient(
          socket,
          username: username,
          onPasswordRequest: () => password!,
        );
      }

      // Wait for authentication to complete by running the command.
      // dartssh2 authenticates lazily on first channel/session request.

      // ── Execute command ────────────────────────────────────────────────
      final session = await client.execute(command).timeout(timeout);

      // Collect stdout.
      final stdoutBuf = BytesBuilder();
      await session.stdout.forEach((data) => stdoutBuf.add(data));

      // Collect stderr.
      final stderrBuf = BytesBuilder();
      await session.stderr.forEach((data) => stderrBuf.add(data));

      // Wait for exit status.
      await session.done;
      final exitCode = session.exitCode ?? -1;

      final stdout = utf8.decode(stdoutBuf.takeBytes(), allowMalformed: true);
      final stderr = utf8.decode(stderrBuf.takeBytes(), allowMalformed: true);

      return _formatResult(
        exitCode: exitCode,
        stdout: stdout,
        stderr: stderr,
        host: host,
        port: port,
        command: command,
      );
    } on SSHAuthFailError {
      return 'Error: SSH authentication failed for $username@$host:$port. '
          'Check your credentials.';
    } on SSHAuthAbortError {
      return 'Error: SSH authentication was aborted for $username@$host:$port.';
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('TimeoutException')) {
        return 'Error: SSH connection timed out after ${timeoutSeconds}s '
            'connecting to $host:$port.';
      }
      if (msg.contains('SocketException') || msg.contains('Connection refused')) {
        return 'Error: Could not connect to $host:$port — '
            'connection refused or host unreachable.';
      }
      return 'Error: SSH operation failed — $e';
    } finally {
      client?.close();
    }
  }

  /// Format the SSH execution result for the LLM.
  static String _formatResult({
    required int exitCode,
    required String stdout,
    required String stderr,
    required String host,
    required int port,
    required String command,
  }) {
    final buffer = StringBuffer();

    buffer.writeln('SSH $host:$port');
    buffer.writeln('Command: $command');
    buffer.writeln('Exit code: $exitCode');
    buffer.writeln();

    // Stdout
    if (stdout.isNotEmpty) {
      if (stdout.length > _maxOutputSize) {
        buffer.writeln('Stdout (truncated):');
        buffer.writeln(stdout.substring(0, _maxOutputSize));
        buffer.writeln('\n[stdout truncated at $_maxOutputSize chars]');
      } else {
        buffer.writeln('Stdout:');
        buffer.writeln(stdout);
      }
    } else {
      buffer.writeln('Stdout: (empty)');
    }

    // Stderr
    if (stderr.isNotEmpty) {
      buffer.writeln();
      if (stderr.length > _maxOutputSize) {
        buffer.writeln('Stderr (truncated):');
        buffer.writeln(stderr.substring(0, _maxOutputSize));
        buffer.writeln('\n[stderr truncated at $_maxOutputSize chars]');
      } else {
        buffer.writeln('Stderr:');
        buffer.writeln(stderr);
      }
    }

    return buffer.toString().trim();
  }
}
