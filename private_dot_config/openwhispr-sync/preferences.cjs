#!/usr/bin/env node
// OpenWhispr 1.11: curated Chromium localStorage, never credentials or history.
'use strict';
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const cp = require('node:child_process');
const { ClassicLevel } = require('classic-level');
const DEFAULT_DIR = path.join(os.homedir(), 'Library/Application Support/open-whispr');
const DEFAULTS = Object.freeze({
  uiLanguage: 'en', theme: 'auto',
  transcriptionMode: 'providers', cloudTranscriptionMode: 'byok',
  cloudTranscriptionProvider: 'openai', cloudTranscriptionModel: 'gpt-transcribe',
  useLocalWhisper: false, preferredLanguage: 'auto', spokenLanguages: ['fr', 'en'],
  useCleanupModel: false, useDictationAgent: false,
  dictationKey: 'Command+Shift+J', activationMode: 'tap',
  voiceAgentKey: '', translationKey: '', meetingKey: '',
  floatingIconAutoHide: false, panelStartPosition: 'center', startMinimized: false,
  microphoneSelectionMode: 'system', preferBuiltInMic: false, selectedMicDeviceLabel: '',
  micWarmHoldSeconds: 0, audioCuesEnabled: true, pauseMediaOnDictation: false,
  autoPasteEnabled: true, keepTranscriptionInClipboard: false,
  showTranscriptionPreview: false, autoLearnCorrections: true,
  notificationsEnabled: true, notifyMeetingDetection: true, notifyCalendarReminders: true,
  autoUpdatesEnabled: true, cloudBackupEnabled: false, insightsSyncEnabled: false,
  telemetryEnabled: false, dataRetentionEnabled: true, audioRetentionDays: 30,
  transcriptRetentionDays: 0, saveDiscardedTranscriptions: false,
});
const ENUMS = {
  theme: ['light', 'dark', 'auto'], activationMode: ['tap', 'push'],
  panelStartPosition: ['bottom-right', 'center', 'bottom-left'],
  microphoneSelectionMode: ['system', 'built-in', 'specific'],
  transcriptionMode: ['providers', 'local', 'openwhispr', 'self-hosted'],
  cloudTranscriptionMode: ['byok', 'openwhispr'],
};
const ENV_KEYS = {
  uiLanguage: 'UI_LANGUAGE', dictationKey: 'DICTATION_KEY',
  activationMode: 'ACTIVATION_MODE', voiceAgentKey: 'VOICE_AGENT_KEY',
  translationKey: 'TRANSLATION_KEY', meetingKey: 'MEETING_KEY',
  floatingIconAutoHide: 'FLOATING_ICON_AUTO_HIDE', panelStartPosition: 'PANEL_START_POSITION',
  startMinimized: 'START_MINIMIZED',
};
const key = name => Buffer.from('_file://\0\x01' + name, 'latin1');
const encode = text => /^[\x00-\xff]*$/.test(text)
  ? Buffer.concat([Buffer.from([1]), Buffer.from(text, 'latin1')])
  : Buffer.concat([Buffer.from([0]), Buffer.from(text, 'utf16le')]);
