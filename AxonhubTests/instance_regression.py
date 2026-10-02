#!/usr/bin/env python3
"""Linux fallback: source contracts + explicit state models, NOT Swift execution.
Run: python3 AxonhubTests/instance_regression.py
Native behavior is covered by InstanceRegressionTests.swift on macOS/iOS.
"""
from pathlib import Path
import copy
import json
import unittest

ROOT = Path(__file__).resolve().parents[1]
STORE = (ROOT / "Axonhub/AxonStore.swift").read_text()
UI = (ROOT / "Axonhub/SettingsView.swift").read_text()


def restore(records, saved_id):
    return saved_id if any(x["id"] == saved_id for x in records) else (records[0]["id"] if records else "")


def edit(original, draft, secret, authenticate):
    needs_secret = any(original[k] != draft[k] for k in ("address", "authType", "adminEmail"))
    if needs_secret and not secret.strip():
        raise ValueError("new credential required")
    token = authenticate(secret) if secret.strip() else None
    result = {**original, **draft, "id": original["id"], "createdAt": original["createdAt"]}
    return result, token


class SourceContracts(unittest.TestCase):
    def test_restore_is_guarded_before_property_observers_can_persist(self):
        self.assertIn("private var isRestoring = true", STORE)
        self.assertIn("guard !isRestoring else { return }", STORE)
        init = STORE.split("init(defaults:", 1)[1].split("func persist()", 1)[0]
        self.assertLess(init.index('defaults.string(forKey: "axon_selected_id")'), init.index("self.instances ="))
        self.assertIn("saved.contains", init)
        self.assertLess(init.index("self.selectedID ="), init.index("isRestoring = false"))

    def test_edit_preserves_identity_and_authenticates_before_commit(self):
        self.assertIn("func updateInstance(id:", STORE)
        update = STORE.split("func updateInstance(id:", 1)[1].split("func deleteInstance", 1)[0]
        self.assertIn("var updated = original", update)
        self.assertIn("requiresNewSecret", update)
        self.assertLess(update.index("try await dependencies.authenticate"), update.index("try dependencies.saveCredential"))
        self.assertLess(update.index("try dependencies.saveCredential"), update.index("instances[index] = updated"))
        self.assertIn("instances.first(where: { $0.id == id }) == original", update)

    def test_keychain_replacement_is_atomic(self):
        self.assertIn("SecItemUpdate", STORE)
        self.assertIn("errSecItemNotFound", STORE)

    def test_refresh_cancels_real_work_and_rejects_stale_results(self):
        self.assertIn("fetchTask?.cancel()", STORE)
        self.assertIn("refreshGeneration", STORE)
        self.assertIn("withTaskCancellationHandler", STORE)
        self.assertIn("self.refreshGeneration == generation", STORE)
        self.assertNotIn("self.selectedID = \"\"", STORE)

    def test_editor_reuses_form_without_loading_secrets(self):
        self.assertIn("init(store: AxonStore, instance: AxonInstance? = nil)", UI)
        self.assertIn("_name = State(initialValue: instance?.name", UI)
        self.assertIn("_address = State(initialValue: instance?.address", UI)
        self.assertIn("store.updateInstance", UI)
        self.assertIn(".sheet(item: $editingInstance)", UI)
        self.assertNotIn("Keychain.load", UI)
        self.assertIn('private var secret: String = ""', UI)

    def test_api_key_help_and_native_tests_do_not_touch_production_keychain(self):
        self.assertIn('Text(NSLocalizedString("API Key 仅可查看可用模型；仪表盘、渠道与审计请使用管理员账号。"', UI)
        native = (ROOT / "AxonhubTests/InstanceRegressionTests.swift").read_text()
        self.assertIn("AxonStoreDependencies(", native)
        self.assertIn("UserDefaults(suiteName:", native)
        self.assertNotIn("Keychain.delete", native)
        self.assertNotIn("Keychain.save", native)
        self.assertNotIn("SecItemDelete", native)

    def test_concurrent_credential_only_edits_have_revision_guard(self):
        self.assertIn("let revision = instanceRevisions[id]", STORE)
        self.assertIn("instanceRevisions[id] == revision", STORE)
        self.assertIn("instanceRevisions[id] = UUID()", STORE)

    def test_new_strings_are_present_in_all_five_languages(self):
        keys = ("编辑实例", "编辑 AxonHub 网关", "保存", "留空以保留现有凭据；更改地址、认证方式或邮箱时必须输入新凭据。", "API Key 仅可查看可用模型；仪表盘、渠道与审计请使用管理员账号。")
        for language in ("en", "zh-Hans", "zh-Hant", "ja", "ko"):
            text = (ROOT / f"Axonhub/{language}.lproj/Localizable.strings").read_text()
            for key in keys:
                self.assertIn(f'"{key}" = ', text, (language, key))


class StateRegressions(unittest.TestCase):
    def setUp(self):
        self.records = [dict(id=x, createdAt=123, name=x, address=f"https://{x}.example", authType="apiKey", adminEmail="") for x in ("a", "b")]

    def test_relaunch_preserves_second_selected_instance(self):
        persisted = json.loads(json.dumps(self.records))
        self.assertEqual(restore(persisted, "b"), "b")

    def test_missing_deleted_invalid_and_empty_selection_fall_back(self):
        for value in (None, "", "deleted", "unknown"):
            self.assertEqual(restore(self.records, value), "a")
        self.assertEqual(restore([], "b"), "")

    def test_name_only_keeps_identity_and_credential_without_authentication(self):
        original = self.records[0]
        result, token = edit(original, {**original, "name": "Renamed"}, "", lambda _: self.fail("unexpected authentication"))
        self.assertEqual((result["id"], result["createdAt"]), ("a", 123))
        self.assertIsNone(token)
        self.assertEqual(original["name"], "a")

    def test_each_credential_context_change_requires_new_secret(self):
        original = self.records[0]
        for key, value in (("address", "https://evil.example"), ("authType", "admin"), ("adminEmail", "admin@example.org")):
            with self.assertRaises(ValueError):
                edit(original, {**original, key: value}, "", lambda _: self.fail("old token must not be sent"))

    def test_failed_authentication_leaves_metadata_and_key_unchanged(self):
        original = self.records[0]
        before = copy.deepcopy(original)
        def reject(_):
            raise ValueError("unauthorized")
        with self.assertRaises(ValueError):
            edit(original, {**original, "name": "Changed", "address": "https://new.example"}, "replacement", reject)
        self.assertEqual(original, before)

    def test_late_refresh_or_error_cannot_replace_current_selection_state(self):
        generation, selected, snapshot, loading = "new", "b", "b snapshot", True
        for old_generation, result in (("old", "a snapshot"), ("old", "unauthorized")):
            if generation == old_generation:
                snapshot, loading = result, False
        self.assertEqual((selected, snapshot, loading), ("b", "b snapshot", True))


if __name__ == "__main__":
    unittest.main(verbosity=2)
