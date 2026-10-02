#!/usr/bin/env python3
"""Editor regression guards and real production Swift checks, without a simulator."""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class EditorRegression(unittest.TestCase):
    def test_channel_read_is_inline_and_not_a_confirmation_popover(self):
        source = (ROOT / 'Axonhub/ManagementEditor.swift').read_text()
        self.assertNotIn('authorizeSecrets', source)
        self.assertNotIn('.confirmationDialog', source)
        self.assertIn('await loadSecrets()', source)
        self.assertIn('channel.credentials["apiKeys"]', source)
        # Clear the editor only when its entire NavigationStack closes, not when
        # pushing a credential/settings field onto that stack.
        self.assertRegex(source, r'\n        \}\n        \.onDisappear \{ clearSecrets\(\) \}')

    def test_model_and_channel_text_fields_have_persistent_labels(self):
        source = (ROOT / 'Axonhub/ManagementEditor.swift').read_text()
        for field in ['name', 'modelID', 'developer', 'group', 'icon', 'remark']:
            self.assertRegex(source, r'LabeledEditorField\([^\n]*\$model\.' + field + r'\b')
        self.assertIn('Text(title)', source)
        self.assertIn('.accessibilityLabel(title)', source)

    def test_api_key_reads_have_no_second_confirmation(self):
        native = (ROOT / 'Axonhub/NativeManagement.swift').read_text()
        detail = native.split('struct NativeEntityDetailView: View {')[1].split('struct NativeEntityEditor: View {')[0]
        self.assertNotIn('isPresented: $reveal', detail)
        self.assertIn('revealSecret()', detail)
        self.assertIn('revealed["id"].string == id', detail)
        legacy = (ROOT / 'Axonhub/AdminCenter.swift').read_text().split('private struct AdminDetailView: View {')[1].split('struct AdminResultTree: View {')[0]
        self.assertNotIn('revealConfirmation', legacy)
        self.assertIn('revealSecret()', legacy)
        self.assertIn('.onDisappear', detail)
        self.assertIn('NativeSecretClipboard.copy(secret)', detail)

    def test_all_number_displays_use_explicit_precision(self):
        for file in (ROOT / 'Axonhub').glob('*.swift'):
            source = file.read_text()
            self.assertNotIn('.formatted()', source, file.name)
            for precision in re.findall(r'fractionLength\(([^)]+)\)', source):
                digits = re.findall(r'\d+', precision)
                self.assertTrue(all(int(n) <= 2 for n in digits), (file.name, precision))
        scalar = (ROOT / 'Axonhub/NativeSystemSettings.swift').read_text()
        self.assertIn('DisplayFormat.number(number)', scalar)
        self.assertIn('DisplayFormat.isDecimalQuantity(key)', scalar)

    def test_no_automatic_simulator_action(self):
        screenshots = (ROOT / '.github/workflows/screenshots.yml').read_text()
        self.assertNotIn('  push:', screenshots)
        build = (ROOT / '.github/workflows/build.yml').read_text()
        self.assertNotIn('simctl', build)
        self.assertNotIn('xcodebuild test', build)
        self.assertIn("generic/platform=iOS", build)


