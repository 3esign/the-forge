#!/usr/bin/env node
'use strict';
// Runs forge/cast with the agent key loaded from data/keys/agenti/<addr>.json into env.
// The key never touches stdout, logs or git. Usage:
//   node script/run.cjs deploy            -> Deploy.s.sol on base_sepolia, broadcast
//   node script/run.cjs probe <forgeAddr> -> Probe.s.sol against a deployed TheForge
//   node script/run.cjs cast <args...>    -> cast with --private-key injected
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const SVEMIR = process.env.SVEMIR_ROOT || 'C:/Svemir';
const KEY_ADDR = process.env.FORGE_SIGNER || '0xa71571929d95fbe3a0a1d6f97a355257d9cbfd8d'; // base-sepolia agent key
const RPC = process.env.BASE_SEPOLIA_RPC_URL || 'https://sepolia.base.org';

const keyFile = path.join(SVEMIR, 'data', 'keys', 'agenti', KEY_ADDR.toLowerCase() + '.json');
const k = JSON.parse(fs.readFileSync(keyFile, 'utf8'));
const pk = k.kljuc.startsWith('0x') ? k.kljuc : '0x' + k.kljuc;

const env = Object.assign({}, process.env, {
  PRIVATE_KEY: pk,
  BASE_SEPOLIA_RPC_URL: RPC,
  TREASURY: process.env.TREASURY || k.adresa,
  SECONDARY_TREASURY: process.env.SECONDARY_TREASURY || k.adresa,
  PATH: path.join(SVEMIR, 'tools', 'foundry') + path.delimiter + process.env.PATH,
});

const [mode, ...rest] = process.argv.slice(2);
let cmd, args;
if (mode === 'deploy') {
  cmd = 'forge';
  args = ['script', 'script/Deploy.s.sol', '--rpc-url', RPC, '--broadcast', '--slow', ...rest];
} else if (mode === 'probe') {
  env.FORGE = rest[0];
  cmd = 'forge';
  args = ['script', 'script/Probe.s.sol', '--rpc-url', RPC, '--broadcast', '--slow', ...rest.slice(1)];
} else if (mode === 'cast') {
  cmd = 'cast';
  args = [...rest, '--rpc-url', RPC, '--private-key', pk];
} else {
  console.error('usage: run.cjs deploy | probe <addr> | cast <args>');
  process.exit(2);
}
console.log('signer:', k.adresa, '| treasury:', env.TREASURY, '| rpc:', RPC);
const r = spawnSync(cmd, args, { cwd: ROOT, env, stdio: 'inherit', shell: process.platform === 'win32' });
process.exit(r.status == null ? 1 : r.status);
