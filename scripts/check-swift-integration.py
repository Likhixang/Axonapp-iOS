#!/usr/bin/env python3
"""Source guards for Swift integration errors found by device archive compilation."""
from pathlib import Path
import re
ROOT = Path(__file__).resolve().parents[1]

def bindings(text):
    depth = 0
    quoted = False
    escaped = False
    start = 0
    parts = []
    for i, c in enumerate(text):
        if quoted:
            if escaped: escaped = False
            elif c == "\\": escaped = True
            elif c == '"': quoted = False
        elif c == '"': quoted = True
        elif c in "([{<": depth += 1
        elif c in ")]}>": depth -= 1
        elif c == "," and depth == 0:
            parts.append(text[start:i].strip()); start = i + 1
    parts.append(text[start:].strip())
    return parts

def main():
    errors = []
    for path in (ROOT / "Axonhub").glob("*.swift"):
        for n, line in enumerate(path.read_text().splitlines(), 1):
            match = re.match(r"\s*@(?:State|StateObject|ObservedObject|Published|Binding) .*?var (.*)", line)
            if match and len(bindings(match.group(1))) > 1:
                errors.append(f"{path.name}:{n}: property wrapper has multiple bindings")
            if "catch { error =" in line:
                errors.append(f"{path.name}:{n}: catch error shadows stored error")
            if re.search(r"NavigationStack \{ .*target: \$0", line):
                errors.append(f"{path.name}:{n}: nested closure uses unnamed outer sheet argument")
    assert not errors, "\n".join(errors)
    print("PASS: property wrappers, catch shadowing and sheet closure arguments")
    for name in ["ChannelsView.swift", "ModelsView.swift"]:
        source = (ROOT / "Axonhub" / name).read_text()
        row = source.split("struct ")[1].split("struct ")[0]
        assert ".swipeActions(edge: .leading, allowsFullSwipe: false)" in row
        assert ".swipeActions(edge: .trailing, allowsFullSwipe: false)" in row
        assert "NeutralActionFooter" not in row and not re.search(r"\bToggle\(", row)
        assert "Button(action: onEdit)" in row and "onToggle(!" in row
        assert ".contextMenu" in row and ".confirmationDialog" in row
        assert ".neutralCard()" in row and ".buttonStyle(.bordered)" not in row
        if name == "ChannelsView.swift": assert "Button(action: onTest)" in row
    keys = (ROOT / "Axonhub/KeysWorkspaceView.swift").read_text()
    assert ".swipeActions(edge: .leading, allowsFullSwipe: false)" in keys
    assert ".swipeActions(edge: .trailing, allowsFullSwipe: false)" in keys
    connection = (ROOT / "Axonhub/ManagementInstanceControls.swift").read_text()
    assert "NeutralActionFooter" not in connection
    assert ".swipeActions(edge: .leading, allowsFullSwipe: false)" in connection
    assert ".swipeActions(edge: .trailing, allowsFullSwipe: false)" in connection
    assert "Picker(" in connection and "重新连接" in connection and "编辑连接" in connection and "新增实例" in connection
    stat = (ROOT / "Axonhub/DashboardView.swift").read_text().split("struct DashboardView")[0]
    assert "@ScaledMetric" in stat and ".frame(height: cardHeight" in stat
    assert "subtitle" not in stat and "reservesSpace: true" in stat
    assert ".foregroundStyle(tint)" in stat
    overview = (ROOT / "Axonhub/ManagementDashboardView.swift").read_text()
    assert overview.count("GridItem(.flexible(minimum: 0)") == 2
    for color in ["blue", "purple", "orange", "green"]:
        assert "tint: ." + color in overview
    print("PASS: instance swipe controls and equal-size stat-card constraints; source guards only")
    print("PASS: swipe actions, no persistent action bars, no full-swipe mutations; source guards only")

if __name__ == "__main__": main()
