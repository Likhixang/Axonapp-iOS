#!/usr/bin/env python3
"""Offline authoritative SDL/coercion for channel/model module only. No server writes."""
import argparse, importlib.util, json, re
from pathlib import Path
from graphql import validate, parse
from graphql.execution.values import get_variable_values
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('contract', ROOT/'scripts/check-api-contract.py')
contract = importlib.util.module_from_spec(spec); spec.loader.exec_module(contract)
parser = argparse.ArgumentParser(); parser.add_argument('--schema-dir', type=Path); args = parser.parse_args()
schema = contract.load_schema(args.schema_dir)
fixtures = json.loads((ROOT/'scripts/channel-model-contract-fixtures.json').read_text())
operations = {k:v for k,v in contract.shipped_operations().items() if k in fixtures or k.startswith(('Channel', 'Model'))}
assert set(operations) == set(fixtures), set(operations)^set(fixtures)
count = 0
for name,(file,doc,definition) in operations.items():
    errors = validate(schema,doc); assert not errors, (name,[e.message for e in errors])
    for item in fixtures[name]:
        values = get_variable_values(schema,definition.variable_definitions or [],item['variables'])
        assert not isinstance(values,list), (name,item['label'],[e.message for e in values])
        count += 1
    print(name, 'valid')
# Runtime expands truncated leaf. Validate a substantially deeper actual emitted selection.
source=(ROOT/'Axonhub/Management.swift').read_text()
query = re.search(r'query ModelDetail.*?"""', source, re.S).group(0)[:-3]
for _ in range(10): query=query.replace('conditions { type }','conditions { type logic field operator value conditions { type } }')
assert not validate(schema,parse(query)), 'recursive expanded query must match schema'
print(f'PASS {len(operations)} operations / {count} offline variable fixtures + recursive expansion')