const decode = value => {
  if (value[0] !== 0 && value[0] !== 1) throw new Error('Unknown localStorage encoding');
  return value.subarray(1).toString(value[0] ? 'latin1' : 'utf16le');
};
const serialize = value => typeof value === 'string' ? value : JSON.stringify(value);
function validate(document) {
  if (!document || document.schemaVersion !== 1 || !document.preferences ||
      Object.keys(document).some(k => !['schemaVersion', 'preferences'].includes(k)))
    throw new Error('Unsupported preference snapshot');
  for (const [name, value] of Object.entries(document.preferences)) {
    if (!Object.hasOwn(DEFAULTS, name)) throw new Error('Unapproved preference field: ' + name);
    const sample = DEFAULTS[name];
    if (Array.isArray(sample)) {
      if (!Array.isArray(value) || value.some(v => typeof v !== 'string' || !/^[a-z]{2,3}(-[A-Za-z0-9]+)*$/.test(v)))
        throw new Error('Invalid language list');
    } else if (typeof value !== typeof sample) throw new Error('Invalid preference type: ' + name);
    if (typeof value === 'string' && (value.length > 200 || /[\r\n\0]|sk-[A-Za-z0-9_-]{8,}|bearer\s/i.test(value)))
      throw new Error('Unsafe preference value: ' + name);
    if (typeof value === 'number' && (!Number.isSafeInteger(value) || value < 0))
      throw new Error('Invalid preference number: ' + name);
    if (ENUMS[name] && !ENUMS[name].includes(value)) throw new Error('Invalid preference choice: ' + name);
  }
  return document.preferences;
}
function assertClosed(dataDir) {
  if (path.resolve(dataDir) !== DEFAULT_DIR) return; // Isolated fixture data is safe to test.
  const result = cp.spawnSync('/usr/bin/pgrep', ['-x', 'OpenWhispr'], { stdio: 'ignore' });
  if (result.status === 0) throw new Error('Quit OpenWhispr, then rerun chezmoi apply or openwhispr-prefs capture.');
  if (result.status !== 1) throw new Error('Could not check whether OpenWhispr is running.');
}
async function read(db, name) {
  const value = await db.get(key(name));
  return value === undefined ? undefined : decode(value);
}
function parse(name, raw) {
  if (typeof DEFAULTS[name] === 'string') return raw;
  return JSON.parse(raw);
}
function atomicWrite(file, contents) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temp = file + '.tmp-' + process.pid;
  try {
    fs.writeFileSync(temp, contents, { mode: 0o600, flag: 'wx' });
    fs.renameSync(temp, file);
  } finally { fs.rmSync(temp, { force: true }); }
}
function mergeEnv(current, preferences) {
  const updates = new Map(Object.entries(ENV_KEYS)
    .filter(([name]) => Object.hasOwn(preferences, name))
    .map(([name, env]) => [env, String(preferences[name])]));
  // A legacy assistant shortcut would otherwise resurrect the cleared slot.
  if (Object.hasOwn(preferences, 'voiceAgentKey')) updates.set('CHAT_AGENT_KEY', '');
  const lines = current.split('\n').filter(line => !updates.has(line.split('=', 1)[0].trim()));
  while (lines.length && lines.at(-1) === '') lines.pop();
  for (const [env, value] of updates) if (value) lines.push(env + '=' + value);
  return lines.join('\n') + '\n';
}
async function run(mode, configFile, dataDir = DEFAULT_DIR) {
  if (!['apply', 'capture', 'check'].includes(mode)) throw new Error('Use apply, capture, or check.');
  assertClosed(dataDir);
  const dbDir = path.join(dataDir, 'Local Storage/leveldb');
  if (!fs.existsSync(path.join(dbDir, 'CURRENT')))
    throw new Error('OpenWhispr preferences do not exist yet. Launch and quit the app first.');
  const preferences = mode === 'capture' ? null : validate(JSON.parse(fs.readFileSync(configFile, 'utf8')));
  // Back up before opening LevelDB: opening can rotate its log files.
  let backup;
  if (mode === 'apply') {
    backup = path.join(dataDir, 'chezmoi-backups', new Date().toISOString().replace(/[:.]/g, '-') + '-' + process.pid);
    fs.mkdirSync(backup, { recursive: true, mode: 0o700 });
    if (fs.existsSync(dbDir)) fs.cpSync(dbDir, path.join(backup, 'leveldb'), { recursive: true });
    const env = path.join(dataDir, '.env');
    if (fs.existsSync(env)) fs.copyFileSync(env, path.join(backup, '.env'));
  }
  const db = new ClassicLevel(dbDir, { keyEncoding: 'buffer', valueEncoding: 'buffer', createIfMissing: mode === 'apply' });
  try {
    await db.open();
    if (mode === 'capture') {
      const captured = {};
      for (const [name, fallback] of Object.entries(DEFAULTS)) {
        const raw = await read(db, name);
        captured[name] = raw === undefined ? fallback : parse(name, raw);
      }
      // Main-process preferences take precedence on startup. Read only named public fields.
      const envFile = path.join(dataDir, '.env');
      if (fs.existsSync(envFile)) {
        const env = new Map(fs.readFileSync(envFile, 'utf8').split('\n').map(line => {
          const index = line.indexOf('='); return [line.slice(0, index).trim(), line.slice(index + 1).trim()];
        }));
        for (const [name, envName] of Object.entries(ENV_KEYS))
          if (env.has(envName)) captured[name] = parse(name, env.get(envName));
      }
      const document = { schemaVersion: 1, preferences: captured };
      validate(document);
      atomicWrite(configFile, JSON.stringify(document, null, 2) + '\n');
      console.log('Captured approved preferences only. Credentials, device IDs, history, and private text were excluded.');
      return;
    }
    const desired = { ...preferences };
    if (preferences.microphoneSelectionMode === 'specific' && preferences.selectedMicDeviceLabel) {
      const label = await read(db, 'selectedMicDeviceLabel');
      const id = await read(db, 'selectedMicDeviceId');
      // Chromium IDs differ per Mac. A nonempty placeholder lets OpenWhispr's
      // own unique-label recovery resolve the physical device on that Mac.
      if (label !== preferences.selectedMicDeviceLabel || !id)
        desired.selectedMicDeviceId = 'chezmoi-resolve-by-label';
    }
    const changes = [];
    for (const [name, value] of Object.entries(desired)) {
      const text = serialize(value);
      if (await read(db, name) !== text) changes.push({ type: 'put', key: key(name), value: encode(text) });
    }
    const envPath = path.join(dataDir, '.env');
    const oldEnv = fs.existsSync(envPath) ? fs.readFileSync(envPath, 'utf8') : '';
    const nextEnv = mergeEnv(oldEnv, preferences);
    if (mode === 'check') {
      if (changes.length || oldEnv !== nextEnv) throw new Error('Saved preferences differ from the curated snapshot.');
      console.log('Saved preferences match; local credentials and other app state are untouched.');
      return;
    }
    if (changes.length) await db.batch(changes, { sync: true });
    if (oldEnv !== nextEnv) atomicWrite(envPath, nextEnv);
    if (!changes.length && oldEnv === nextEnv) fs.rmSync(backup, { recursive: true, force: true });
    console.log('Applied approved OpenWhispr preferences. API keys and local app state were preserved.');
  } finally { await db.close(); }
}
module.exports = { run, validate, mergeEnv, key, encode, decode, DEFAULTS };
if (require.main === module) {
  const [mode, config, dataDir] = process.argv.slice(2);
  if (!config) { console.error('Usage: preferences.cjs apply|capture|check PREFERENCES.json [DATA_DIR]'); process.exitCode = 1; }
  else run(mode, config, dataDir).catch(() => {
    // Database errors may contain private paths or state; never dump raw errors.
    console.error('OpenWhispr preference operation failed. Quit OpenWhispr; check the snapshot format, dependencies, and file permissions.');
    process.exitCode = 1;
  });
}
