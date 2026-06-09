#!/usr/bin/env python3
"""
GitHub Copilot OpenAI-Compatible REST API Bridge

A zero-dependency Python server (stdlib only + gh CLI) that bridges GitHub
Copilot's internal chat completions API to a local OpenAI-compatible REST
endpoint.

Authentication flow (all via gh CLI + GitHub device flow):
  1. One-time device flow auth using Copilot's OAuth app → cached OAuth token
  2. Token exchange via api.github.com/copilot_internal/v2/token → session token
  3. Proxied chat completions via api.githubcopilot.com/chat/completions

Usage:
    python3 copilot_bridge.py [--port 8080] [--host 127.0.0.1]

Then point any OpenAI-compatible client at:
    http://127.0.0.1:8080/v1/chat/completions
"""

import argparse
import http.client
import http.server
import json
import logging
import os
import ssl
import subprocess
import sys
import threading
import time
import urllib.parse
import uuid

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Copilot OAuth app client ID (same one VS Code / copilot.vim use)
COPILOT_CLIENT_ID = "Iv1.b507a08c87ecfe98"

# GitHub device flow endpoints
GITHUB_DEVICE_CODE_URL = "/login/device/code"
GITHUB_ACCESS_TOKEN_URL = "/login/oauth/access_token"
GITHUB_HOST = "github.com"

# Copilot internal API
COPILOT_TOKEN_ENDPOINT = "/copilot_internal/v2/token"
COPILOT_TOKEN_HOST = "api.github.com"

# Copilot chat completions host
COPILOT_CHAT_HOST_DEFAULT = "api.githubcopilot.com"
COPILOT_CHAT_ENDPOINT = "/chat/completions"
COPILOT_MODELS_ENDPOINT = "/models"

# How long to cache the models list (seconds)
MODELS_CACHE_TTL_SECONDS = 300

# Headers to mimic an official Copilot IDE extension
IDE_HEADERS = {
    "Editor-Version": "vscode/1.96.0",
    "Editor-Plugin-Version": "copilot/1.250.0",
    "User-Agent": "GithubCopilot/1.250.0",
}

# Token refresh buffer: refresh 2 minutes before expiry
TOKEN_REFRESH_BUFFER_SECONDS = 120

# Where to cache the Copilot OAuth token
TOKEN_CACHE_FILE = os.path.join(
    os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")),
    "copilot-bridge",
    "token.json",
)



logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("copilot-bridge")


