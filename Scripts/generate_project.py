"""Generate the checked-in Xcode project without third-party dependencies."""
from pathlib import Path
import hashlib, json
root = Path(__file__).resolve().parent.parent
objects = {}
def ident(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def obj(uid, isa, **kwargs):
    key = ident(uid); objects[key] = dict(isa=isa, **kwargs); return key
def ref(path, kind='sourcecode.swift', name=None):
    return obj('file:'+path, 'PBXFileReference', path=path, sourceTree='SOURCE_ROOT', lastKnownFileType=kind, **({'name':name} if name else {}))
def build(key, label, settings=None):
    return obj('build:'+label, 'PBXBuildFile', fileRef=key, **({'settings':settings} if settings else {}))
def phase(name, isa, files):
    return obj(name, isa, buildActionMask=2147483647, files=files, runOnlyForDeploymentPostprocessing=0)
core_files = [ref(str(p.relative_to(root))) for p in sorted((root/'Sources/LadderCore').glob('*.swift'))]
app_files = [ref(str(p.relative_to(root))) for p in sorted((root/'Sources/OpenLadderStudio').rglob('*.swift'))]
test_files = [ref(str(p.relative_to(root))) for p in sorted((root/'Tests/LadderCoreTests').glob('*.swift'))]
app_tests = [ref(str(p.relative_to(root))) for p in sorted((root/'Tests/LadderAppTests').glob('*.swift'))]
products = {
 'core':obj('product:core','PBXFileReference',explicitFileType='wrapper.framework',path='LadderCore.framework',sourceTree='BUILT_PRODUCTS_DIR'),
 'app':obj('product:app','PBXFileReference',explicitFileType='wrapper.application',path='Open Ladder Studio.app',sourceTree='BUILT_PRODUCTS_DIR'),
 'tests':obj('product:tests','PBXFileReference',explicitFileType='wrapper.cfbundle',path='LadderCoreTests.xctest',sourceTree='BUILT_PRODUCTS_DIR'),
 'apptests':obj('product:apptests','PBXFileReference',explicitFileType='wrapper.cfbundle',path='LadderAppTests.xctest',sourceTree='BUILT_PRODUCTS_DIR')}
localizations = [obj('localization:'+lang,'PBXFileReference',lastKnownFileType='text.plist.strings',name=lang,path=f'Sources/OpenLadderStudio/Resources/{lang}.lproj/Localizable.strings',sourceTree='SOURCE_ROOT') for lang in ['en','ja']]
localized = obj('localizable','PBXVariantGroup',children=localizations,name='Localizable.strings',sourceTree='<group>')
resources = [localized, ref('Examples','folder'), ref('Sources/OpenLadderStudio/Resources/AppIcon.icns','image.icns')]
info = ref('Sources/OpenLadderStudio/Info.plist','text.plist.xml')
entitlements = ref('Sources/OpenLadderStudio/OpenLadderStudio.entitlements','text.plist.entitlements')
groups = [obj('group:'+name,'PBXGroup',children=children,name=name,sourceTree='<group>') for name,children in [('LadderCore',core_files),('OpenLadderStudio',app_files+[info,entitlements]),('Tests',test_files+app_tests),('Resources',resources),('Products',list(products.values()))]]
main_group = obj('mainGroup','PBXGroup',children=groups,sourceTree='<group>')
common = dict(MACOSX_DEPLOYMENT_TARGET='14.0',SDKROOT='macosx',SWIFT_VERSION='6.0',CLANG_ENABLE_MODULES='YES',SWIFT_STRICT_CONCURRENCY='complete',ARCHS='arm64',CODE_SIGN_STYLE='Automatic',GCC_C_LANGUAGE_STANDARD='gnu17',CLANG_ENABLE_OBJC_ARC='YES',SWIFT_EMIT_LOC_STRINGS='NO')
def configs(name, settings):
    entries=[]
    for cfg in ['Debug','Release']:
        flags = dict(settings)
        flags.update(SWIFT_OPTIMIZATION_LEVEL='-Onone' if cfg=='Debug' else '-O',DEBUG_INFORMATION_FORMAT='dwarf' if cfg=='Debug' else 'dwarf-with-dsym')
        if cfg=='Debug': flags.update(ENABLE_TESTABILITY='YES',SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG',GCC_PREPROCESSOR_DEFINITIONS=['DEBUG=1','$(inherited)'])
        entries.append(obj(name+cfg,'XCBuildConfiguration',buildSettings=flags,name=cfg))
    return obj(name+'config','XCConfigurationList',buildConfigurations=entries,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
project_configs = configs('project', common)
targets={k:ident('target:'+k) for k in products}
project_id = ident('project')
def dependency(source, target):
    proxy=obj('proxy:'+source+target,'PBXContainerItemProxy',containerPortal=project_id,proxyType=1,remoteGlobalIDString=targets[target],remoteInfo=target)
    return obj('dep:'+source+target,'PBXTargetDependency',target=targets[target],targetProxy=proxy)
names={'app':'OpenLadderStudio','core':'LadderCore','tests':'LadderCoreTests','apptests':'LadderAppTests'}
for key, files in [('core',core_files),('app',app_files),('tests',test_files),('apptests',app_tests)]:
    sources=phase('sources:'+key,'PBXSourcesBuildPhase',[build(f,key+f) for f in files])
    links=[] if key=='core' else [build(products['core'],'link:'+key)]
    frameworks=phase('frameworks:'+key,'PBXFrameworksBuildPhase',links)
    phases=[sources,frameworks]
    if key=='app':
        phases.append(phase('resources:app','PBXResourcesBuildPhase',[build(f,'resource:'+f) for f in resources]))
        phases.append(obj('embed','PBXCopyFilesBuildPhase',buildActionMask=2147483647,dstPath='',dstSubfolderSpec=10,files=[build(products['core'],'embed:core',{'ATTRIBUTES':['CodeSignOnCopy','RemoveHeadersOnCopy']})],name='Embed Frameworks',runOnlyForDeploymentPostprocessing=0))
    settings=dict(PRODUCT_NAME=names[key],PRODUCT_BUNDLE_IDENTIFIER='studio.openladder.'+key,GENERATE_INFOPLIST_FILE='YES',LD_RUNPATH_SEARCH_PATHS=['$(inherited)','@executable_path/../Frameworks','@loader_path/../Frameworks'])
    if key=='core': settings.update(DEFINES_MODULE='YES',SKIP_INSTALL='YES',DYLIB_INSTALL_NAME_BASE='@rpath',INSTALL_PATH='$(LOCAL_LIBRARY_DIR)/Frameworks')
    if key=='app': settings.update(PRODUCT_NAME='Open Ladder Studio',PRODUCT_MODULE_NAME='OpenLadderStudio',GENERATE_INFOPLIST_FILE='NO',INFOPLIST_FILE='Sources/OpenLadderStudio/Info.plist',CODE_SIGN_ENTITLEMENTS='Sources/OpenLadderStudio/OpenLadderStudio.entitlements',ENABLE_HARDENED_RUNTIME='YES',ENABLE_APP_SANDBOX='YES',COMBINE_HIDPI_IMAGES='YES')
    if key=='apptests': settings.update(TEST_HOST='$(BUILT_PRODUCTS_DIR)/Open Ladder Studio.app/Contents/MacOS/Open Ladder Studio',BUNDLE_LOADER='$(TEST_HOST)')
    deps=[] if key=='core' else [dependency(key,'core')]
    if key=='apptests': deps.append(dependency(key,'app'))
    obj('target:'+key,'PBXNativeTarget',buildConfigurationList=configs(key,settings),buildPhases=phases,buildRules=[],dependencies=deps,name=names[key],productName=names[key],productReference=products[key],productType='com.apple.product-type.application' if key=='app' else 'com.apple.product-type.framework' if key=='core' else 'com.apple.product-type.bundle.unit-test')
obj('project','PBXProject',attributes={'BuildIndependentTargetsInParallel':'YES','LastSwiftUpdateCheck':'1600','LastUpgradeCheck':'1600','TargetAttributes':{targets[k]:{'CreatedOnToolsVersion':'16.0'} for k in targets}},buildConfigurationList=project_configs,compatibilityVersion='Xcode 14.0',developmentRegion='en',hasScannedForEncodings=0,knownRegions=['en','ja','Base'],mainGroup=main_group,productRefGroup=groups[-1],projectDirPath='',projectRoot='',targets=[targets[k] for k in ['app','core','tests','apptests']])
def emit(value, depth=0):
    if isinstance(value,dict): return '{\n'+'\n'.join('\t'*(depth+1)+f'{json.dumps(k)} = {emit(v,depth+1)};' for k,v in value.items())+'\n'+'\t'*depth+'}'
    if isinstance(value,list): return '( '+', '.join(emit(v,depth) for v in value)+' )'
    if isinstance(value,int): return str(value)
    return json.dumps(value,ensure_ascii=False)
(root/'OpenLadderStudio.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n'+emit({'archiveVersion':1,'classes':{},'objectVersion':56,'objects':objects,'rootObject':project_id})+'\n')
scheme=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{targets['app']}" BuildableName="Open Ladder Studio.app" BlueprintName="OpenLadderStudio" ReferencedContainer="container:OpenLadderStudio.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables>'''
for key in ['tests','apptests']:
    scheme+=f'<TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{targets[key]}" BuildableName="{names[key]}.xctest" BlueprintName="{names[key]}" ReferencedContainer="container:OpenLadderStudio.xcodeproj"/></TestableReference>'
scheme+='</Testables></TestAction>'
scheme+=f'''<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{targets['app']}" BuildableName="Open Ladder Studio.app" BlueprintName="OpenLadderStudio" ReferencedContainer="container:OpenLadderStudio.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>'''
(root/'OpenLadderStudio.xcodeproj/xcshareddata/xcschemes/OpenLadderStudio.xcscheme').write_text(scheme)
print('Generated Xcode project and shared scheme')
