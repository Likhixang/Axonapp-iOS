#!/usr/bin/env python3
"""Offline verification only. Does NOT compile/run Swift, call an LLM, or require secrets.
Run with --official-root pointing at the beta10 source snapshot. Dependencies:
graphql-core, tree-sitter, tree-sitter-swift. Native tests are in PlaygroundProtocolTests.swift.
"""
import argparse
import json
import re
import unittest
from pathlib import Path
from graphql import build_schema, parse, validate
from tree_sitter import Language, Parser
import tree_sitter_swift

REPO = Path(__file__).resolve().parents[1]
OFFICIAL: Path = Path()


class SSEMirror:
    """Byte-for-byte logic mirror of PlaygroundSSEParser, not Swift execution."""
    def __init__(self):
        self.line = bytearray()
        self.lines = []
        self.size = 0
        self.skip_lf = False

    def end_line(self):
        value = self.line.decode("utf-8", errors="strict")
        self.line.clear()
        if not value:
            data = "\n".join(self.lines) if self.lines else None
            self.lines.clear()
            self.size = 0
            return data
        if value.startswith("data:") or value == "data":
            data = "" if value == "data" else value[5:]
            if data.startswith(" "):
                data = data[1:]
            self.size += len(data.encode())
            if self.size > 4 * 1024 * 1024:
                raise ValueError("event limit")
            self.lines.append(data)
        return None

    def feed(self, byte):
        if self.skip_lf:
            self.skip_lf = False
            if byte == 10:
                return None
        if byte == 13:
            self.skip_lf = True
            return self.end_line()
        if byte == 10:
            return self.end_line()
        if len(self.line) >= 1024 * 1024:
            raise ValueError("line limit")
        self.line.append(byte)
        return None

    def finish(self):
        if self.line:
            self.end_line()
        data = "\n".join(self.lines) if self.lines else None
        self.lines.clear()
        self.size = 0
        return data


def parse_bytes(wire):
    parser = SSEMirror()
    output = []
    for byte in wire:
        event = parser.feed(byte)
        if event is not None:
            output.append(event)
    event = parser.finish()
    if event is not None:
        output.append(event)
    return output


