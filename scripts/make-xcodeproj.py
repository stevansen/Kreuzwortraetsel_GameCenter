#!/usr/bin/env python3
"""Erzeugt Apps/Kreuzwort.xcodeproj von Hand.

Kein XcodeGen, kein Tuist, kein xcodeproj-Gem — die sind hier nicht installiert
und wären für ein einziges App-Target auch übertrieben. Das Projekt hat genau
eine Aufgabe: die App-Quellen unter Apps/Kreuzwort/ mit dem lokalen
Swift-Paket im Wurzelverzeichnis verbinden und für iOS, iPadOS und macOS bauen.

Die Bibliotheken selbst bleiben im Paket. Das Projekt referenziert sie über
XCLocalSwiftPackageReference, damit `swift build`/`swift test` und Xcode
dieselben Quellen sehen.

Reproduzierbar: die UUIDs sind aus stabilen Namen abgeleitet, ein erneuter Lauf
erzeugt dieselbe Datei.
"""
import hashlib, os, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
PROJECT_DIR = ROOT / "Apps" / "Kreuzwort.xcodeproj"
APP_SOURCES = sorted(p.name for p in (ROOT / "Apps" / "Kreuzwort").glob("*.swift"))
INFO_PLIST = "Info.plist"
PRODUCTS = ["PuzzleKit", "ClueCatalog", "KreuzwortUI", "SyncKit", "GameServices"]
BUNDLE_ID = "com.kreuzwort.app"
DEPLOY_IOS = "18.0"
DEPLOY_MAC = "15.0"
DEPLOY_TV = "18.0"


def uid(name: str) -> str:
    """Stabile 24-stellige Hex-ID aus einem Namen."""
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()


