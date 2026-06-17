#!/usr/bin/env node
/**
 * Zero-dependency GraphQL-over-WebSocket subscriber probe (Node 22 global WebSocket).
 *
 * Supports BOTH ws subprotocols the corridor stack uses:
 *   --protocol legacy  → "graphql-ws"            (SmartFace/VPP :8097, CIGS — connection_init→ack→start→data)
 *   --protocol modern  → "graphql-transport-ws"  (our Foundation facade — connection_init→ack→subscribe→next)
 *
 * Emits one compact JSON line per received payload to stdout (so callers can grep/jq).
 * Diagnostics go to stderr. Exits 0 after collecting --max payloads, 0 on timeout with
 * >=1 payload, 124 on timeout with 0 payloads (so a scenario can assert "something arrived").
 *
 * Usage:
 *   node gql-ws-probe.mjs --url ws://localhost:8097/graphql --protocol legacy \
 *        --query-file q.graphql [--vars '{"k":1}'] [--max 1] [--timeout 30] [--quiet]
 *   echo "<query>" | node gql-ws-probe.mjs --url ... --protocol modern --query-stdin
 */
import { readFileSync } from 'node:fs';

const args = process.argv.slice(2);
function opt(name, def = undefined) {
  const i = args.indexOf(`--${name}`);
  if (i === -1) return def;
  const v = args[i + 1];
  return v && !v.startsWith('--') ? v : true;
}
const url = opt('url');
const protocol = opt('protocol', 'modern');
const max = parseInt(opt('max', '1'), 10);
const timeoutS = parseInt(opt('timeout', '30'), 10);
const quiet = !!opt('quiet', false);
const varsRaw = opt('vars');
let query;
if (opt('query-stdin')) query = readFileSync(0, 'utf8');
else if (opt('query-file')) query = readFileSync(opt('query-file'), 'utf8');
else if (opt('query')) query = opt('query');

if (!url || !query) {
  console.error('usage: --url <ws-url> --protocol legacy|modern (--query-file f | --query-stdin | --query q) [--vars json] [--max n] [--timeout s]');
  process.exit(2);
}
const variables = varsRaw ? JSON.parse(varsRaw) : undefined;
const subprotocol = protocol === 'legacy' ? 'graphql-ws' : 'graphql-transport-ws';
const log = (...a) => { if (!quiet) console.error('[probe]', ...a); };

let received = 0;
let acked = false;
const ws = new WebSocket(url, subprotocol);

const done = (code) => { try { ws.close(); } catch {} process.exit(code); };
const timer = setTimeout(() => {
  log(`timeout after ${timeoutS}s, received=${received}`);
  done(received > 0 ? 0 : 124);
}, timeoutS * 1000);

ws.addEventListener('open', () => {
  log(`open ${url} (${subprotocol})`);
  ws.send(JSON.stringify({ type: 'connection_init', payload: {} }));
});

ws.addEventListener('error', (e) => { log('ws error', e.message || e); });
ws.addEventListener('close', (e) => { log(`closed code=${e.code} reason=${e.reason || ''}`); if (!acked) done(124); });

ws.addEventListener('message', (ev) => {
  let msg;
  try { msg = JSON.parse(ev.data); } catch { return; }
  switch (msg.type) {
    case 'connection_ack': {
      acked = true;
      const startType = protocol === 'legacy' ? 'start' : 'subscribe';
      log(`ack → ${startType}`);
      ws.send(JSON.stringify({ id: '1', type: startType, payload: { query, variables } }));
      break;
    }
    case 'data':      // legacy
    case 'next': {    // modern
      received++;
      process.stdout.write(JSON.stringify(msg.payload) + '\n');
      if (received >= max) { clearTimeout(timer); log(`collected ${received}`); done(0); }
      break;
    }
    case 'error': {
      console.error('[probe] subscription error:', JSON.stringify(msg.payload));
      done(1);
      break;
    }
    case 'complete': { log('server completed'); done(received > 0 ? 0 : 124); break; }
    case 'ka': case 'ping': { if (protocol === 'modern' && msg.type === 'ping') ws.send(JSON.stringify({ type: 'pong' })); break; }
    default: break;
  }
});
