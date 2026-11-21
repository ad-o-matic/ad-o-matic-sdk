#!/usr/bin/env node
/**
 * Ad-o-matic Zero-Dependency Local Stdio MCP Server (v5.8)
 *
 * Bridges any local stdio MCP client (Claude Desktop, Claude Code, Cursor, Windsurf,
 * Antigravity, GitHub Copilot, Zed, Cline) directly to the live Ad-o-matic MCP endpoint
 * at https://ad-o-matic.com/mcp (with automatic failover to https://2-29-104-72.nip.io/mcp)
 * using built-in Node 18+ fetch (zero npm dependencies!).
 *
 * Exposes 4 AI-agent tools:
 * - adomatic_get_integration (Android Compose, iOS SwiftUI, Flutter, React Native, WebView)
 * - adomatic_onboard_app
 * - adomatic_verify_integration
 * - adomatic_network_status
 */

const readline = require('readline');

const EXPLICIT_MCP_URL = process.env.ADOMATIC_MCP_URL || '';
const PRIMARY_MCP_URL = 'https://ad-o-matic.com/mcp';
const MIRROR_MCP_URL = 'https://2-29-104-72.nip.io/mcp';
let activeMcpUrl = EXPLICIT_MCP_URL || PRIMARY_MCP_URL;

const rl = readline.createInterface({
  input: process.stdin,
  terminal: false
});

async function postMcpWithFailover(payload) {
  const candidates = EXPLICIT_MCP_URL
    ? [EXPLICIT_MCP_URL]
    : (activeMcpUrl === MIRROR_MCP_URL ? [MIRROR_MCP_URL, PRIMARY_MCP_URL] : [PRIMARY_MCP_URL, MIRROR_MCP_URL]);

  let lastErr;
  for (let i = 0; i < candidates.length; i++) {
    const url = candidates[i];
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), i === 0 ? 3000 : 8000);
    try {
      const resp = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
        body: JSON.stringify(payload),
        signal: ctrl.signal
      });
      clearTimeout(timer);
      activeMcpUrl = url;
      return resp;
    } catch (err) {
      clearTimeout(timer);
      lastErr = err;
    }
  }
  throw lastErr || new Error('Ad-o-matic MCP endpoints unreachable');
}

async function processLine(line) {
  const trimmed = String(line || '').trim();
  if (!trimmed) return;

  let parsed;
  try {
    parsed = JSON.parse(trimmed);
  } catch (_) {
    process.stdout.write(JSON.stringify({
      jsonrpc: '2.0',
      id: null,
      error: { code: -32700, message: 'Parse error' }
    }) + '\n');
    return;
  }

  // Notifications without an id do not expect a response
  if (parsed && !Array.isArray(parsed) && parsed.id === undefined) {
    return;
  }

  try {
    const resp = await postMcpWithFailover(parsed);
    if (resp.status === 202) return;
    const data = await resp.json();
    process.stdout.write(JSON.stringify(data) + '\n');
  } catch (err) {
    process.stdout.write(JSON.stringify({
      jsonrpc: '2.0',
      id: parsed?.id ?? null,
      error: { code: -32603, message: `Ad-o-matic MCP network error: ${err.message}` }
    }) + '\n');
  }
}

let queue = Promise.resolve();
rl.on('line', (line) => {
  queue = queue.then(() => processLine(line)).catch(() => {});
});