def main() -> None:
    ids = {k: uid(k) for k in [
        "project", "target", "mainGroup", "appGroup", "productsGroup", "frameworksGroup",
        "productRef", "sourcesPhase", "frameworksPhase", "resourcesPhase",
        "projectConfigList", "targetConfigList",
        "projectDebug", "projectRelease", "targetDebug", "targetRelease",
        "packageRef", "resourcesRef", "resourcesBuildFile",
        # Icon und Privacy-Manifest sind für die Einreichung Pflicht: ohne Icon
        # lehnt der Upload ab, ohne Manifest seit Mai 2024 die Prüfung.
        "assetsRef", "assetsBuildFile", "privacyRef", "privacyBuildFile",
        "copyDataPhase",
    ]}
    ids[f"file:{INFO_PLIST}"] = uid(f"file:{INFO_PLIST}")
    for name in APP_SOURCES:
        ids[f"file:{name}"] = uid(f"file:{name}")
        ids[f"build:{name}"] = uid(f"build:{name}")
    for product in PRODUCTS:
        ids[f"product:{product}"] = uid(f"product:{product}")
        ids[f"productBuild:{product}"] = uid(f"productBuild:{product}")

    L = []
    A = L.append
    A("// !$*UTF8*$!")
    A("{")
    A("\tarchiveVersion = 1;")
    A("\tclasses = {")
    A("\t};")
    A("\tobjectVersion = 56;")
    A("\tobjects = {")

    # --- PBXBuildFile ---
    A("\n/* Begin PBXBuildFile section */")
    for name in APP_SOURCES:
        A(f"\t\t{ids[f'build:{name}']} /* {name} in Sources */ = {{isa = PBXBuildFile; "
          f"fileRef = {ids[f'file:{name}']} /* {name} */; }};")
    for product in PRODUCTS:
        A(f"\t\t{ids[f'productBuild:{product}']} /* {product} in Frameworks */ = "
          f"{{isa = PBXBuildFile; productRef = {ids[f'product:{product}']} /* {product} */; }};")
    A(f"\t\t{ids['assetsBuildFile']} /* Assets.xcassets in Resources */ = "
      f"{{isa = PBXBuildFile; fileRef = {ids['assetsRef']} /* Assets.xcassets */; }};")
    A(f"\t\t{ids['privacyBuildFile']} /* PrivacyInfo.xcprivacy in Resources */ = "
      f"{{isa = PBXBuildFile; fileRef = {ids['privacyRef']} /* PrivacyInfo.xcprivacy */; }};")
    A("/* End PBXBuildFile section */")

    # --- PBXFileReference ---
    A("\n/* Begin PBXFileReference section */")
    A(f"\t\t{ids['productRef']} /* Kreuzwort.app */ = {{isa = PBXFileReference; "
      "explicitFileType = wrapper.application; includeInIndex = 0; "
      "path = Kreuzwort.app; sourceTree = BUILT_PRODUCTS_DIR; };")
    for name in APP_SOURCES:
        A(f"\t\t{ids[f'file:{name}']} /* {name} */ = {{isa = PBXFileReference; "
          f"lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = \"<group>\"; }};")
    A(f"\t\t{ids[f'file:{INFO_PLIST}']} /* {INFO_PLIST} */ = {{isa = PBXFileReference; "
      f"lastKnownFileType = text.plist.xml; path = {INFO_PLIST}; sourceTree = \"<group>\"; }};")
    A(f"\t\t{ids['assetsRef']} /* Assets.xcassets */ = {{isa = PBXFileReference; "
      "lastKnownFileType = folder.assetcatalog; path = Kreuzwort/Assets.xcassets; "
      "sourceTree = \"<group>\"; };")
    A(f"\t\t{ids['privacyRef']} /* PrivacyInfo.xcprivacy */ = {{isa = PBXFileReference; "
      "lastKnownFileType = text.plist.xml; path = Kreuzwort/PrivacyInfo.xcprivacy; "
      "sourceTree = \"<group>\"; };")
    A("/* End PBXFileReference section */")

    # --- PBXFrameworksBuildPhase ---
    A("\n/* Begin PBXFrameworksBuildPhase section */")
    A(f"\t\t{ids['frameworksPhase']} /* Frameworks */ = {{")
    A("\t\t\tisa = PBXFrameworksBuildPhase;")
    A("\t\t\tbuildActionMask = 2147483647;")
    A("\t\t\tfiles = (")
    for product in PRODUCTS:
        A(f"\t\t\t\t{ids[f'productBuild:{product}']} /* {product} in Frameworks */,")
    A("\t\t\t);")
    A("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    A("\t\t};")
    A("/* End PBXFrameworksBuildPhase section */")

    # --- PBXGroup ---
    A("\n/* Begin PBXGroup section */")
    A(f"\t\t{ids['mainGroup']} = {{")
    A("\t\t\tisa = PBXGroup;")
    A("\t\t\tchildren = (")
    A(f"\t\t\t\t{ids['appGroup']} /* Kreuzwort */,")
    A(f"\t\t\t\t{ids['assetsRef']} /* Assets.xcassets */,")
    A(f"\t\t\t\t{ids['privacyRef']} /* PrivacyInfo.xcprivacy */,")
    A(f"\t\t\t\t{ids['productsGroup']} /* Products */,")
    A("\t\t\t);")
    A("\t\t\tsourceTree = \"<group>\";")
    A("\t\t};")
    A(f"\t\t{ids['appGroup']} /* Kreuzwort */ = {{")
    A("\t\t\tisa = PBXGroup;")
    A("\t\t\tchildren = (")
    for name in APP_SOURCES:
        A(f"\t\t\t\t{ids[f'file:{name}']} /* {name} */,")
    A(f"\t\t\t\t{ids[f'file:{INFO_PLIST}']} /* {INFO_PLIST} */,")
    A("\t\t\t);")
    A("\t\t\tpath = Kreuzwort;")
    A("\t\t\tsourceTree = \"<group>\";")
    A("\t\t};")
    A(f"\t\t{ids['productsGroup']} /* Products */ = {{")
    A("\t\t\tisa = PBXGroup;")
    A("\t\t\tchildren = (")
    A(f"\t\t\t\t{ids['productRef']} /* Kreuzwort.app */,")
    A("\t\t\t);")
    A("\t\t\tname = Products;")
    A("\t\t\tsourceTree = \"<group>\";")
    A("\t\t};")
    A("/* End PBXGroup section */")

    # --- PBXNativeTarget ---
    A("\n/* Begin PBXNativeTarget section */")
    A(f"\t\t{ids['target']} /* Kreuzwort */ = {{")
    A("\t\t\tisa = PBXNativeTarget;")
    A(f"\t\t\tbuildConfigurationList = {ids['targetConfigList']};")
    A("\t\t\tbuildPhases = (")
    A(f"\t\t\t\t{ids['sourcesPhase']} /* Sources */,")
    A(f"\t\t\t\t{ids['frameworksPhase']} /* Frameworks */,")
    A(f"\t\t\t\t{ids['resourcesPhase']} /* Resources */,")
    A(f"\t\t\t\t{ids['copyDataPhase']} /* Daten kopieren */,")
    A("\t\t\t);")
    A("\t\t\tbuildRules = (")
    A("\t\t\t);")
    A("\t\t\tdependencies = (")
    A("\t\t\t);")
    A("\t\t\tname = Kreuzwort;")
    A("\t\t\tpackageProductDependencies = (")
    for product in PRODUCTS:
        A(f"\t\t\t\t{ids[f'product:{product}']} /* {product} */,")
    A("\t\t\t);")
    A("\t\t\tproductName = Kreuzwort;")
    A(f"\t\t\tproductReference = {ids['productRef']} /* Kreuzwort.app */;")
    A("\t\t\tproductType = \"com.apple.product-type.application\";")
    A("\t\t};")
    A("/* End PBXNativeTarget section */")

    # --- PBXProject ---
    A("\n/* Begin PBXProject section */")
    A(f"\t\t{ids['project']} /* Project object */ = {{")
    A("\t\t\tisa = PBXProject;")
    A("\t\t\tattributes = {")
    A("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    A("\t\t\t\tLastSwiftUpdateCheck = 2600;")
    A("\t\t\t\tLastUpgradeCheck = 2600;")
    A("\t\t\t\tTargetAttributes = {")
    A(f"\t\t\t\t\t{ids['target']} = {{")
    A("\t\t\t\t\t\tCreatedOnToolsVersion = 26.0;")
    A("\t\t\t\t\t};")
    A("\t\t\t\t};")
    A("\t\t\t};")
    A(f"\t\t\tbuildConfigurationList = {ids['projectConfigList']};")
    A("\t\t\tdevelopmentRegion = de;")
    A("\t\t\thasScannedForEncodings = 0;")
    A("\t\t\tknownRegions = (")
    for region in ["de", "en", "it", "Base"]:
        A(f"\t\t\t\t{region},")
    A("\t\t\t);")
    A(f"\t\t\tmainGroup = {ids['mainGroup']};")
    A("\t\t\tminimizedProjectReferenceProxies = 1;")
    A("\t\t\tpackageReferences = (")
    A(f"\t\t\t\t{ids['packageRef']} /* KreuzwortCore */,")
    A("\t\t\t);")
    A("\t\t\tpreferredProjectObjectVersion = 77;")
    A(f"\t\t\tproductRefGroup = {ids['productsGroup']} /* Products */;")
    A("\t\t\tprojectDirPath = \"\";")
    A("\t\t\tprojectRoot = \"\";")
    A("\t\t\ttargets = (")
    A(f"\t\t\t\t{ids['target']} /* Kreuzwort */,")
    A("\t\t\t);")
    A("\t\t};")
    A("/* End PBXProject section */")

    # --- PBXShellScriptBuildPhase: Daten ins Bundle ---
    #
    # Warum ein Skript und kein Ordnerverweis in der Resources-Phase: ein
    # Ordner mit dem Namen **Resources** im iOS-Bundle bringt codesign dazu,
    # die Dateien in der Bundle-Wurzel für eigenständigen Code zu halten. Der
    # Build scheiterte mit „code object is not signed at all / In subcomponent:
    # AppIcon60x60@2x.png" — nachweisbar: nimmt man den Ordner heraus, signiert
    # dasselbe Bundle sofort. Der Zielname ist deshalb „Data".
    #
    # Der zweite Grund, der schon für den Ordnerverweis galt, gilt weiter: der
    # Katalog ist ein generiertes 43-MB-Artefakt und liegt nicht im Git. Fehlt
    # er, warnt das Skript statt den Build zu brechen.
    A("\n/* Begin PBXShellScriptBuildPhase section */")
    A(f"\t\t{ids['copyDataPhase']} /* Daten kopieren */ = {{")
    A("\t\t\tisa = PBXShellScriptBuildPhase;")
    A("\t\t\talwaysOutOfDate = 1;")
    A("\t\t\tbuildActionMask = 2147483647;")
    A("\t\t\tfiles = (")
    A("\t\t\t);")
    A("\t\t\tinputPaths = (")
    A("\t\t\t);")
    A("\t\t\tname = \"Daten kopieren\";")
    A("\t\t\toutputPaths = (")
    A("\t\t\t);")
    A("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    A("\t\t\tshellPath = /bin/sh;")
    # pbxproj-Zeichenketten dürfen keine echten Zeilenumbrüche enthalten und
    # Anführungszeichen müssen maskiert sein — sonst ist die Datei unparsbar.
    # Der erste Versuch schrieb echte Umbrüche hinein und plutil verweigerte sie.
    script_lines = [
        "set -e",
        'SRC="$SRCROOT/../Resources"',
        'DST="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Data"',
        # Ein Ordner „Resources" aus einem älteren Build bleibt in DerivedData
        # liegen und löst denselben codesign-Fehler erneut aus. Er wird deshalb
        # bei jedem Build entfernt, nicht nur beim ersten.
        'rm -rf "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Resources"',
        'if [ -d "$SRC" ]; then',
        '  rm -rf "$DST"',
        '  mkdir -p "$DST"',
        '  rsync -a --exclude .DS_Store "$SRC/" "$DST/"',
        "else",
        '  echo "warning: $SRC fehlt - die App startet ohne Katalog"',
        "fi",
    ]
    escaped = "\\n".join(line.replace('"', '\\"') for line in script_lines) + "\\n"
    A(f'\t\t\tshellScript = "{escaped}";')
    A("\t\t};")
    A("/* End PBXShellScriptBuildPhase section */")

    # --- PBXResourcesBuildPhase ---
    A("\n/* Begin PBXResourcesBuildPhase section */")
    A(f"\t\t{ids['resourcesPhase']} /* Resources */ = {{")
    A("\t\t\tisa = PBXResourcesBuildPhase;")
    A("\t\t\tbuildActionMask = 2147483647;")
    A("\t\t\tfiles = (")
    A(f"\t\t\t\t{ids['assetsBuildFile']} /* Assets.xcassets in Resources */,")
    A(f"\t\t\t\t{ids['privacyBuildFile']} /* PrivacyInfo.xcprivacy in Resources */,")
    A("\t\t\t);")
    A("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    A("\t\t};")
    A("/* End PBXResourcesBuildPhase section */")

    # --- PBXSourcesBuildPhase ---
    A("\n/* Begin PBXSourcesBuildPhase section */")
    A(f"\t\t{ids['sourcesPhase']} /* Sources */ = {{")
    A("\t\t\tisa = PBXSourcesBuildPhase;")
    A("\t\t\tbuildActionMask = 2147483647;")
    A("\t\t\tfiles = (")
    for name in APP_SOURCES:
        A(f"\t\t\t\t{ids[f'build:{name}']} /* {name} in Sources */,")
    A("\t\t\t);")
    A("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    A("\t\t};")
    A("/* End PBXSourcesBuildPhase section */")

    # --- XCBuildConfiguration ---
    shared = [
        "CLANG_ENABLE_MODULES = YES",
        "CLANG_ENABLE_OBJC_ARC = YES",
        "ENABLE_STRICT_OBJC_MSGSEND = YES",
        "GCC_NO_COMMON_BLOCKS = YES",
        f"IPHONEOS_DEPLOYMENT_TARGET = {DEPLOY_IOS}",
        f"MACOSX_DEPLOYMENT_TARGET = {DEPLOY_MAC}",
        f"TVOS_DEPLOYMENT_TARGET = {DEPLOY_TV}",
        "SDKROOT = auto",
        # tvOS gehört dazu, seit die Fernseh-Oberfläche existiert: Fokus im
        # Gitter und Buchstaben auf dem Schirm. Ohne diesen Eintrag liesse sich
        # das gar nicht bauen, und der Store-Eintrag hat eine tvOS-Version.
        'SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx appletvos '
        'appletvsimulator"',
        "SUPPORTS_MACCATALYST = NO",
        "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO",
        "SWIFT_EMIT_LOC_STRINGS = YES",
        "SWIFT_VERSION = 6.0",
    ]
    target_shared = [
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor",
        "CODE_SIGN_STYLE = Automatic",
        # Team aus dem Developer-Account; ohne das signiert Xcode nicht und der
        # Upload nach App Store Connect ist nicht möglich.
        "DEVELOPMENT_TEAM = JF8N3J347R",
        # Getrennte Entitlements je Plattform: der Mac App Store verlangt die
        # Sandbox, iOS kennt sie nicht.
        '"CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]" = Kreuzwort/Kreuzwort.entitlements',
        '"CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*]" = Kreuzwort/Kreuzwort.entitlements',
        '"CODE_SIGN_ENTITLEMENTS[sdk=macosx*]" = Kreuzwort/Kreuzwort-macOS.entitlements',
        '"CODE_SIGN_ENTITLEMENTS[sdk=appletvos*]" = Kreuzwort/Kreuzwort.entitlements',
        '"CODE_SIGN_ENTITLEMENTS[sdk=appletvsimulator*]" = Kreuzwort/Kreuzwort.entitlements',
        "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon",
        # KREUZWORT_CLOUDKIT ist hier ABSICHTLICH nicht gesetzt. Der Schalter
        # gehört zusammen mit dem iCloud-Entitlement gesetzt: ohne Entitlement
        # trappt CKContainer(identifier:) und die App stürzt beim Start ab —
        # genau das ist im Simulator passiert. Kommt beides gemeinsam dazu, wenn
        # der CloudKit-Container steht und der Sync einmal wirklich lief.
        'SWIFT_ACTIVE_COMPILATION_CONDITIONS = "$(inherited)"',
        'CURRENT_PROJECT_VERSION = 1',
        "ENABLE_PREVIEWS = YES",
        "GENERATE_INFOPLIST_FILE = YES",
        # Eine eigene Info.plist als Basis: CFBundleURLTypes und
        # NSUserActivityTypes sind Arrays und über INFOPLIST_KEY_* nicht
        # ausdrückbar. Xcode mischt die übrigen Schlüssel weiterhin hinein.
        'INFOPLIST_FILE = Kreuzwort/Info.plist',
        'INFOPLIST_KEY_CFBundleDisplayName = Kreuzwort',
        'INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.puzzle-games"',
        'INFOPLIST_KEY_NSHumanReadableCopyright = ""',
        "INFOPLIST_KEY_UILaunchScreen_Generation = YES",
        'INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = '
        '"UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown '
        'UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"',
        'INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = '
        '"UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft '
        'UIInterfaceOrientationLandscapeRight"',
        'LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks '
        '@executable_path/../Frameworks"',
        "MARKETING_VERSION = 1.0",
        f'PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID}',
        'PRODUCT_NAME = "$(TARGET_NAME)"',
        "SWIFT_APPROACHABLE_CONCURRENCY = YES",
        "SWIFT_EMIT_LOC_STRINGS = YES",
        # 1 iPhone, 2 iPad, 3 Apple TV. Ohne die 3 bietet Xcode keine
        # tvOS-Ziele an — SUPPORTED_PLATFORMS allein genügt nicht, das Ziel
        # blieb mit „Unable to find a destination" unauffindbar.
        'TARGETED_DEVICE_FAMILY = "1,2,3"',
    ]

    def config(uid_key, name, extra, is_target):
        A(f"\t\t{ids[uid_key]} /* {name} */ = {{")
        A("\t\t\tisa = XCBuildConfiguration;")
        A("\t\t\tbuildSettings = {")
        for line in sorted((target_shared if is_target else shared) + extra):
            A(f"\t\t\t\t{line};")
        A("\t\t\t};")
        A(f"\t\t\tname = {name};")
        A("\t\t};")

    A("\n/* Begin XCBuildConfiguration section */")
    config("projectDebug", "Debug", [
        "DEBUG_INFORMATION_FORMAT = dwarf",
        "ENABLE_TESTABILITY = YES",
        "GCC_OPTIMIZATION_LEVEL = 0",
        'GCC_PREPROCESSOR_DEFINITIONS = "DEBUG=1 $(inherited)"',
        "ONLY_ACTIVE_ARCH = YES",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS = "
        '"DEBUG $(inherited)"',
        "SWIFT_OPTIMIZATION_LEVEL = \"-Onone\"",
    ], False)
    config("projectRelease", "Release", [
        'DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym"',
        "ENABLE_NS_ASSERTIONS = NO",
        "SWIFT_COMPILATION_MODE = wholemodule",
    ], False)
    config("targetDebug", "Debug", [], True)
    config("targetRelease", "Release", [], True)
    A("/* End XCBuildConfiguration section */")

    # --- XCConfigurationList ---
    A("\n/* Begin XCConfigurationList section */")
    for key, debug, release, label in [
        ("projectConfigList", "projectDebug", "projectRelease", "PBXProject"),
        ("targetConfigList", "targetDebug", "targetRelease", "PBXNativeTarget"),
    ]:
        A(f"\t\t{ids[key]} /* Build configuration list for {label} */ = {{")
        A("\t\t\tisa = XCConfigurationList;")
        A("\t\t\tbuildConfigurations = (")
        A(f"\t\t\t\t{ids[debug]} /* Debug */,")
        A(f"\t\t\t\t{ids[release]} /* Release */,")
        A("\t\t\t);")
        A("\t\t\tdefaultConfigurationIsVisible = 0;")
        A("\t\t\tdefaultConfigurationName = Release;")
        A("\t\t};")
    A("/* End XCConfigurationList section */")

    # --- XCLocalSwiftPackageReference ---
    A("\n/* Begin XCLocalSwiftPackageReference section */")
    A(f"\t\t{ids['packageRef']} /* KreuzwortCore */ = {{")
    A("\t\t\tisa = XCLocalSwiftPackageReference;")
    A("\t\t\trelativePath = ..;")
    A("\t\t};")
    A("/* End XCLocalSwiftPackageReference section */")

    # --- XCSwiftPackageProductDependency ---
    A("\n/* Begin XCSwiftPackageProductDependency section */")
    for product in PRODUCTS:
        A(f"\t\t{ids[f'product:{product}']} /* {product} */ = {{")
        A("\t\t\tisa = XCSwiftPackageProductDependency;")
        A(f"\t\t\tproductName = {product};")
        A("\t\t};")
    A("/* End XCSwiftPackageProductDependency section */")

    A("\t};")
    A(f"\trootObject = {ids['project']} /* Project object */;")
    A("}")

    PROJECT_DIR.mkdir(parents=True, exist_ok=True)
    (PROJECT_DIR / "project.pbxproj").write_text("\n".join(L) + "\n")

    # Ein geteiltes Schema, damit `xcodebuild -scheme Kreuzwort` ohne Xcode-Start geht.
    schemes = PROJECT_DIR / "xcshareddata" / "xcschemes"
    schemes.mkdir(parents=True, exist_ok=True)
    (schemes / "Kreuzwort.xcscheme").write_text(f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.7">
   <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting="YES" buildForRunning="YES"
                           buildForProfiling="YES" buildForArchiving="YES"
                           buildForAnalyzing="YES">
            <BuildableReference BuildableIdentifier="primary"
               BlueprintIdentifier="{ids['target']}"
               BuildableName="Kreuzwort.app" BlueprintName="Kreuzwort"
               ReferencedContainer="container:Kreuzwort.xcodeproj"/>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0"
      useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO"
      debugDocumentVersioning="YES" debugServiceExtension="internal"
      allowLocationSimulation="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
         <BuildableReference BuildableIdentifier="primary"
            BlueprintIdentifier="{ids['target']}"
            BuildableName="Kreuzwort.app" BlueprintName="Kreuzwort"
            ReferencedContainer="container:Kreuzwort.xcodeproj"/>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES"
      savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
         <BuildableReference BuildableIdentifier="primary"
            BlueprintIdentifier="{ids['target']}"
            BuildableName="Kreuzwort.app" BlueprintName="Kreuzwort"
            ReferencedContainer="container:Kreuzwort.xcodeproj"/>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration="Debug"/>
   <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
""")
    print(f"Apps/Kreuzwort.xcodeproj erzeugt — {len(APP_SOURCES)} Quelldateien, "
          f"{len(PRODUCTS)} Paketprodukte")


if __name__ == "__main__":
    main()
