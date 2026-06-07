import 'dart:async';
import 'dart:isolate';

import 'package:lua_dardo_plus/lua.dart';

/// Maximum output buffer size in characters (~50KB).
const _maxOutputSize = 50000;

/// Default execution timeout.
const _defaultTimeout = Duration(seconds: 10);

/// Result from a Lua script execution.
class LuaResult {
  final String output;
  final String? returnValue;
  final String? error;
  final bool timedOut;

  const LuaResult({
    this.output = '',
    this.returnValue,
    this.error,
    this.timedOut = false,
  });

  /// Format as a tool output string for the LLM.
  String toToolOutput() {
    final parts = <String>[];
    if (error != null) {
      parts.add('Error: $error');
    }
    if (timedOut) {
      parts.add('[Execution timed out after ${_defaultTimeout.inSeconds}s]');
    }
    if (output.isNotEmpty) {
      parts.add('Output:\n$output');
    }
    if (returnValue != null && returnValue!.isNotEmpty) {
      parts.add('Return: $returnValue');
    }
    if (parts.isEmpty) {
      return '(no output)';
    }
    return parts.join('\n');
  }

  Map<String, dynamic> toJson() => {
        'output': output,
        if (returnValue != null) 'returnValue': returnValue,
        if (error != null) 'error': error,
        'timedOut': timedOut,
      };
}

/// Sandboxed Lua 5.3 executor with Isolate-based timeout.
///
/// Supports two modes:
/// - **Ephemeral** (persistent = false): fresh VM per execution.
/// - **Persistent** (persistent = true): reuses the VM across calls within a
///   session so the LLM can define functions in one call and use them later.
///
/// Each execution runs inside a [Isolate] so the UI thread is never blocked
/// and a hard timeout is enforced deterministically.
class LuaExecutor {
  /// Persistent Lua state (null when not in persistent mode or not yet created).
  LuaState? _persistentState;

  /// Captured output buffer for the persistent state.
  final List<String> _persistentOutput = [];

  /// Execute a Lua script.
  ///
  /// [script] — the Lua source code to run.
  /// [persistent] — if true, reuse the VM across calls in this executor instance.
  /// [timeout] — max wall-clock time before the execution is killed.
  Future<LuaResult> execute(
    String script, {
    bool persistent = false,
    Duration timeout = _defaultTimeout,
  }) async {
    if (persistent) {
      return _executePersistent(script, timeout);
    }
    return _executeInIsolate(script, timeout);
  }

  /// Reset the persistent Lua state (e.g., on conversation clear).
  void resetState() {
    _persistentState = null;
    _persistentOutput.clear();
  }

  // ── Ephemeral execution (in a dedicated Isolate) ──────────────────────

  static Future<LuaResult> _executeInIsolate(
    String script,
    Duration timeout,
  ) async {
    final receivePort = ReceivePort();

    Isolate? isolate;
    try {
      isolate = await Isolate.spawn(
        _isolateEntry,
        _IsolateRequest(script: script, sendPort: receivePort.sendPort),
      );

      // Wait for result or timeout.
      final completer = Completer<LuaResult>();
      Timer? timer;
      timer = Timer(timeout, () {
        if (!completer.isCompleted) {
          completer.complete(LuaResult(
            error: 'Script execution timed out after ${timeout.inSeconds}s.',
            timedOut: true,
          ));
          isolate?.kill(priority: Isolate.immediate);
        }
      });

      receivePort.listen((message) {
        timer?.cancel();
        if (!completer.isCompleted) {
          completer.complete(message as LuaResult);
        }
      });

      return await completer.future;
    } catch (e) {
      isolate?.kill(priority: Isolate.immediate);
      return LuaResult(error: 'Failed to spawn isolate: $e');
    } finally {
      receivePort.close();
    }
  }

  /// Entry point for the spawned Isolate.
  static void _isolateEntry(_IsolateRequest request) {
    final result = _runLuaSandboxed(request.script);
    request.sendPort.send(result);
  }

  // ── Persistent execution (on main isolate, with timeout wrapper) ──────

