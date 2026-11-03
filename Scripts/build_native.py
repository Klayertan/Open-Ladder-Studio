#!/usr/bin/env python3
"""Dependency-free local build using an installed Xcode Swift toolchain.
Does not change or accept any system license, signing, or security settings.
"""
from pathlib import Path
import subprocess, plistlib, shutil, os, argparse, hashlib
root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--test', action='store_true')
parser.add_argument('--assets', action='store_true', help='Regenerate examples and icon')
args = parser.parse_args()
developer = Path(os.environ.get('DEVELOPER_DIR', '/Applications/Xcode.app/Contents/Developer'))
swift = developer/'Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc'
sdk = developer/'Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk'
platform = developer/'Platforms/MacOSX.platform/Developer'
# Keep signed bundles off cloud-synchronized Documents folders, whose metadata can invalidate signatures.
workspace_id = hashlib.sha256(str(root).encode()).hexdigest()[:12]
out = Path(os.environ.get('OPEN_LADDER_BUILD_DIR', str(Path.home()/'Library/Caches/OpenLadderStudio'/workspace_id/'Native')))
out.mkdir(parents=True, exist_ok=True)
link_path = root/'build/Native'
link_path.parent.mkdir(parents=True, exist_ok=True)
if not link_path.is_symlink() and link_path.exists():
    archived = root/'build/Native.previous'
    if archived.exists(): shutil.rmtree(archived)
    link_path.rename(archived)
if link_path.is_symlink(): link_path.unlink()
link_path.symlink_to(out, target_is_directory=True)
def run(command, **kwargs):
    subprocess.run([str(x) for x in command], cwd=root, check=True, **kwargs)
base=[swift, '-sdk',sdk, '-target','arm64-apple-macosx14.0','-swift-version','6','-g','-Onone','-enable-testing']
core=out/'LadderCore.framework'; modules=core/'Modules/LadderCore.swiftmodule'; modules.mkdir(parents=True,exist_ok=True)
core_sources=sorted((root/'Sources/LadderCore').glob('*.swift'))
run(base+['-emit-library','-emit-module','-module-name','LadderCore','-emit-module-path',modules/'arm64-apple-macos.swiftmodule','-Xlinker','-install_name','-Xlinker','@rpath/LadderCore.framework/LadderCore',*core_sources,'-o',core/'LadderCore'])
with (core/'Info.plist').open('wb') as f:
    plistlib.dump(dict(CFBundleIdentifier='studio.openladder.core',CFBundleName='LadderCore',CFBundleExecutable='LadderCore',CFBundlePackageType='FMWK',CFBundleVersion='1'),f)
link=['-F',out,'-framework','LadderCore','-Xlinker','-rpath','-Xlinker',str(out)]
if args.assets or not (root/'Sources/OpenLadderStudio/Resources/AppIcon.icns').exists():
    run(base+link+[root/'Scripts/MakeAssets.swift','-o',out/'MakeAssets'])
    run([out/'MakeAssets',root])
    run(['/usr/bin/iconutil','-c','icns',root/'build/AppIcon.iconset','-o',root/'Sources/OpenLadderStudio/Resources/AppIcon.icns'])
app=out/'Open Ladder Studio.app'; contents=app/'Contents'; (contents/'MacOS').mkdir(parents=True, exist_ok=True)
resources=contents/'Resources'; resources.mkdir(exist_ok=True)
app_sources=sorted((root/'Sources/OpenLadderStudio').rglob('*.swift'))
run(base+['-F',out,'-framework','LadderCore','-parse-as-library','-module-name','OpenLadderStudio',*app_sources,'-Xlinker','-rpath','-Xlinker','@executable_path/../Frameworks','-o',out/'OpenLadderStudioExecutable'])
shutil.copy2(out/'OpenLadderStudioExecutable', contents/'MacOS/Open Ladder Studio')
frameworks=contents/'Frameworks'; frameworks.mkdir(exist_ok=True)
shutil.copytree(core,frameworks/'LadderCore.framework',dirs_exist_ok=True,ignore=shutil.ignore_patterns('*.dSYM'))
for lang in ['en','ja']:
    shutil.copytree(root/f'Sources/OpenLadderStudio/Resources/{lang}.lproj',resources/f'{lang}.lproj',dirs_exist_ok=True)
shutil.copy(root/'Sources/OpenLadderStudio/Resources/AppIcon.icns', resources)
shutil.copytree(root/'Examples',resources/'Examples',dirs_exist_ok=True)
with (root/'Sources/OpenLadderStudio/Info.plist').open('rb') as f: info=plistlib.load(f)
info.update(CFBundleExecutable='Open Ladder Studio',CFBundleIdentifier='studio.openladder.app')
with (contents/'Info.plist').open('wb') as f: plistlib.dump(info,f)
# Finder/iCloud may attach metadata to generated bundles. Remove only signing-incompatible metadata.
for attribute in ['com.apple.FinderInfo', 'com.apple.ResourceFork']:
    subprocess.run(['/usr/bin/xattr', '-dr', attribute, str(app)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
run(['/usr/bin/codesign','--force','--sign','-',frameworks/'LadderCore.framework'])
run(['/usr/bin/codesign','--force','--sign','-',app])
print(f'Built {app}',flush=True)
if args.test:
    # Build an importable app module for integration tests using the same sources.
    run(base+link+['-parse-as-library','-emit-library','-emit-module','-module-name','OpenLadderStudio','-emit-module-path',out/'OpenLadderStudio.swiftmodule',*app_sources,'-o',out/'libOpenLadderStudio.dylib'])
    test_sources=sorted((root/'Tests').rglob('*Tests.swift'))
    bundle=out/'LadderTests.xctest'; executable=bundle/'Contents/MacOS/LadderTests'
    executable.parent.mkdir(parents=True,exist_ok=True)
    with (bundle/'Contents/Info.plist').open('wb') as f:
        plistlib.dump(dict(CFBundleExecutable='LadderTests',CFBundleIdentifier='studio.openladder.directtests',CFBundlePackageType='BNDL'),f)
    test_flags=['-I',platform/'usr/lib','-L',platform/'usr/lib','-Xlinker','-rpath','-Xlinker',platform/'usr/lib','-F',platform/'Library/Frameworks','-I',out,'-L',out,'-lOpenLadderStudio','-framework','XCTest','-Xlinker','-rpath','-Xlinker',platform/'Library/Frameworks']
    run(base+link+test_flags+['-parse-as-library','-emit-library','-module-name','LadderTests',*test_sources,'-o',executable])
    run([developer/'usr/bin/xctest',bundle])
