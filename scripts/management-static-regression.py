#!/usr/bin/env python3
"""Real SDL/coercion and shipped-source static regression; NOT Swift runtime tests."""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import sys
import unittest
from graphql import parse, validate
from graphql.execution.values import get_variable_values

ROOT = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('contract', ROOT / 'scripts/check-api-contract.py')
assert spec is not None and spec.loader is not None
contract = importlib.util.module_from_spec(spec)
spec.loader.exec_module(contract)


class ContractRegression(unittest.TestCase):
    schema = None
    @classmethod
    def setUpClass(cls):
        cls.operations = contract.shipped_operations()
        cls.management = (ROOT / 'Axonhub/Management.swift').read_text()
        cls.store = (ROOT / 'Axonhub/AxonStore.swift').read_text()
        cls.editor = (ROOT / 'Axonhub/ManagementEditor.swift').read_text()

    def test_all_shipped_operations_and_variable_fixtures(self):
        fixtures = json.loads((ROOT / 'scripts/channel-model-contract-fixtures.json').read_text())
        for name, samples in fixtures.items():
            _, document, definition = self.operations[name]
            self.assertFalse(validate(self.schema, document), name)
            for sample in samples:
                self.assertNotIsInstance(get_variable_values(self.schema, definition.variable_definitions or [], sample['variables']), list, (name, sample['label']))

    def test_schema_rejects_missing_required_channel_credentials(self):
        definition = self.operations['CreateChannel'][2]
        sample = {'input': {'type': 'openai', 'name': 'broken', 'supportedModels': ['chat'], 'defaultTestModel': 'chat'}}
        values = get_variable_values(self.schema, definition.variable_definitions, sample)
        self.assertIsInstance(values, list)
        self.assertTrue(any('credentials' in error.message for error in values))

    def test_schema_rejects_old_model_type_and_empty_required_model_settings(self):
        sample = json.loads((ROOT / 'scripts/api-contract-fixtures.json').read_text())['CreateModel'][0]['variables']
        sample['input']['type'] = 'llm'
        sample['input']['settings'] = {}
        errors = get_variable_values(self.schema, self.operations['CreateModel'][2].variable_definitions, sample)
        self.assertIsInstance(errors, list)
        self.assertTrue(any('llm' in e.message for e in errors))
        self.assertTrue(any('associations' in e.message for e in errors))

    def test_schema_rejects_wrong_mutation_and_unknown_variable_fields(self):
        invalid = parse('mutation Old($id: ID!) { updateModelStatus(id: $id, status: enabled) { id } }')
        self.assertTrue(validate(self.schema, invalid))
        sample = {'id': '1', 'input': {'name': 'new', 'hiddenBogusField': True}}
        errors = get_variable_values(self.schema, self.operations['EditChannel'][2].variable_definitions, sample)
        self.assertIsInstance(errors, list)
        self.assertTrue(any('hiddenBogusField' in e.message for e in errors))

    def test_swift_enum_sets_match_exact_official_schema(self):
        for name in ['ChannelType', 'ModelType']:
            body = re.search(r'enum '+name+r':[^\{]+\{(.*?)\n\}', self.management, re.S).group(1)
            cases = set()
            for line in body.splitlines():
                if line.strip().startswith('case '):
                    cases.update(x.strip() for x in line.strip()[5:].split(','))
            self.assertEqual(cases, set(self.schema.get_type(name).values))

    def test_production_route_literal_matches_official_input_fixture(self):
        body = re.search(r'var associations: JSON \{(.*?)\n    \}', self.management, re.S).group(1)
        self.assertIn('"type": .string("model")', body)
        self.assertIn('"modelId": .object(["modelId": .string(routeModelID.trimmed)])', body)
        fixture = json.loads((ROOT / 'scripts/api-contract-fixtures.json').read_text())['CreateModel'][0]['variables']['input']['settings']['associations'][0]
        self.assertEqual(fixture['type'], 'model')
        self.assertEqual(set(fixture['modelId']), {'modelId'})

    def test_changed_only_payload_and_explicit_protected_full_settings(self):
        channel_body = self.management.split('struct ChannelDraft {')[1].split('struct ModelDraft {')[0]
        self.assertIn('p = p.filter', channel_body)
        self.assertIn('guard secretsLoaded else', channel_body)
        self.assertIn('originalCredentials', channel_body)
        self.assertIn('migrationConfirmed', channel_body)
        self.assertIn('p["settings"] = settings', channel_body)
        model_body = self.management.split('struct ModelDraft {')[1].split('extension String {')[0]
        self.assertIn('p = p.filter', model_body)
        self.assertIn('modelCard != original?', model_body)
        self.assertIn('settingsOriginal.object', model_body)
        self.assertIn('when { enabled condition', self.management)

    def test_base_url_clear_is_effective_not_ignored_flag(self):
        payload = self.management.split('struct ChannelDraft {')[1].split('struct ModelDraft {')[0]
        self.assertNotIn('p["clearBaseURL"]', payload)
        self.assertIn('"baseURL": .string(baseURL.trimmed)', payload)
        self.assertIn('baseURL != baseline.baseURL ? "baseURL" : nil', payload)
        fixtures = json.loads((ROOT/'scripts/channel-model-contract-fixtures.json').read_text())
        self.assertFalse(any('clearBaseURL' in x['variables'].get('input',{}) for x in fixtures['EditChannel']))

    def test_model_card_null_value_fields_are_rejected_before_write(self):
        card = self.management.split('static func validCard')[1].split('extension String')[0]
        self.assertIn('if value.isNull { return false }',card)
        self.assertIn('if field.isNull { return false }',card)
        self.assertIn('Self.validCard(card)', self.management)
        tests = (ROOT/'AxonhubTests/ManagementPayloadTests.swift').read_text()
        for field in ['vision','knowledge','input','reasoning','context']:
            self.assertIn('"'+field+'":null', tests)

    def test_all_input_metadata_matches_official_sdl(self):
        source = (ROOT/'Axonhub/ChannelAdvancedInputs.swift').read_text()
        section = source.split('static let fields:')[1].split('static let enums:')[0]
        for name, body in re.findall(r'"([A-Za-z0-9]+Input|BulkImportChannelItem|ChannelOrderingItem)": \[(.*)\],', section):
            fields = dict(re.findall(r'"([^"\n]+)": "([^"\n]+)"',body))
            official = self.schema.get_type(name)
            self.assertIsNotNone(official,name)
            self.assertEqual(fields, {k:str(v.type) for k,v in official.fields.items()},name)

    def test_recursion_never_returns_truncated_conditions(self):
        self.assertIn('Self.hasTruncatedCondition(node["settings"])', self.management)
        self.assertIn('expanded.replacingOccurrences(of:', self.management)
        self.assertIn('object.keys.count == 1', self.management)
        self.assertIn('throw ManagementError.invalidFields // fail closed', self.management)

    def test_snapshot_uses_exhaustive_model_pages(self):
        core=(ROOT/'Axonhub/Core.swift').read_text()
        operations=(ROOT/'Axonhub/ChannelModelOperations.swift').read_text()
        self.assertIn('snapshot.models = try await allManagedModels()',core)
        self.assertIn('models(first: 100, after: $after',operations)
        self.assertIn('result.count == page["totalCount"].int',operations)
        self.assertIn('guard case .array = page["edges"]',operations)

    def test_secret_reads_have_explicit_authorization_and_secure_ui(self):
        self.assertNotIn('credentials {', self.management.split('func channelDetail')[1].split('func modelDetail')[0])
        self.assertIn('authorizeSecrets = true',self.editor)
        self.assertIn('Read into protected fields',self.editor)
        self.assertIn('ChannelSchemaFields(value: $channel.credentials',self.editor)
        schema_ui=(ROOT/'Axonhub/ChannelAdvancedInputs.swift').read_text()
        self.assertIn('SecureField(path, text: stringBinding)',schema_ui)
        self.assertNotIn('UserDefaults',schema_ui)
        self.assertNotIn('print(',schema_ui)

    def test_native_advanced_operations_have_ui_entrypoints(self):
        sources='\n'.join((ROOT/'Axonhub'/name).read_text() for name in ['ChannelModelToolsView.swift','ChannelKeysView.swift','ChannelDetailToolsView.swift','ChannelTemplates.swift','ChannelDiagnostics.swift','ManagementEditor.swift'])
        for method in ['managedBatch','managedKeyAction','bulkCreateChannels','bulkImportChannels','bulkUpdateChannelOrdering','bulkCreateModels','providersCatalog','unassociatedChannels','saveChannelModelPrices','clearChannelError','createChannelTemplate','applyChannelTemplate','clearChannelTemplates','channelDiagnostics','channelTestHistory','resetManagedChannelQuota','managedRoutePreview']:
            self.assertIn(method,sources,method)

    def test_source_target_guards_readback_confirmation_and_uncertain_write(self):
        self.assertIn('managementRevision == target.connectionRevision', self.store)
        self.assertIn('managementRevision = UUID()', self.store)
        self.assertIn('selectedInstance == target.instance', self.store)
        self.assertIn('guard !managementBusy', self.store)
        self.assertIn('cli.channelDetail(id: id) == nil', self.store)
        self.assertIn('cli.modelDetail(id: id) == nil', self.store)
        self.assertIn('try verify(detail, input: input)', self.store)
        self.assertIn('uncertainWrite = writeStarted', self.editor)
        self.assertIn('.interactiveDismissDisabled(saving)', self.editor)
        for file in ['ChannelsView.swift', 'ModelsView.swift']:
            text = (ROOT / 'Axonhub' / file).read_text()
            self.assertIn('.confirmationDialog', text)
            self.assertNotIn('try?', text)
            self.assertNotIn('.swipeActions', text)
            self.assertIn('if canManage', text)
        core = (ROOT / 'Axonhub/Core.swift').read_text()
        self.assertNotIn('graphQLError(safeMessage)', core)
        self.assertNotIn('root?["errors"].array.first?["message"]', core)

    def test_swift_parses_with_real_tree_sitter_grammar(self):
        from tree_sitter import Language, Parser
        import tree_sitter_swift
        parser = Parser(Language(tree_sitter_swift.language()))
        for file in sorted((ROOT / 'Axonhub').rglob('*.swift')) + sorted((ROOT / 'AxonhubTests').rglob('*.swift')):
            with self.subTest(file=file.name):
                self.assertFalse(parser.parse(file.read_bytes()).root_node.has_error, file.name)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--schema-dir', type=Path)
    args = parser.parse_args()
    ContractRegression.schema = contract.load_schema(args.schema_dir)
    unittest.main(argv=['management-static-regression'], verbosity=2)