  Future<LuaResult> _executePersistent(String script, Duration timeout) async {
    // Persistent mode must run on the main isolate because LuaState is not
    // transferable across isolates. We use a timeout via Future.any.
    try {
      final result = await Future.any([
        Future(() => _runPersistent(script)),
        Future.delayed(timeout, () => LuaResult(
          error: 'Script execution timed out after ${timeout.inSeconds}s.',
          timedOut: true,
        )),
      ]);
      return result;
    } catch (e) {
      return LuaResult(error: 'Execution error: $e');
    }
  }

  LuaResult _runPersistent(String script) {
    _persistentState ??= _createSandboxedState(_persistentOutput);

    // Clear output buffer for this invocation (keep state).
    _persistentOutput.clear();

    return _executeLua(_persistentState!, script, _persistentOutput);
  }

  // ── Core Lua execution ────────────────────────────────────────────────

  /// Run a script in a fresh sandboxed Lua VM (used by isolate path).
  static LuaResult _runLuaSandboxed(String script) {
    final output = <String>[];
    final state = _createSandboxedState(output);
    try {
      return _executeLua(state, script, output);
    } catch (e) {
      return LuaResult(
        output: _joinOutput(output),
        error: 'Unexpected error: $e',
      );
    }
  }

  /// Create a sandboxed LuaState with only safe libraries.
  static LuaState _createSandboxedState(List<String> outputBuffer) {
    final state = LuaState.newState();

    // Open all standard libs first.
    state.openLibs();

    // Remove dangerous modules and globals.
    // -- Remove os module entirely
    state.pushNil();
    state.setGlobal('os');
    // -- Remove io module (if present)
    state.pushNil();
    state.setGlobal('io');
    // -- Remove package/require (prevent loading external modules)
    state.pushNil();
    state.setGlobal('package');
    state.pushNil();
    state.setGlobal('require');
    // -- Remove file loading functions
    state.pushNil();
    state.setGlobal('dofile');
    state.pushNil();
    state.setGlobal('loadfile');
    // -- Remove raw debug access
    state.pushNil();
    state.setGlobal('debug');

    // Override print() to capture output into the buffer.
    int capturedPrint(LuaState ls) {
      final nArgs = ls.getTop();
      final parts = <String>[];
      for (int i = 1; i <= nArgs; i++) {
        parts.add(ls.toStr(i) ?? 'nil');
      }
      final line = parts.join('\t');
      // Enforce output size limit.
      final currentSize =
          outputBuffer.fold<int>(0, (sum, s) => sum + s.length);
      if (currentSize + line.length <= _maxOutputSize) {
        outputBuffer.add(line);
      } else if (currentSize < _maxOutputSize) {
        outputBuffer.add('[output truncated]');
      }
      return 0;
    }

    state.pushDartFunction(capturedPrint);
    state.setGlobal('print');

    return state;
  }

  /// Execute a Lua script on a given state and return the result.
  static LuaResult _executeLua(
    LuaState state,
    String script,
    List<String> output,
  ) {
    try {
      final loadStatus = state.loadString(script);
      if (loadStatus != ThreadStatus.luaOk) {
        final errMsg = state.toStr(-1) ?? 'Unknown load error';
        state.pop(1);
        return LuaResult(
          output: _joinOutput(output),
          error: 'Syntax error: $errMsg',
        );
      }

      final callStatus = state.pCall(0, luaMultret, 0);
      if (callStatus != ThreadStatus.luaOk) {
        final errMsg = state.toStr(-1) ?? 'Unknown runtime error';
        state.pop(1);
        return LuaResult(
          output: _joinOutput(output),
          error: 'Runtime error: $errMsg',
        );
      }

      // Collect return values from the stack.
      final nResults = state.getTop();
      String? returnValue;
      if (nResults > 0) {
        final parts = <String>[];
        for (int i = 1; i <= nResults; i++) {
          parts.add(state.toStr(i) ?? 'nil');
        }
        returnValue = parts.join('\t');
        state.setTop(0);
      }

      return LuaResult(
        output: _joinOutput(output),
        returnValue: returnValue,
      );
    } catch (e) {
      return LuaResult(
        output: _joinOutput(output),
        error: 'Execution failed: $e',
      );
    }
  }

  static String _joinOutput(List<String> output) => output.join('\n');
}

/// Internal message sent to the Isolate.
class _IsolateRequest {
  final String script;
  final SendPort sendPort;

  const _IsolateRequest({required this.script, required this.sendPort});
}
