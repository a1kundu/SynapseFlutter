import 'dart:async';

import 'package:flutter/foundation.dart';
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
}

/// Top-level function for [compute] — must not be a closure or instance method.
/// Runs a Lua script in a fresh sandboxed VM and returns the result.
LuaResult _computeEntry(String script) {
  return _runLuaSandboxed(script);
}

/// Run a script in a fresh sandboxed Lua VM.
LuaResult _runLuaSandboxed(String script) {
  final output = <String>[];
  final state = _createSandboxedState(output);
  try {
    return _executeLua(state, script, output);
  } catch (e) {
    return LuaResult(
      output: output.join('\n'),
      error: 'Unexpected error: $e',
    );
  }
}

/// Create a sandboxed LuaState with only safe libraries.
LuaState _createSandboxedState(List<String> outputBuffer) {
  final state = LuaState.newState();

  // Open all standard libs first.
  state.openLibs();

  // Remove dangerous modules and globals.
  for (final name in ['os', 'io', 'package', 'require', 'dofile', 'loadfile', 'debug']) {
    state.pushNil();
    state.setGlobal(name);
  }

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
LuaResult _executeLua(
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
        output: output.join('\n'),
        error: 'Syntax error: $errMsg',
      );
    }

    final callStatus = state.pCall(0, luaMultret, 0);
    if (callStatus != ThreadStatus.luaOk) {
      final errMsg = state.toStr(-1) ?? 'Unknown runtime error';
      state.pop(1);
      return LuaResult(
        output: output.join('\n'),
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
      output: output.join('\n'),
      returnValue: returnValue,
    );
  } catch (e) {
    return LuaResult(
      output: output.join('\n'),
      error: 'Execution failed: $e',
    );
  }
}

/// Sandboxed Lua 5.3 executor with timeout support.
///
/// Supports two modes:
/// - **Ephemeral** (persistent = false): fresh VM per execution.
/// - **Persistent** (persistent = true): reuses the VM across calls within a
///   session so the LLM can define functions in one call and use them later.
///
/// On native platforms, ephemeral execution runs via [compute] (real Isolate)
/// so the UI thread is never blocked and a hard timeout can kill the isolate.
/// On web, execution runs inline with a cooperative timeout since dart:isolate
/// is not available.
class LuaExecutor {
  /// Persistent Lua state (null when not yet created).
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
    return _executeEphemeral(script, timeout);
  }

  /// Reset the persistent Lua state (e.g., on conversation clear).
  void resetState() {
    _persistentState = null;
    _persistentOutput.clear();
  }

  // ── Ephemeral execution ───────────────────────────────────────────────

  /// On native: runs in a real Isolate via [compute] (non-blocking, hard kill
  /// on timeout). On web: runs inline with cooperative timeout.
  static Future<LuaResult> _executeEphemeral(
    String script,
    Duration timeout,
  ) async {
    try {
      if (kIsWeb) {
        // Web: no isolate support — run inline with timeout race.
        return await Future.any([
          Future(() => _runLuaSandboxed(script)),
          Future.delayed(timeout, () => LuaResult(
            error: 'Script execution timed out after ${timeout.inSeconds}s.',
            timedOut: true,
          )),
        ]);
      }
      // Native: compute() spawns a real Isolate.
      return await compute(_computeEntry, script).timeout(
        timeout,
        onTimeout: () => LuaResult(
          error: 'Script execution timed out after ${timeout.inSeconds}s.',
          timedOut: true,
        ),
      );
    } catch (e) {
      return LuaResult(error: 'Execution error: $e');
    }
  }

  // ── Persistent execution ──────────────────────────────────────────────

  /// Persistent mode runs inline (state can't cross isolate boundaries).
  /// Uses Future.any for cooperative timeout.
  Future<LuaResult> _executePersistent(
    String script,
    Duration timeout,
  ) async {
    try {
      return await Future.any([
        Future(() {
          _persistentState ??= _createSandboxedState(_persistentOutput);
          _persistentOutput.clear();
          return _executeLua(_persistentState!, script, _persistentOutput);
        }),
        Future.delayed(timeout, () => LuaResult(
          error: 'Script execution timed out after ${timeout.inSeconds}s.',
          timedOut: true,
        )),
      ]);
    } catch (e) {
      return LuaResult(error: 'Execution error: $e');
    }
  }
}
