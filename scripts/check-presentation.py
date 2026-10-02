#!/usr/bin/env python3
"""Complete presentation coverage + optional real host Swift execution (no simulator)."""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--swift', action='store_true')
    args = parser.parse_args()
    labels = json.loads((ROOT / 'Axonhub/PresentationLabels.json').read_text())
    schema = json.loads((ROOT / 'Axonhub/AdminSchema.json').read_text())
    fields = {f['name'] for t in schema['types'].values() for f in t['fields']}
    fields |= {f['name'] for op in schema['operations'] for f in op['variables']}
    advanced = (ROOT / 'Axonhub/ChannelAdvancedInputs.swift').read_text()
    fields |= set(re.findall(r'"(\w+)": "(?:\[)?\w+[!\]]*"', advanced.split('static let enums')[0]))
    enums = {v for t in schema['types'].values() if t['kind'] == 'enum' for v in t['values']}
    enums |= set(re.findall(r'"(\w+)"', advanced.split('static let enums')[1].split('static func validate')[0])) - set(re.findall(r'"(\w+)":', advanced.split('static let enums')[1].split('static func validate')[0]))
    operations = {o['id'] for o in schema['operations']}
    assert fields <= labels['fields'].keys(), fields-labels['fields'].keys()
    assert enums <= labels['values'].keys(), enums-labels['values'].keys()
    assert operations <= labels['operations'].keys(), operations-labels['operations'].keys()
    assert all(value != key for key, value in labels['fields'].items())
    assert all(value != key for key, value in labels['operations'].items())
    for file in (ROOT / 'Axonhub').glob('*.swift'):
        source = file.read_text()
        for pattern in [r'DisclosureGroup\(key\)', r'Text\(field\.name\)', r'(?:Picker|Toggle|SecureField|TextField)\(path,', r'Text\(\$0\.rawValue\)', r'Text\((?:channel|project|user)\.status(?:\.uppercased\(\))?\)', r'Text\(channel\.type\.uppercased\(\)\)']:
            assert not re.search(pattern, source), f'{file.name}: raw UI label {pattern}'
    print(f'PASS: {len(fields)} typed fields, {len(enums)} enum choices, {len(operations)} operation titles; no raw-label regression')
    about = (ROOT / 'Axonhub/SettingsView.swift').read_text().split('struct AboutView: View {')[1]
    for required in ['独立第三方客户端', '开源与致谢', '问题反馈', '源代码', '图标许可', '许可文件未能读取']:
        assert required in about, required
    assert 'CFBundleShortVersionString' in about and 'CFBundleVersion' in about
    assert 'Section("安全与兼容")' not in about
    assert 'AxonHub 原生客户端' not in about
    assert 'BrandIcons-LICENSE' in about and 'String(contentsOf: url' in about
    notices = (ROOT / 'Axonhub/BrandIcons-LICENSE.txt').read_text()
    assert 'MIT License' in notices and 'Apache License' in notices
    print('PASS: About third-party identity, real project links and bundled license route')
    if args.swift:
        core = (ROOT / 'Axonhub/Core.swift').read_text()
        core = core[core.index('indirect enum JSON:'):core.index('/// Safe user-facing errors')]
        presentation = (ROOT / 'Axonhub/NativeSystemSettings.swift').read_text()
        presentation = presentation[presentation.index('enum NativeAdminLabels'):presentation.index('struct NativeSystemSettingsView')]
        display = (ROOT / 'Axonhub/NativePresentation.swift').read_text()
        date = display[display.index('    static func date'):display.index('struct NativeDetailFieldsView')]
        tests = r'''func obsText(_ key: String) -> String { key }
func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    precondition(condition(), name)
    print("PASS: " + name)
}
check(NativeAdminLabels.field("autoSyncSupportedModels") == "自动同步支持的模型", "advanced channel field")
check(NativeAdminLabels.path("settings.rateLimit.queueTimeoutMs") == "设置 › 限流 › 队列超时（ms）", "nested field path")
check(NativeAdminLabels.field("completionTokensGTE") != "completionTokensGTE", "filter operator label")
check(NativeAdminLabels.operation("getCacheDiagnostics") == "缓存诊断", "operation title")
check(NativeAdminLabels.value("image_generation") == "图像生成", "model type")
check(NativeAdminLabels.scalar(.string("completed"), key: "status") == "已完成", "status translation")
check(NativeAdminLabels.scalar(.string("completed"), key: "name") == "completed", "preserve user names")
check(NativeAdminLabels.scalar(.string("user"), key: "role") == "用户", "message role")
check(NativeAdminLabels.scalar(.string("model_id"), key: "content") == "model_id", "preserve message content")
check(NativeAdminLabels.scalar(.bool(false), key: "enabled") == "否", "boolean label")
check(NativeAdminLabels.scalar(.null) == "—", "null placeholder")
check(!NativeAdminLabels.scalar(.number(42), key: "statusCodes").isEmpty, "numeric array item")
let payload = JSON.object(["name": .string("completed"), "status": .string("completed"), "body": .string("user")])
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
let encoded = try encoder.encode(payload)
_ = NativeAdminLabels.scalar(payload["status"], key: "status")
let afterDisplay = try encoder.encode(payload)
check(afterDisplay == encoded, "presentation never changes API payload")
'''
        formatting = (ROOT / 'Axonhub/DisplayFormat.swift').read_text().replace('import Foundation', '')
        health = (ROOT / 'Axonhub/ChannelHealthStatistics.swift').read_text().replace('import Foundation', '')
        tests += r'''
let emptyHealth = ChannelHealthStatistics(rows: [])
check(emptyHealth.rate == nil && emptyHealth.percentage == "—", "empty sample remains unknown")
let perfectHealth = ChannelHealthStatistics(.object(["successCount": .number(3), "failedCount": .number(0)]))
check(perfectHealth.rate == 100, "perfect execution rate")
let failedHealth = ChannelHealthStatistics(.object(["successCount": .number(0), "failedCount": .number(4)]))
check(failedHealth.rate == 0 && failedHealth.needsAttention, "all failures and attention filter")
let weightedHealth = ChannelHealthStatistics(rows: [.object(["successCount": .number(1), "failedCount": .number(0)]), .object(["successCount": .number(0), "failedCount": .number(9)])])
check(weightedHealth.rate == 10 && weightedHealth.total == 10, "weighted counts not mean of percentages")
let staleRate = ChannelHealthStatistics(.object(["successRate": .number(80), "totalCount": .number(100)]))
check(staleRate.rate == nil, "missing execution counts are not fabricated")
'''
        tests += r'''
check(DisplayFormat.compact(0) == "0", "zero tokens")
check(DisplayFormat.compact(999) == "999", "small token values")
check(DisplayFormat.compact(1_000) == "1K", "K boundary")
check(DisplayFormat.compact(1_000_000) == "1M", "M boundary")
check(DisplayFormat.compact(1_000_000_000) == "1B", "B boundary")
check(DisplayFormat.compact(999_999) == "1M", "rounded K promotes to M")
check(DisplayFormat.compact(999_999_999) == "1B", "rounded M promotes to B")
check(DisplayFormat.compact(-1_500) == "-1.5K", "negative display")
check(DisplayFormat.compact(.infinity) == "—", "nonfinite display")
for key in ["prompt_tokens", "total_tokens", "cachedTokens", "reasoningTokens", "totalTokensThisMonth", "tokensCount"] {
    check(NativeAdminLabels.scalar(.number(1_500_000), key: key) == "1.5M", "token quantity " + key)
    check(NativeAdminLabels.scalar(.string("1500000"), key: key) == "1.5M", "string token quantity " + key)
}
check(!DisplayFormat.isTokenQuantity("accessToken") && !DisplayFormat.isTokenQuantity("refreshToken"), "credential tokens are not quantities")
check(NativeAdminLabels.scalar(.string("1500000"), key: "accessToken") == "1500000", "preserve opaque auth token")
let isoValue = "2026-01-02T15:04:05.123Z"
let instant = ISO8601DateFormatter()
instant.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
let parsedInstant = instant.date(from: isoValue)!
let systemDate = DateFormatter()
systemDate.locale = .autoupdatingCurrent
systemDate.calendar = .autoupdatingCurrent
systemDate.timeZone = .autoupdatingCurrent
systemDate.dateStyle = .medium
systemDate.timeStyle = .short
check(NativeDisplay.date(isoValue) == systemDate.string(from: parsedInstant), "timestamps follow system date time and timezone")
check(NativeDisplay.date("2026-01-02T15:04:05Z") == systemDate.string(from: parsedInstant), "timestamps without fractional seconds")
check(NativeDisplay.date("2026-01-02") != "2026-01-02", "daily date is system localized")
check(NativeDisplay.date("not-a-date") == "not-a-date", "invalid source date preserved")
check(NativeDisplay.date("2026-02-31") == "2026-02-31", "invalid calendar date preserved")
'''
        # The dictionary read uses Bundle.main exactly as it does in the app.
        with tempfile.TemporaryDirectory(prefix='axon-presentation-') as directory:
            path = Path(directory)
            (path / 'PresentationLabels.json').write_bytes((ROOT / 'Axonhub/PresentationLabels.json').read_bytes())
            (path / 'main.swift').write_text('import Foundation\n'+core+'\n'+formatting+'\nenum NativeDisplay {\n'+date+'\n'+presentation+'\n'+health+'\n'+tests)
            subprocess.run(['swiftc', str(path/'main.swift'), '-o', str(path/'presentation-tests')], check=True)
            subprocess.run([str(path/'presentation-tests')], check=True)

if __name__ == '__main__':
    main()
