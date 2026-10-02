#!/usr/bin/env python3
"""Offline contract, schema-resource and native administration safety regressions.

No production writes; no claim of Xcode compilation on Linux.
Install graphql-core==3.2.6, tree-sitter and tree-sitter-swift in a scratch venv.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import re
from graphql import build_schema, parse, validate, is_input_object_type, is_enum_type, is_scalar_type
from graphql.execution.values import get_variable_values
from tree_sitter import Parser, Language
import tree_sitter_swift

ROOT = Path(__file__).resolve().parents[1]
REVISION = '939b2bc07cc05bdf7750d7ec872290d67784d13d'
FILES = ['AdminCenter.swift','AdminOperations.swift','AdminTransfer.swift','AdminDocuments.swift','SchemaForm.swift']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--schema-dir', required=True, type=Path)
    args = parser.parse_args()
    schema = build_schema('\n'.join(p.read_text() for p in args.schema_dir.glob('*.graphql')), assume_valid=True)
    resource = json.loads((ROOT/'Axonhub/AdminSchema.json').read_text())
    fixtures = json.loads((ROOT/'scripts/admin-contract-fixtures.json').read_text())
    assert resource['revision'] == REVISION
    operations = {}
    swift_parser = Parser(Language(tree_sitter_swift.language()))
    for filename in FILES:
        source = (ROOT/'Axonhub'/filename).read_text()
        tree = swift_parser.parse(source.encode())
        assert not tree.root_node.has_error, f'{filename}: Swift syntax parse error (not a typecheck)'
        for text in re.findall(r'"""(.*?)"""', source, re.S):
            if not re.match(r'\s*(query|mutation)\b', text):
                continue
            assert '\\(' not in text
            document = parse(text)
            operation = document.definitions[0]
            name = operation.name.value
            assert name not in operations, name
            assert name.startswith('Admin'), name
            assert not validate(schema, document), f'{name}: {validate(schema, document)}'
            operations[name] = (document, operation)
    assert set(operations) == set(fixtures) == {m['name'] for m in resource['operations']}
    count = 0
    for name, samples in fixtures.items():
        _, definition = operations[name]
        for sample in samples:
            values = get_variable_values(schema, definition.variable_definitions or [], sample['variables'])
            assert not isinstance(values, list), f'{name}/{sample["label"]}: {values}'
            count += 1
    # Complete SDL schema-derived form metadata, not a hand-picked subset.
    expected_types = {name for name, value in schema.type_map.items() if not name.startswith('__') and
                      (is_input_object_type(value) or is_enum_type(value) or is_scalar_type(value))}
    assert set(resource['types']) == expected_types
    field_count = 0
    for name, data in resource['types'].items():
        official = schema.get_type(name)
        if is_input_object_type(official):
            assert {f['name']:f['type'] for f in data['fields']} == {k:str(v.type) for k,v in official.fields.items()}, name
            field_count += len(data['fields'])
        if is_enum_type(official):
            assert data['values'] == list(official.values), name
    documents_source = (ROOT/'Axonhub/AdminDocuments.swift').read_text()
    center = (ROOT/'Axonhub/AdminCenter.swift').read_text()
    engine = (ROOT/'Axonhub/AdminOperations.swift').read_text()
    form = (ROOT/'Axonhub/SchemaForm.swift').read_text()
    transfer = (ROOT/'Axonhub/AdminTransfer.swift').read_text()
    source = center + engine + form + transfer
    for forbidden in ['WKWebView', 'SFSafariViewController', 'UIApplication.shared.open', 'UserDefaults', 'print(', 'fetchSnapshot(']:
        assert forbidden not in source, f'Unsafe/native contract: {forbidden}'
    assert 'try store.ensureClient()' in engine
    assert 'current.token == client.token' in engine and 'store.selectedInstance == instance' in engine
    assert '.onChange(of: store.selectedID)' in center and '.onChange(of: store.selectedInstance)' in center
    assert 'confirmationDialog' in center and 'confirmationDialog' in transfer
    assert 'guard !busy, !invalidated' in engine
    assert 'guard case .array' in engine
    assert 'guard case .array(let items) = actual' in engine
    assert 'nullUnsupported' in form and 'if type.hasSuffix("!") || mutation' in form
    assert 'SecureField' in form and 'pickerStyle(.menu)' in form and 'AdminNestedForm' in form
    assert 'X-Project-ID' in engine and 'NoRedirectDelegate' in engine
    assert 'variables.file' in transfer and 'filename=\\"backup.json\\"' in transfer
    # Nonsecret list/detail reads; reveal only explicit operation IDs.
    for metadata in resource['operations']:
        document, definition = operations[metadata['name']]
        assert metadata['documentKey'] in documents_source
        assert metadata['variables'] == [{
            'name':v.variable.name.value, 'type':str(__import__('graphql').type_from_ast(schema,v.type)),
            'description':'', 'hasDefault':v.default_value is not None,
            'default':__import__('graphql').value_from_ast_untyped(v.default_value) if v.default_value else None
        } for v in (definition.variable_definitions or [])]
        if metadata['kind']=='mutation' and metadata['id'] not in ['restore','previewPromptProtectionRule']:
            assert metadata['verification'], f'No precise target readback: {metadata["id"]}'
        if metadata['group']=='Internal':
            assert metadata['id'].startswith(('detail','reveal')), metadata
    # Regression: Go business ignores these SDL fields: no accidental editable writes.
    by_id = {m['id']:m for m in resource['operations']}
    assert by_id['createUser']['allowedInputFields'] == ['email','password','firstName','lastName','scopes','roleIDs']
    assert by_id['updateRole']['allowedInputFields'] == ['name','scopes']
    assert by_id['updateProject']['allowedInputFields'] == ['name','description','clearUsers','addUserIDs','removeUserIDs']
    assert by_id['updateDataStorage']['allowedInputFields'] == ['name','description','status','settings']
    assert by_id['createDataStorage']['allowedInputFields'] == ['name','description','type','settings']
    assert 'min(600, max(0, value.number))' in engine
    assert 'seconds.number <= 0 ? 3600 : min(604800, max(60, seconds.number))' in engine
    assert 'clearAllowedIps' in engine and 'input.removeValue(forKey: key)' in engine
    assert 'containsTruncatedObject' in engine
    groups = {m['group'] for m in resource['operations'] if m['group'] != 'Internal'}
    for group in groups:
        assert f'"{group}"' in center, f'Missing native group: {group}'
    for root in ['createAPIKey','updateAPIKey','updateAPIKeyProfiles','bulkArchiveAPIKeys','rotateAPIKey',
                 'createApiKeyProfileTemplate','updateApiKeyProfileTemplate','deleteApiKeyProfileTemplate','loadApiKeyProfileTemplate',
                 'createUser','updateUser','deleteUser','createRole','updateRole','bulkDeleteRoles','createProject',
                 'updateProjectProfiles','addUserToProject','removeUserFromProject','updateProjectUser','projectUsers',
                 'createPrompt','updatePrompt','bulkDeletePrompts','createPromptProtectionRule','previewPromptProtectionRule',
                 'createDataStorage','updateDataStorage','updateSystemModelSettings','updateMe','updateMyPassword','unlinkOIDCIdentity',
                 'backup','restore','triggerAutoBackup','triggerGcCleanup','clearCache']:
        assert root in by_id, f'Missing operation: {root}'
    print(f'PASS: {len(operations)} named official GraphQL operations / {count} coerced fixtures')
    print(f'PASS: complete {len(resource["types"])} input/scalar/enum types / {field_count} input fields')
    print(f'PASS: {len(FILES)} Swift files parsed; native routes, instance binding, confirmation, readback, secrets and Go-write restrictions checked')
    print('LIMIT: syntax parser is not Swift/Xcode typecheck; fixtures validate GraphQL contracts, not live resolver permissions/business effects')


if __name__ == '__main__':
    main()
