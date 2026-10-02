#!/usr/bin/env python3
"""Real bundled logo validation. Native matching tests require macOS Swift; no simulator."""
import argparse,json,re,struct,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--compiled')
    parser.add_argument('--swift',action='store_true')
    args=parser.parse_args()
    assets=ROOT/'Axonhub/Assets.xcassets'
    source=(ROOT/'Axonhub/BrandIdentity.swift').read_text()
    provenance=json.loads((ROOT/'scripts/assets/brand-icons-provenance.json').read_text())
    channels=provenance['channelTypes']
    colored=set(provenance['lobeIcons']['colorVariants'])
    names=set()
    for folder in sorted(assets.glob('Brand-*.imageset')):
        name=folder.stem.removeprefix('Brand-');names.add(name)
        assert '"'+name+'"' in source,name
        data=json.loads((folder/'Contents.json').read_text())
        assert data['properties']['template-rendering-intent'] in ['template','original']
        if name in colored: assert data['properties']['template-rendering-intent']=='original', 'Brand color stripped: '+name
        raw=(folder/'icon.png').read_bytes()
        assert raw[:8]==b'\x89PNG\r\n\x1a\n' and struct.unpack('>II',raw[16:24])==(128,128),name
        assert raw[25]==6, 'Logo alpha missing: '+name
    for channel,brand in channels.items():
        assert brand in names and '"'+channel+'": "'+brand+'"' in source,channel
    assert 'BrandIdentity.channel(channel.type)' in (ROOT/'Axonhub/ChannelsView.swift').read_text()
    assert 'BrandIdentity.asset(icon: model.icon)' in (ROOT/'Axonhub/ModelsView.swift').read_text()
    for filename in ['NativePresentation.swift','ChannelsView.swift','ModelsView.swift']:
        text=(ROOT/'Axonhub'/filename).read_text()
        assert '.background(tint.opacity' not in text
        assert '.background(Color(.tertiarySystemGroupedBackground)' not in text
    print(f'PASS: {len(names)} bundled genuine logos, {len(channels)} upstream channel mappings, model.icon wired, no icon tile backgrounds')
    assert colored <= names and {'google','deepseek','qwen','claude','minimax'} <= colored
    app=(ROOT/'Axonhub/App.swift').read_text()
    assert '.tint(resolvedAccentColor(hex))' in app and '.accentColor(resolvedAccentColor(hex))' in app
    for filename in ['NativePresentation.swift','ManagementInstanceControls.swift','ManagementDashboardView.swift','KeysWorkspaceView.swift','APIKeysView.swift']:
        assert 'foregroundStyle(Color.accentColor)' in (ROOT/'Axonhub'/filename).read_text(), filename
    health=(ROOT/'Axonhub/ChannelHealthViews.swift').read_text()
    assert 'foregroundStyle(.green)' in health and 'Color.orange' in health
    assert '.foregroundStyle(.green)' in (ROOT/'Axonhub/APIKeysView.swift').read_text()
    print(f'PASS: {len(colored)} upstream color variants use original rendering; theme tint/accent bridge and semantic colors retained')
    if args.compiled:
        compiled=json.loads(Path(args.compiled).read_text())
        packaged={x.get('Name') for x in compiled}
        assert not {'Brand-'+n for n in names}-packaged, 'Compiled brand images missing'
        print(f'PASS: all {len(names)} brands present in compiled Assets.car')
    if args.swift:
        identity=source[source.index('enum BrandIdentity'):source.index('struct BrandMark')]
        tests='\nassert(BrandIdentity.channel("openai_responses") == "Brand-openai")\nassert(BrandIdentity.channel("deepseek_anthropic") == "Brand-deepseek")\nassert(BrandIdentity.channel("gemini_vertex") == "Brand-google")\nassert(BrandIdentity.channel("unknown_channel") == nil)\nassert(BrandIdentity.asset(icon: "DeepSeek") == "Brand-deepseek")\nassert(BrandIdentity.asset(icon: "Qwen") == "Brand-qwen")\nassert(BrandIdentity.asset(icon: "not-a-real-logo") == nil)\nassert(BrandIdentity.asset(icon: "") == nil)\nassert(BrandIdentity.asset(icon: nil) == nil)\nfor (_, brand) in BrandIdentity.channelIcons { assert(BrandIdentity.asset(icon: brand) != nil) }\nprint("PASS: native Swift matching, explicit icon handling and unknown/missing metadata")\n'
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/'main.swift';path.write_text(identity+tests)
            subprocess.run(['swift',str(path)],check=True)
if __name__=='__main__':main()