class PlaygroundOfflineTests(unittest.TestCase):
    def test_swift_syntax_only(self):
        parser = Parser(Language(tree_sitter_swift.language()))
        files = list((REPO / "Axonhub").glob("Playground*.swift")) + [REPO / "AxonhubTests/PlaygroundProtocolTests.swift"]
        self.assertEqual(len(files), 4)
        for file in files:
            with self.subTest(file=file.name):
                self.assertFalse(parser.parse(file.read_bytes()).root_node.has_error)

    def test_graphql_queries_validate_against_official_sdl(self):
        schema = build_schema("\n".join(p.read_text() for p in (OFFICIAL / "internal/server/gql").glob("*.graphql")),
                              assume_valid=True, assume_valid_sdl=True)
        source = (REPO / "Axonhub/PlaygroundService.swift").read_text()
        queries = re.findall(r'static let \w+Query = """(.*?)"""', source, re.S)
        self.assertEqual(len(queries), 3)
        for query in queries:
            with self.subTest(query=query.strip().splitlines()[0]):
                self.assertEqual(validate(schema, parse(query)), [])

    def test_route_and_auth_are_official(self):
        routes = (OFFICIAL / "internal/server/routes.go").read_text()
        frontend = (OFFICIAL / "frontend/src/features/playground/index.tsx").read_text()
        service = (REPO / "Axonhub/PlaygroundService.swift").read_text()
        self.assertIn('WithJWTAuth', routes)
        self.assertIn('"/playground/chat"', routes)
        self.assertIn("api: '/admin/playground/chat'", frontend)
        self.assertIn("Authorization: 'Bearer ' + accessToken", frontend)
        for header in ["X-Project-ID", "X-Channel-ID"]:
            self.assertIn(header, frontend)
            self.assertIn(header, service)
        self.assertIn('client.authType == .adminJWT ? "admin/playground/chat" : "v1/chat/completions"', service)
        self.assertIn('middleware.WithAPIKeyConfig', routes)
        self.assertIn('openaiGroup.POST("/chat/completions"', routes)
        self.assertNotIn('createAPIKey', service)

    def test_payload_fixture_fields_match_go_and_web(self):
        fixture = json.loads((REPO / "AxonhubTests/playground-contract-fixtures.json").read_text())
        aisdk = (OFFICIAL / "llm/transformer/aisdk/model.go").read_text()
        converter = (OFFICIAL / "llm/transformer/aisdk/convert_request.go").read_text()
        web = (OFFICIAL / "frontend/src/features/playground/index.tsx").read_text()
        go_keys = set(re.findall(r'json:"([^",]+)', aisdk))
        self.assertTrue(set(fixture["admin_payload"]) <= go_keys)
        self.assertEqual(fixture["admin_payload"]["messages"][0]["parts"][1]["type"], "file")
        self.assertIn('strings.HasPrefix(strings.ToLower(p.MediaType), "image/")', converter)
        for key in ["model", "temperature", "max_tokens", "system"]:
            self.assertIn(key + ":", web)
        self.assertIn("accept='image/*'", web)
        self.assertIn('Stream:      lo.ToPtr(true)', converter)
        openai = (OFFICIAL / "llm/transformer/openai/model.go").read_text()
        key_fields = set(re.findall(r'json:"([^",]+)', openai))
        self.assertTrue(set(fixture["api_key_payload"]) <= key_fields)
        self.assertEqual(fixture["api_key_payload"]["messages"][1]["content"][1]["type"], "image_url")
        # This validates checked-in payload fixtures and Swift field literals, not Swift execution.
        native = (REPO / "Axonhub/PlaygroundProtocol.swift").read_text()
        for field in fixture["admin_payload"]:
            self.assertIn('"' + field + '"', native)

    def test_official_aisdk_recording_sse_reconstruction(self):
        recording = OFFICIAL / "llm/transformer/aisdk/testdata/aisdk-strop.stream.jsonl"
        data = [json.loads(line)["Data"] for line in recording.read_text().splitlines() if line.strip()]
        expected = "".join(json.loads(s).get("delta", "") for s in data if s != "[DONE]" and json.loads(s)["type"] == "text-delta")
        for newline in ["\n", "\r\n", "\r"]:
            wire = "".join("data: " + s + newline + newline for s in data).encode()
            # feed single bytes: all network chunk boundaries, including UTF-8 splits.
            recovered = parse_bytes(wire)
            self.assertEqual(recovered, data)
            actual = "".join(json.loads(s).get("delta", "") for s in recovered if s != "[DONE]" and json.loads(s)["type"] == "text-delta")
            self.assertEqual(actual, expected)
            self.assertIn("1 2 3 4 5", actual)
            self.assertIn("16 17 18 19 20", actual)
            self.assertIn('[DONE]', recovered)

    def test_official_openai_reasoning_recording(self):
        recording = OFFICIAL / "llm/transformer/openai/testdata/deepseek-reasoninig.stream.jsonl"
        data = [json.loads(line)["Data"] for line in recording.read_text().splitlines() if line.strip()]
        self.assertEqual(parse_bytes("".join("data: " + s + "\n\n" for s in data).encode()), data)
        reasoning = []
        text = []
        for item in data:
            if item == '[DONE]':
                continue
            for choice in json.loads(item).get('choices', []):
                delta = choice.get('delta', {})
                reasoning.append(delta.get('reasoning_content') or '')
                text.append(delta.get('content') or '')
        self.assertTrue(''.join(reasoning))
        self.assertTrue(''.join(text))
        self.assertIn('20', ''.join(text))

    def test_comments_multiline_tail_and_utf8(self):
        self.assertEqual(parse_bytes(": heartbeat\r\ndata: 你好\r\ndata: 世界\r\n\r\ndata: tail".encode()), ['你好\n世界', 'tail'])
        with self.assertRaises(UnicodeDecodeError):
            parse_bytes(bytes([255, 10]))

    def test_line_limit(self):
        with self.assertRaises(ValueError):
            parse_bytes(b'x' * (1024 * 1024 + 1))

    def test_server_has_no_playground_history_write(self):
        web = (OFFICIAL / 'frontend/src/features/playground/index.tsx').read_text()
        chats = (OFFICIAL / 'frontend/src/features/chats/index.tsx').read_text()
        self.assertIn("// Fake Data", chats)
        self.assertIn("import { conversations } from './data/convo.json'", chats)
        for mutation in ['createChat', 'saveChat', 'createThread']:
            self.assertNotIn(mutation, web)
        routes = (OFFICIAL / 'internal/server/routes.go').read_text()
        admin = routes[routes.index('adminGroup :='):routes.index('openAPIGroup :=')]
        self.assertNotIn('WithThread', admin)

    def test_credentials_and_model_calls_not_persisted_or_automatic(self):
        files = [(REPO / 'Axonhub' / name).read_text() for name in ['Playground.swift', 'PlaygroundService.swift', 'PlaygroundProtocol.swift']]
        for source in files:
            source = re.sub(r'//[^\n]*', '', source)
            for forbidden in ['UserDefaults', 'Keychain.save', 'print(', 'WebView', 'WKWebView']:
                self.assertNotIn(forbidden, source)
        state = files[0]
        run = state[state.index('func run('):state.index('func importImages(')]
        before = state[:state.index('func run(')]
        self.assertNotIn('service.stream(', before)
        self.assertEqual(run.count('service.stream('), 1)
        self.assertIn('store.ensureClient()', run)
        self.assertIn('发送（消耗额度）', state)
        self.assertIn('重新生成（消耗额度）', state)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--official-root', type=Path, required=True)
    args = parser.parse_args()
    OFFICIAL = args.official_root
    unittest.main(argv=['playground_offline_contract.py'], verbosity=2)
