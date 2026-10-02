#!/usr/bin/env python3
"""Validate all shipped Swift GraphQL operations and variable fixtures.

Reference: exact official AxonHub v1.0.0-beta10 revision. No server writes.
Install scripts/requirements-api-contract.txt; --schema-dir uses local upstream SDL.
"""
import argparse
import base64
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import re
import subprocess
from graphql import build_schema, parse, validate
from graphql.execution.values import get_variable_values
from graphql.language.visitor import Visitor, visit

ROOT = Path(__file__).resolve().parents[1]
REVISION = '939b2bc07cc05bdf7750d7ec872290d67784d13d'


def github(path):
    return json.loads(subprocess.check_output(['gh', 'api', path]))


def load_schema(directory=None):
    if directory:
        documents = [p.read_text() for p in directory.glob('*.graphql')]
    else:
        tree = github(f'repos/looplj/axonhub/git/trees/{REVISION}?recursive=1')['tree']
        paths = [item['path'] for item in tree if item['type'] == 'blob'
                 and item['path'].startswith('internal/server/gql/')
                 and item['path'].endswith('.graphql') and '/openapi/' not in item['path']]
        def load(path):
            result = github(f'repos/looplj/axonhub/contents/{path}?ref={REVISION}')
            return base64.b64decode(result['content']).decode()
        with ThreadPoolExecutor(max_workers=6) as pool:
            documents = list(pool.map(load, paths))
    assert documents, 'No official schema documents found'
    return build_schema('\n'.join(documents), assume_valid=True, assume_valid_sdl=True)


def shipped_operations():
    operations = {}
    for file in sorted((ROOT / 'Axonhub').rglob('*.swift')):
        source = file.read_text()
        for text in re.findall(r'"""(.*?)"""', source, re.S):
            if not re.match(r'\s*(query|mutation|subscription)\b', text):
                continue
            assert '\\(' not in text, f'{file}: interpolated GraphQL cannot be checked safely'
            document = parse(text)
            for definition in document.definitions:
                if definition.kind != 'operation_definition':
                    continue
                assert definition.name, f'{file}: operation must be named'
                name = definition.name.value
                assert name not in operations, f'Duplicate operation: {name}'
                operations[name] = (file, document, definition)
    assert operations, 'No shipped operations found'
    return operations


def check(schema, fixtures=None):
    if fixtures is None:
        fixtures = {}
        paths = sorted((ROOT / 'scripts').glob('*contract-fixtures.json'))
        paths += sorted((ROOT / 'scripts').glob('*graphql-fixtures.json'))
        # Playground REST payload fixtures use a different schema and are checked separately.
        paths += sorted((ROOT / 'AxonhubTests').glob('*graphql-fixtures.json'))
        for path in paths:
            for name, samples in json.loads(path.read_text()).items():
                fixtures[name] = samples
    operations = shipped_operations()
    output_fields = set()
    class FieldCollector(Visitor):
        def enter_field(self, node, *_):
            output_fields.add(node.name.value)
    for _, document, _ in operations.values():
        visit(document, FieldCollector())
    presentation = json.loads((ROOT / 'Axonhub/PresentationLabels.json').read_text())
    assert output_fields <= presentation['fields'].keys(), f'Unmapped output fields: {output_fields-presentation["fields"].keys()}'
    print(f'Presentation labels cover all {len(output_fields)} selected GraphQL output fields')
    assert set(fixtures) == set(operations), f'Fixture/operation mismatch: {set(fixtures) ^ set(operations)}'
    failures = []
    count = 0
    for name, (file, document, definition) in operations.items():
        failures.extend(f'{name}: {e.message}' for e in validate(schema, document))
        for sample in fixtures[name]:
            values = get_variable_values(schema, definition.variable_definitions or [], sample['variables'])
            errors = values if isinstance(values, list) else []
            failures.extend(f'{name}/{sample["label"]}: {e.message}' for e in errors)
            count += 1
        print(f'{name}: official operation + {len(fixtures[name])} variable fixtures valid ({file.name})')
    assert not failures, '\n'.join(failures)
    source = '\n'.join(p.read_text() for p in (ROOT / 'Axonhub').rglob('*.swift'))
    assert 'openapi/v1/graphql' not in source, 'User API keys cannot use service-account OpenAPI'
    print(f'All {len(operations)} operations / {count} fixtures match AxonHub {REVISION}')
    return operations


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--schema-dir', type=Path)
    args = parser.parse_args()
    check(load_schema(args.schema_dir))


if __name__ == '__main__':
    main()