# ---------------------------------------------------------------------------
# HTTPS helper
# ---------------------------------------------------------------------------
def _https_request(
    host: str,
    method: str,
    path: str,
    headers: dict | None = None,
    body: bytes | str | None = None,
) -> tuple[int, dict, bytes]:
    """Make an HTTPS request and return (status, headers_dict, body_bytes)."""
    ctx = ssl.create_default_context()
    conn = http.client.HTTPSConnection(host, context=ctx)
    try:
        if isinstance(body, str):
            body = body.encode("utf-8")
        conn.request(method, path, body=body, headers=headers or {})
        resp = conn.getresponse()
        resp_body = resp.read()
        resp_headers = {k.lower(): v for k, v in resp.getheaders()}
        return resp.status, resp_headers, resp_body
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# GitHub Device Flow Authentication for Copilot
# ---------------------------------------------------------------------------
def device_flow_login() -> str:
    """
    Run the GitHub device flow using Copilot's OAuth app.
    Returns an OAuth access token (ghu_...) scoped for Copilot.
    """
    log.info("Starting GitHub device flow for Copilot authentication...")

    # Step 1: Request device and user codes
    body = urllib.parse.urlencode({
        "client_id": COPILOT_CLIENT_ID,
        "scope": "copilot",
    })
    status, _, resp = _https_request(
        GITHUB_HOST,
        "POST",
        GITHUB_DEVICE_CODE_URL,
        headers={
            "Accept": "application/json",
            "Content-Type": "application/x-www-form-urlencoded",
        },
        body=body,
    )
    if status != 200:
        raise RuntimeError(f"Device code request failed (HTTP {status}): {resp.decode()}")

    data = json.loads(resp)
    device_code = data["device_code"]
    user_code = data["user_code"]
    verification_uri = data["verification_uri"]
    interval = data.get("interval", 5)
    expires_in = data.get("expires_in", 900)

    # Step 2: Show the user code and wait for authorization
    print()
    print("=" * 60)
    print("  GitHub Copilot Authentication Required")
    print()
    print(f"  1. Open: {verification_uri}")
    print(f"  2. Enter code: {user_code}")
    print()
    print("  Waiting for authorization...")
    print("=" * 60)
    print()

    # Try to open the browser via gh CLI
    try:
        subprocess.run(
            ["gh", "browse", "--url", verification_uri],
            capture_output=True,
            timeout=5,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass  # gh not available or no browser, user will open manually

    # Step 3: Poll for the access token
    deadline = time.time() + expires_in
    while time.time() < deadline:
        time.sleep(interval)

        poll_body = urllib.parse.urlencode({
            "client_id": COPILOT_CLIENT_ID,
            "device_code": device_code,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
        })
        status, _, resp = _https_request(
            GITHUB_HOST,
            "POST",
            GITHUB_ACCESS_TOKEN_URL,
            headers={
                "Accept": "application/json",
                "Content-Type": "application/x-www-form-urlencoded",
            },
            body=poll_body,
        )

        poll_data = json.loads(resp)

        if "access_token" in poll_data:
            log.info("Device flow authentication successful!")
            return poll_data["access_token"]

        error = poll_data.get("error", "")
        if error == "authorization_pending":
            continue
        elif error == "slow_down":
            interval = poll_data.get("interval", interval + 5)
            continue
        elif error == "expired_token":
            raise RuntimeError("Device code expired. Please re-run authentication.")
        elif error == "access_denied":
            raise RuntimeError("Authorization was denied by the user.")
        else:
            raise RuntimeError(f"Device flow poll error: {poll_data}")

    raise RuntimeError("Device code expired (timeout). Please re-run authentication.")


def save_oauth_token(token: str):
    """Save the Copilot OAuth token to disk."""
    os.makedirs(os.path.dirname(TOKEN_CACHE_FILE), mode=0o700, exist_ok=True)
    data = {"oauth_token": token, "saved_at": time.time()}
    with open(TOKEN_CACHE_FILE, "w") as f:
        json.dump(data, f)
    os.chmod(TOKEN_CACHE_FILE, 0o600)
    log.info("Copilot OAuth token cached at %s", TOKEN_CACHE_FILE)


def load_oauth_token() -> str | None:
    """Load the cached Copilot OAuth token from disk, or None."""
    try:
        with open(TOKEN_CACHE_FILE, "r") as f:
            data = json.load(f)
        token = data.get("oauth_token")
        if token:
            log.info("Loaded cached Copilot OAuth token.")
            return token
    except (FileNotFoundError, json.JSONDecodeError, KeyError):
        pass
    return None


# ---------------------------------------------------------------------------
# Token Manager – handles Copilot OAuth + session token exchange + caching
# ---------------------------------------------------------------------------
class TokenManager:
    """Manages Copilot OAuth token and session token exchange."""

    def __init__(self, copilot_chat_host: str | None = None):
        self._lock = threading.Lock()
        self._oauth_token: str | None = None
        self._copilot_token: str | None = None
        self._copilot_token_expires_at: float = 0
        self._copilot_chat_host: str = copilot_chat_host or COPILOT_CHAT_HOST_DEFAULT

    @property
    def copilot_chat_host(self) -> str:
        return self._copilot_chat_host

    # -- OAuth token management -----------------------------------------------

    def ensure_oauth_token(self) -> str:
        """
        Get a Copilot OAuth token. Loads from cache, or runs device flow.
        """
        if self._oauth_token:
            return self._oauth_token

        # Try loading from cache
        cached = load_oauth_token()
        if cached:
            self._oauth_token = cached
            return cached

        # Run device flow
        token = device_flow_login()
        save_oauth_token(token)
        self._oauth_token = token
        return token

    def clear_oauth_token(self):
        """Clear cached OAuth token (e.g., if it's expired/revoked)."""
        self._oauth_token = None
        try:
            os.remove(TOKEN_CACHE_FILE)
            log.info("Cleared cached OAuth token.")
        except FileNotFoundError:
            pass

    # -- Copilot session token exchange ---------------------------------------

    def _exchange_for_copilot_token(self, oauth_token: str) -> dict:
        """Exchange a Copilot OAuth token for a short-lived session token."""
        headers = {
            "Authorization": f"token {oauth_token}",
            "Accept": "application/json",
            **IDE_HEADERS,
        }
        status, _, resp = _https_request(
            COPILOT_TOKEN_HOST, "GET", COPILOT_TOKEN_ENDPOINT, headers=headers
        )

        if status == 401 or status == 403:
            raise PermissionError(
                f"OAuth token rejected (HTTP {status}). Token may be expired or revoked."
            )
        if status != 200:
            raise RuntimeError(
                f"Copilot token exchange failed (HTTP {status}): {resp.decode()[:500]}"
            )

        data = json.loads(resp)
        if "token" not in data:
            raise RuntimeError(
                f"Copilot token exchange: 'token' field missing: {resp.decode()[:500]}"
            )
        return data

    # -- Public API ----------------------------------------------------------

    def get_copilot_token(self) -> str:
        """Get a valid Copilot session token, refreshing if needed."""
        with self._lock:
            now = time.time()
            if (
                self._copilot_token is not None
                and now < self._copilot_token_expires_at - TOKEN_REFRESH_BUFFER_SECONDS
            ):
                return self._copilot_token

            oauth_token = self.ensure_oauth_token()
            log.info("Exchanging OAuth token for Copilot session token...")

            try:
                data = self._exchange_for_copilot_token(oauth_token)
            except PermissionError:
                # OAuth token might be revoked; re-authenticate
                log.warning("OAuth token rejected, re-authenticating...")
                self.clear_oauth_token()
                oauth_token = self.ensure_oauth_token()
                data = self._exchange_for_copilot_token(oauth_token)

            self._copilot_token = data["token"]
            # Parse expiry: the response includes `expires_at` as epoch seconds
            expires_at = data.get("expires_at")
            if isinstance(expires_at, (int, float)):
                self._copilot_token_expires_at = float(expires_at)
            else:
                # Fallback: assume 25-minute lifetime
                self._copilot_token_expires_at = now + 25 * 60

            remaining = int(self._copilot_token_expires_at - now)
            log.info(
                "Copilot session token acquired (expires in %d seconds).", remaining
            )
            return self._copilot_token


# ---------------------------------------------------------------------------
# Copilot API Proxy – forwards requests to the Copilot chat endpoint
# ---------------------------------------------------------------------------
class CopilotProxy:
    """Proxies OpenAI-compatible requests to the Copilot API."""

    def __init__(self, token_manager: TokenManager):
        self.tm = token_manager
        self._models_cache: list | None = None
        self._models_cache_time: float = 0
        self._models_lock = threading.Lock()

    def fetch_models(self) -> list:
        """Fetch available models from the Copilot API, with caching."""
        with self._models_lock:
            now = time.time()
            if (
                self._models_cache is not None
                and now - self._models_cache_time < MODELS_CACHE_TTL_SECONDS
            ):
                return self._models_cache

            copilot_token = self.tm.get_copilot_token()
            host = self.tm.copilot_chat_host

            headers = {
                "Authorization": f"Bearer {copilot_token}",
                "Accept": "application/json",
                **IDE_HEADERS,
            }

            status, _, resp_body = _https_request(
                host, "GET", COPILOT_MODELS_ENDPOINT, headers=headers
            )

            if status != 200:
                log.warning("Failed to fetch models (HTTP %d), using cache", status)
                if self._models_cache is not None:
                    return self._models_cache
                return []

            data = json.loads(resp_body)
            raw_models = data.get("data", [])

            # Normalize to OpenAI-compatible format
            models = []
            for m in raw_models:
                model_entry = {
                    "id": m.get("id", ""),
                    "object": "model",
                    "created": 1700000000,
                    "owned_by": m.get("vendor", "copilot"),
                }
                # Preserve useful extra fields
                if "name" in m:
                    model_entry["name"] = m["name"]
                if "capabilities" in m:
                    caps = m["capabilities"]
                    limits = caps.get("limits", {})
                    supports = caps.get("supports", {})
                    model_entry["capabilities"] = {
                        "type": caps.get("type", "chat"),
                        "family": caps.get("family", m.get("id", "")),
                        "max_context_window_tokens": limits.get("max_context_window_tokens"),
                        "max_output_tokens": limits.get("max_output_tokens"),
                        "supports_streaming": supports.get("streaming", False),
                        "supports_tool_calls": supports.get("tool_calls", False),
                        "supports_vision": supports.get("vision", False),
                    }
                if m.get("preview"):
                    model_entry["preview"] = True
                models.append(model_entry)

            self._models_cache = models
            self._models_cache_time = now
            log.info("Models catalog refreshed: %d models available.", len(models))
            return models

    def chat_completions(self, request_body: bytes) -> tuple[int, dict, bytes]:
        """
        Forward a chat/completions request to Copilot.
        Returns (status_code, response_headers_dict, response_body_bytes).
        """
        copilot_token = self.tm.get_copilot_token()
        host = self.tm.copilot_chat_host

        headers = {
            "Authorization": f"Bearer {copilot_token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
            "X-Request-Id": str(uuid.uuid4()),
            **IDE_HEADERS,
        }

        # Check if streaming is requested
        try:
            payload = json.loads(request_body)
            is_stream = payload.get("stream", False)
        except (json.JSONDecodeError, KeyError):
            is_stream = False

        if is_stream:
            headers["Accept"] = "text/event-stream"

        ctx = ssl.create_default_context()
        conn = http.client.HTTPSConnection(host, context=ctx)
        try:
            conn.request("POST", COPILOT_CHAT_ENDPOINT, body=request_body, headers=headers)
            resp = conn.getresponse()
            resp_body = resp.read()
            resp_headers = {k: v for k, v in resp.getheaders()}
            return resp.status, resp_headers, resp_body
        finally:
            conn.close()

    def chat_completions_stream(self, request_body: bytes):
        """
        Forward a streaming chat/completions request to Copilot.
        Yields raw chunks as they arrive.
        """
        copilot_token = self.tm.get_copilot_token()
        host = self.tm.copilot_chat_host

        headers = {
            "Authorization": f"Bearer {copilot_token}",
            "Content-Type": "application/json",
            "Accept": "text/event-stream",
            "X-Request-Id": str(uuid.uuid4()),
            **IDE_HEADERS,
        }

        ctx = ssl.create_default_context()
        conn = http.client.HTTPSConnection(host, context=ctx)
        try:
            conn.request("POST", COPILOT_CHAT_ENDPOINT, body=request_body, headers=headers)
            resp = conn.getresponse()

            if resp.status != 200:
                body = resp.read()
                yield resp.status, body
                return

            # Stream chunks
            yield resp.status, None
            while True:
                chunk = resp.read(4096)
                if not chunk:
                    break
                yield None, chunk
        finally:
            conn.close()


# ---------------------------------------------------------------------------
# HTTP Request Handler – OpenAI-compatible REST endpoints
# ---------------------------------------------------------------------------
class BridgeHandler(http.server.BaseHTTPRequestHandler):
    """HTTP handler exposing OpenAI-compatible REST API endpoints."""

    # Force HTTP/1.1 responses (required for Transfer-Encoding: chunked streaming)
    protocol_version = "HTTP/1.1"

    # Shared across all handler instances
    proxy: CopilotProxy = None  # type: ignore[assignment]

    def log_message(self, format, *args):
        log.info(f"{self.client_address[0]} - {format % args}")

    def _set_cors_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")

    def _send_json(self, status: int, data: dict | list):
        body = json.dumps(data, indent=2).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self._set_cors_headers()
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_error_json(self, status: int, message: str, error_type: str = "server_error"):
        self._send_json(
            status,
            {
                "error": {
                    "message": message,
                    "type": error_type,
                    "code": status,
                }
            },
        )

    def _read_body(self) -> bytes:
        content_length = int(self.headers.get("Content-Length", 0))
        return self.rfile.read(content_length)

    # -- Route handlers -------------------------------------------------------

    def do_OPTIONS(self):
        self.send_response(204)
        self._set_cors_headers()
        self.end_headers()

    def do_GET(self):
        path = self.path.rstrip("/")

        if path in ("/v1/models", "/models"):
            self._handle_models()
        elif path in ("/health", "/v1/health", "/"):
            self._handle_health()
        else:
            self._send_error_json(404, f"Unknown endpoint: {self.path}", "not_found")

    def do_POST(self):
        path = self.path.rstrip("/")

        if path in ("/v1/chat/completions", "/chat/completions"):
            self._handle_chat_completions()
        else:
            self._send_error_json(404, f"Unknown endpoint: {self.path}", "not_found")

    # -- Endpoint implementations ---------------------------------------------

    def _handle_health(self):
        self._send_json(200, {"status": "ok", "service": "copilot-bridge"})

    def _handle_models(self):
        try:
            models = self.proxy.fetch_models()
            self._send_json(200, {"object": "list", "data": models})
        except Exception as e:
            log.exception("Failed to fetch models")
            self._send_error_json(502, f"Failed to fetch models: {e}", "upstream_error")

    def _handle_chat_completions(self):
        body = self._read_body()

        # Validate request body
        try:
            payload = json.loads(body)
        except json.JSONDecodeError as e:
            self._send_error_json(400, f"Invalid JSON: {e}", "invalid_request")
            return

        if "messages" not in payload:
            self._send_error_json(
                400, "Missing required field: 'messages'", "invalid_request"
            )
            return

        # Default model if not specified
        if "model" not in payload:
            payload["model"] = "gpt-4o"
            body = json.dumps(payload).encode("utf-8")

        is_stream = payload.get("stream", False)

        try:
            if is_stream:
                self._handle_streaming(body)
            else:
                self._handle_non_streaming(body)
        except BrokenPipeError:
            log.debug("Client disconnected during response")
        except ConnectionResetError:
            log.debug("Client connection reset")
        except RuntimeError as e:
            log.error("Proxy error: %s", e)
            self._send_error_json(502, str(e), "upstream_error")
        except Exception as e:
            log.exception("Unexpected error during proxy request")
            self._send_error_json(500, f"Internal server error: {e}")

    def _handle_non_streaming(self, body: bytes):
        status, resp_headers, resp_body = self.proxy.chat_completions(body)

        self.send_response(status)
        self.send_header("Content-Type", resp_headers.get("content-type", "application/json"))
        self._set_cors_headers()
        self.send_header("Content-Length", str(len(resp_body)))
        self.end_headers()
        self.wfile.write(resp_body)

    def _handle_streaming(self, body: bytes):
        chunks = self.proxy.chat_completions_stream(body)

        first_status, first_data = next(chunks)

        if first_data is not None:
            # Error response (non-200)
            self.send_response(first_status)
            self.send_header("Content-Type", "application/json")
            self._set_cors_headers()
            self.send_header("Content-Length", str(len(first_data)))
            self.end_headers()
            self.wfile.write(first_data)
            return

        # Streaming response
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.send_header("Transfer-Encoding", "chunked")
        self._set_cors_headers()
        self.end_headers()

        for _, chunk in chunks:
            if chunk:
                # Send as HTTP chunked transfer
                chunk_size = f"{len(chunk):x}\r\n".encode()
                self.wfile.write(chunk_size)
                self.wfile.write(chunk)
                self.wfile.write(b"\r\n")
                self.wfile.flush()

        # Final zero-length chunk
        self.wfile.write(b"0\r\n\r\n")
        self.wfile.flush()


# ---------------------------------------------------------------------------
# Server setup
# ---------------------------------------------------------------------------
class ThreadedHTTPServer(http.server.ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True


def run_server(host: str = "127.0.0.1", port: int = 8080, copilot_host: str | None = None):
    """Start the bridge server."""

    # Initialize token manager
    tm = TokenManager(copilot_chat_host=copilot_host)

    log.info("Ensuring Copilot authentication...")
    try:
        tm.ensure_oauth_token()
    except RuntimeError as e:
        log.error("Authentication failed: %s", e)
        sys.exit(1)

    log.info("Pre-fetching Copilot session token...")
    try:
        tm.get_copilot_token()
    except PermissionError:
        log.warning("Cached OAuth token was rejected, re-authenticating...")
        tm.clear_oauth_token()
        try:
            tm.ensure_oauth_token()
            tm.get_copilot_token()
        except RuntimeError as e:
            log.error("Copilot token exchange failed: %s", e)
            sys.exit(1)
    except RuntimeError as e:
        log.error("Copilot token exchange failed: %s", e)
        log.error(
            "Make sure you have an active GitHub Copilot subscription."
        )
        sys.exit(1)

    proxy = CopilotProxy(tm)
    BridgeHandler.proxy = proxy

    server = ThreadedHTTPServer((host, port), BridgeHandler)

    log.info("=" * 60)
    log.info("  Copilot Bridge Server")
    log.info("  Listening on http://%s:%d", host, port)
    log.info("")
    log.info("  Endpoints:")
    log.info("    GET  /v1/models              - List models")
    log.info("    POST /v1/chat/completions    - Chat completions")
    log.info("    GET  /health                 - Health check")
    log.info("")
    log.info("  Copilot backend: %s", tm.copilot_chat_host)
    log.info("  Token auto-refresh: enabled")
    log.info("=" * 60)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log.info("\nShutting down...")
        server.shutdown()


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(
        description="GitHub Copilot OpenAI-Compatible REST API Bridge",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s                              # Start on 127.0.0.1:8080
  %(prog)s --port 5000                  # Start on port 5000
  %(prog)s --host 0.0.0.0 --port 8000  # Listen on all interfaces
  %(prog)s --login                      # Authenticate with GitHub (one-time)
  %(prog)s --logout                     # Clear cached auth token

  # Test with curl:
  curl http://localhost:8080/v1/models
  curl http://localhost:8080/v1/chat/completions \\
    -H "Content-Type: application/json" \\
    -d '{"model":"gpt-4o","messages":[{"role":"user","content":"Hello!"}]}'

  # Use with any OpenAI-compatible client:
  export OPENAI_BASE_URL=http://localhost:8080/v1
  export OPENAI_API_KEY=dummy
        """,
    )
    parser.add_argument(
        "--host",
        default=os.environ.get("COPILOT_BRIDGE_HOST", "127.0.0.1"),
        help="Host to bind to (default: 127.0.0.1, env: COPILOT_BRIDGE_HOST)",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=int(os.environ.get("COPILOT_BRIDGE_PORT", "8080")),
        help="Port to listen on (default: 8080, env: COPILOT_BRIDGE_PORT)",
    )
    parser.add_argument(
        "--copilot-host",
        default=os.environ.get("COPILOT_CHAT_HOST"),
        help=(
            "Override Copilot chat host "
            "(default: api.githubcopilot.com, "
            "use api.individual.githubcopilot.com for Individual plans, "
            "env: COPILOT_CHAT_HOST)"
        ),
    )
    parser.add_argument(
        "--login",
        action="store_true",
        help="Run the device flow authentication and exit",
    )
    parser.add_argument(
        "--logout",
        action="store_true",
        help="Clear cached Copilot OAuth token and exit",
    )
    parser.add_argument(
        "--debug",
        action="store_true",
        help="Enable debug logging",
    )

    args = parser.parse_args()

    if args.debug:
        logging.getLogger().setLevel(logging.DEBUG)

    if args.logout:
        try:
            os.remove(TOKEN_CACHE_FILE)
            print("Copilot OAuth token cleared.")
        except FileNotFoundError:
            print("No cached token found.")
        return

    if args.login:
        token = device_flow_login()
        save_oauth_token(token)
        print("Authentication successful! Token cached.")
        print(f"You can now run: python3 {sys.argv[0]}")
        return

    run_server(host=args.host, port=args.port, copilot_host=args.copilot_host)


if __name__ == "__main__":
    main()