def swift_checks():
    core = (ROOT / 'Axonhub/Core.swift').read_text()
    core = core[core.index('indirect enum JSON:'):core.index('/// Safe user-facing errors')]
    management = (ROOT / 'Axonhub/Management.swift').read_text().split('extension AxonClient {')[0]
    advanced = (ROOT / 'Axonhub/ChannelAdvancedInputs.swift').read_text().split('/// Lazy navigation')[0].replace('import SwiftUI', '')
    semantics = (ROOT / 'Axonhub/ChannelSemantics.swift').read_text()
    defaults = (ROOT / 'Axonhub/ChannelDefaults.swift').read_text()
    formatting = (ROOT / 'Axonhub/DisplayFormat.swift').read_text()
    tests = r'''
func check(_ condition: @autoclosure () throws -> Bool, _ name: String) rethrows {
    let result = try condition()
    precondition(result, name)
    print("PASS: " + name)
}
let locale = Locale(identifier: "en_US_POSIX")
check(DisplayFormat.number(12.3456, locale: locale) == "12.35", "round to two places")
check(DisplayFormat.number(12.3, locale: locale) == "12.3", "no unnecessary trailing zero")
check(DisplayFormat.number(12, locale: locale) == "12", "integer remains integer")
check(DisplayFormat.number(0.00001, locale: locale) == "0", "small cost rounds to zero")
check(DisplayFormat.number(-12.3456, locale: locale) == "-12.35", "negative rounding")
check(DisplayFormat.number(.infinity, locale: locale) == "—", "nonfinite remains unknown")
check(DisplayFormat.number("123456789012345.6789", locale: locale)?.replacingOccurrences(of: ",", with: "") == "123456789012345.68", "decimal string keeps exact precision")
check(DisplayFormat.number("not-a-number", locale: locale) == nil, "non-numeric string is not changed")
check(DisplayFormat.number("12.345 text", locale: locale) == nil, "numeric prefix is not treated as a quantity")
for key in ["cost", "totalCost", "pricePerUnit", "subtotal", "cacheRead", "avgTokensPerSecond", "usagePerUnit"] {
    check(DisplayFormat.isDecimalQuantity(key), "decimal field " + key)
}
for key in ["id", "apiKey", "modelID", "accessToken", "name", "content", "input", "output", "costPriceReferenceID"] {
    check(!DisplayFormat.isDecimalQuantity(key), "opaque field " + key)
}
let detail = JSON.from(#"{"id":"channel-1","name":"Original","type":"openai","supportedModels":["chat"],"defaultTestModel":"chat","orderingWeight":0,"updatedAt":"2026-10-02T08:07:36Z","policies":{"stream":"unlimited"}}"#)!
let secret = JSON.from(#"{"id":"channel-1","updatedAt":"2026-10-02T08:07:36Z","credentials":{"apiKey":"","apiKeys":["fixture-a","fixture-b"],"oauth":null},"settings":{"proxy":{"type":"URL","url":"http://proxy.example:8080","password":"fixture-password"},"rateLimit":{"rpm":20}}}"#)!
var draft = ChannelDraft(detail: detail)
draft.loadSecrets(secret)
check(draft.secretsLoaded, "read enables auth and advanced configuration")
check(draft.credentials["apiKeys"].array.count == 2, "official apiKeys array is retained")
check(draft.settings["proxy"]["password"].string == "fixture-password", "protected advanced values loaded")
try check(draft.payload().isEmpty, "reading alone never changes server credentials or settings")
var credentials = draft.credentials.object
credentials["apiKeys"] = .array([.string("fixture-new"), .string("fixture-b")])
draft.credentials = .object(credentials)
let updated = try draft.payload()
check(updated["credentials"]?["apiKeys"].array.first == .string("fixture-new"), "editing existing array writes edited key")
check(updated["settings"] == nil, "credential edit never overwrites settings")
var settingsDraft = ChannelDraft(detail: detail)
settingsDraft.loadSecrets(secret)
var settings = settingsDraft.settings.object
settings["passThroughBody"] = .bool(true)
settingsDraft.settings = .object(settings)
let input = try settingsDraft.payload()
check(input["credentials"] == nil, "advanced edit preserves authentication")
check(input["settings"]?["proxy"]["password"].string == "fixture-password", "advanced edit keeps proxy credentials")
let originalCost = JSON.number(0.123456789)
_ = DisplayFormat.number(originalCost.number, locale: locale)
check(originalCost == .number(0.123456789), "display rounding never mutates API data")
'''
    with tempfile.TemporaryDirectory(prefix='axon-editor-') as directory:
        path = Path(directory)
        (path / 'main.swift').write_text('import Foundation\nstruct AxonInstance {}\n' + core + management + advanced + semantics + defaults + formatting + tests)
        subprocess.run(['swiftc', str(path / 'main.swift'), '-o', str(path / 'editor-tests')], check=True)
        subprocess.run([str(path / 'editor-tests')], check=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--swift', action='store_true')
    args = parser.parse_args()
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(EditorRegression))
    if not result.wasSuccessful():
        raise SystemExit(1)
    if args.swift:
        swift_checks()
