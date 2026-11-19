#!/usr/bin/env python3
"""Exercise the hook using native defaults against temporary plist fixtures.

The process check is stubbed; these tests do not launch/quit FluidVoice or prove
how the app's UI interprets preferences. No real app preferences are accessed.
"""
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent
HOOK = ROOT / 'run_onchange_after_apply-fluidvoice-settings.sh.tmpl'


class FluidVoiceSettingsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='fluidvoice-settings-test-', dir='/private/tmp')
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)
        self.config = self.path / 'chezmoi.json'
        self.config.write_text('{}\n')
        self.domain = self.path / 'preferences'
        self.bin = self.path / 'bin'
        self.bin.mkdir()
        scripts = {
            'pgrep': '#!/bin/sh\nexit "$PROCESS_STATUS"\n',
            'defaults': '''#!/bin/sh
set -eu
[ "$#" -eq 5 ]
[ "$1" = write ]
[ "$2" = com.FluidApp.app ]
exec /usr/bin/defaults write "$FIXTURE_DOMAIN" "$3" "$4" "$5"
''',
        }
        for name, text in scripts.items():
            p = self.bin / name
            p.write_text(text)
            p.chmod(0o755)
        self.env = dict(os.environ, PATH=f'{self.bin}:/usr/bin:/bin',
                        FIXTURE_DOMAIN=str(self.domain), PROCESS_STATUS='1')

    def render(self, filename, system='darwin'):
        return subprocess.check_output([
            'chezmoi', '-c', str(self.config), '-S', str(ROOT),
            'execute-template', '--override-data', json.dumps({'chezmoi': {'os': system}}),
            '-f', str(filename),
        ], text=True)

    def apply(self, status='1'):
        return subprocess.run(['/bin/sh'], input=self.render(HOOK), text=True,
                              env=dict(self.env, PROCESS_STATUS=status), capture_output=True)

    def read(self):
        result = subprocess.check_output(['/usr/bin/defaults', 'export', str(self.domain), '-'])
        return plistlib.loads(result)

    def test_native_types_preservation_and_repeat_apply(self):
        private = {
            'SavedProviders': b'[{"apiKey":"PRIVATE_SENTINEL","baseURL":"https://private.invalid"}]',
            'CommandModeChatSessions': b'private conversation',
            'CustomDictionaryEntries': b'private dictionary',
            'DictationPromptConfigurations': b'private prompt',
            'PreferredInputDeviceUID': 'LOCAL_DEVICE_SENTINEL',
            'AnalyticsAnonymousInstallID': 'LOCAL_ANALYTICS_SENTINEL',
            'LocalAPIEnabled': True,
            'LaunchAtStartup': True,
            'UnrecognizedFutureSetting': {'keep': ['unchanged']},
        }
        subprocess.run(['/usr/bin/defaults', 'import', str(self.domain), '-'],
                       input=plistlib.dumps(dict(private, ShareAnonymousAnalytics=True)), check=True,
                       capture_output=True)
        result = self.apply()
        self.assertEqual(result.returncode, 0, result.stderr)
        prefs = self.read()
        for key, value in private.items():
            self.assertEqual(prefs[key], value, key)
        expected = {
            'AccentColorOption': 'Blue', 'DictationPromptOff': False,
            'DictationScreenContextEnabled': True, 'EditModeReadsScreen': False,
            'EnableDebugLogs': False, 'FileTranscriptionSpeakerLabelsEnabled': True,
            'MeetingAudioRetentionPolicy': 'days7', 'OverlayBottomOffset': 50.0,
            'PrivateAIProviderContextTokenLimit': 4096, 'PromptModeShortcutEnabled': False,
            'ReturnDictationToStartingField': True, 'SaveAudioWithTranscriptionHistory': False,
            'SecondaryDictationPromptOff': True, 'SelectedSpeechModel': 'fluid-parakeet-pro',
            'ShareAnonymousAnalytics': False, 'TextInsertionMode': 'reliablePaste',
        }
        for key, value in expected.items():
            self.assertEqual(prefs[key], value, key)
            self.assertIs(type(prefs[key]), type(value), key)
        shortcut = {'kind': 'keyboard', 'keyCode': 38, 'modifierFlagsRawValue': 1179658}
        self.assertIsInstance(prefs['HotkeyShortcutKey'], bytes)
        self.assertEqual(json.loads(prefs['HotkeyShortcutKey']), shortcut)
        self.assertEqual(json.loads(prefs['PrimaryDictationShortcuts']), [shortcut])
        self.assertEqual(set(prefs), set(private) | set(expected) |
                         {'HotkeyShortcutKey', 'PrimaryDictationShortcuts'})
        result = self.apply()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.read(), prefs)

    def test_first_install(self):
        result = self.apply()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.read()['ShareAnonymousAnalytics'])

    def test_running_app_refuses_all_writes(self):
        result = self.apply('0')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('FluidVoice is running', result.stderr)
        self.assertFalse(self.domain.with_suffix('.plist').exists())

    def test_process_check_error_refuses_all_writes(self):
        result = self.apply('2')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Cannot check', result.stderr)
        self.assertFalse(self.domain.with_suffix('.plist').exists())

    def test_linux_has_no_hook_or_casks(self):
        self.assertEqual(self.render(HOOK, 'linux').strip(), '')
        brewfile = self.render(ROOT / '.chezmoitemplates/Brewfile', 'linux')
        self.assertNotIn('cask ', brewfile)
        self.assertNotIn('fluidvoice', brewfile)

    def test_macos_installs_fluidvoice(self):
        brewfile = self.render(ROOT / '.chezmoitemplates/Brewfile')
        self.assertEqual(brewfile.count('cask "fluidvoice"'), 1)


if __name__ == '__main__':
    unittest.main(verbosity=2)
