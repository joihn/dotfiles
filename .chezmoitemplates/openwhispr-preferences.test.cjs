'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { ClassicLevel } = require('classic-level');
const { run, validate, key, encode, decode } = require('../private_dot_config/openwhispr-sync/preferences.cjs');
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'openwhispr-prefs-test-'));
async function withDb(dir, fn) {
  const db = new ClassicLevel(path.join(dir, 'Local Storage/leveldb'), { keyEncoding: 'buffer', valueEncoding: 'buffer' });
  await db.open(); try { await fn(db); } finally { await db.close(); }
}
(async () => {
  const dir = path.join(root, 'mac-a');
  fs.mkdirSync(dir, { recursive: true });
  const opaqueSecret = 'local-only-placeholder';
  await withDb(dir, async db => db.batch([
    { type: 'put', key: key('openaiApiKey'), value: encode(opaqueSecret) },
    { type: 'put', key: key('selectedMicDeviceId'), value: encode('machine-a-only-id') },
    { type: 'put', key: key('selectedMicDeviceLabel'), value: encode('BOYA CM40 (37d3:0035)') },
    { type: 'put', key: key('microphoneSelectionMode'), value: encode('specific') },
    { type: 'put', key: key('privateTranscript'), value: encode('private fixture text') },
    { type: 'put', key: key('telemetryEnabled'), value: encode('true') },
  ]));
  fs.mkdirSync(path.join(dir, 'secure-keys'));
  fs.writeFileSync(path.join(dir, 'secure-keys/OPENAI_API_KEY.enc'), opaqueSecret);
  fs.writeFileSync(path.join(dir, 'transcriptions.db'), 'fixture history');
  fs.writeFileSync(path.join(dir, '.env'), 'OPENAI_API_KEY='+opaqueSecret+'\nCUSTOM_OTHER=keep\nDICTATION_KEY=F8\nCHAT_AGENT_KEY=F9\n');
  const file = path.join(root, 'preferences.json');
  await run('capture', file, dir);
  const captured = JSON.parse(fs.readFileSync(file));
  assert(!fs.readFileSync(file, 'utf8').includes(opaqueSecret));
  assert(!Object.hasOwn(captured.preferences, 'selectedMicDeviceId'));
  assert(!Object.hasOwn(captured.preferences, 'privateTranscript'));
  captured.preferences.telemetryEnabled = false;
  captured.preferences.dictationKey = 'Command+Shift+J';
  fs.writeFileSync(file, JSON.stringify(captured));
  await run('apply', file, dir);
  await run('check', file, dir);
  await withDb(dir, async db => {
    assert.equal(decode(await db.get(key('openaiApiKey'))), opaqueSecret);
    assert.equal(decode(await db.get(key('privateTranscript'))), 'private fixture text');
    assert.equal(decode(await db.get(key('selectedMicDeviceId'))), 'machine-a-only-id');
    assert.equal(decode(await db.get(key('telemetryEnabled'))), 'false');
  });
  assert.equal(fs.readFileSync(path.join(dir, 'secure-keys/OPENAI_API_KEY.enc'), 'utf8'), opaqueSecret);
  assert.equal(fs.readFileSync(path.join(dir, 'transcriptions.db'), 'utf8'), 'fixture history');
  const env = fs.readFileSync(path.join(dir, '.env'), 'utf8');
  assert(env.includes('OPENAI_API_KEY='+opaqueSecret));
  assert(env.includes('CUSTOM_OTHER=keep'));
  assert(!env.includes('CHAT_AGENT_KEY='));
  const envTime = fs.statSync(path.join(dir, '.env')).mtimeMs;
  const backupCount = fs.readdirSync(path.join(dir, 'chezmoi-backups')).length;
  await run('apply', file, dir);
  assert.equal(fs.statSync(path.join(dir, '.env')).mtimeMs, envTime);
  assert.equal(fs.readdirSync(path.join(dir, 'chezmoi-backups')).length, backupCount);
  const second = path.join(root, 'mac-b');
  await withDb(second, async db => db.put(key('selectedMicDeviceId'), encode('unrelated-mac-b-device')));
  await run('apply', file, second);
  await withDb(second, async db => {
    assert.equal(decode(await db.get(key('selectedMicDeviceId'))), 'chezmoi-resolve-by-label');
    assert.equal(decode(await db.get(key('selectedMicDeviceLabel'))), 'BOYA CM40 (37d3:0035)');
  });
  await assert.rejects(run('apply', file, path.join(root, 'never-launched')));
  assert.throws(() => validate({schemaVersion:1,preferences:{openaiApiKey:'anything'}}));
  assert.throws(() => validate({schemaVersion:1,preferences:{dictationKey:'sk-'+'x'.repeat(30)}}));
  assert.equal(decode(encode('Microphone français 🎙')), 'Microphone français 🎙');
  console.log('PASS: whitelist capture, secret/history preservation, idempotence, env merging, fresh-install guard, microphone remapping, secret rejection, Unicode.');
})().finally(() => fs.rmSync(root, { recursive: true, force: true })).catch(e => { console.error(e); process.exitCode=1; });
