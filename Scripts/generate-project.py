#!/usr/bin/env python3
"""Generates MultiSet AR.xcodeproj with both targets.

Hand-authoring a pbxproj is error-prone, so it is generated from a declarative
description instead and verified by actually building. Re-run after adding or
removing source files:

    python3 Scripts/generate-project.py
"""

import hashlib
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT_NAME = "MultiSet AR"

# Package products the two targets link. The Clip deliberately omits nothing
# here — it is MultiSetSDK.xcframework that it must not link, and that is
# attached to the app target only, further down.
LOCAL_PACKAGES = ["MultiSetKit", "MultiSetUI", "MultiSetARCore", "MultiSetVPS"]

# Nothing is app-only any more: the VPS engine is a source package driven by a
# bearer token, so the Clip can link exactly what the app does.
APP_ONLY_PACKAGES: dict[str, str] = {}

_used_ids = set()


def gid(*parts):
    """Stable 24-hex identifier derived from the given key."""
    key = "\u0000".join(parts)
    digest = hashlib.sha256(key.encode()).hexdigest()[:24].upper()
    while digest in _used_ids:
        digest = hashlib.sha256((key + "!").encode()).hexdigest()[:24].upper()
        key += "!"
    _used_ids.add(digest)
    return digest


def swift_sources(relative_dir):
    """Every .swift file under a directory, sorted for a stable project file."""
    found = []
    absolute = os.path.join(ROOT, relative_dir)
    for directory, _, files in os.walk(absolute):
        for name in sorted(files):
            if name.endswith(".swift"):
                path = os.path.relpath(os.path.join(directory, name), ROOT)
                found.append(path)
    return sorted(found)


APP_SOURCES = swift_sources("App")
CLIP_SOURCES = swift_sources("Clip")

# The photographic imagery lives inside App/Resources/Assets.xcassets under
# Onboarding/ and Learn/. A second catalog invited exactly the target-membership
# mistake that would push content assets into the Clip, so there is only one.
APP_RESOURCES = ["App/Resources/Assets.xcassets", "App/Resources/PrivacyInfo.xcprivacy"]
CLIP_RESOURCES = ["Clip/Assets.xcassets", "Clip/PrivacyInfo.xcprivacy"]

XCCONFIGS = [
    "Config/Shared.xcconfig",
    "Config/Debug.xcconfig",
    "Config/Release.xcconfig",
    "Config/App.xcconfig",
    "Config/Clip.xcconfig",
]

OTHER_FILES = [
    "App/Resources/Info.plist",
    "App/Resources/MultiSetAR.entitlements",
    "Clip/Info.plist",
    "Clip/MultiSetARClip.entitlements",
]

# ---------------------------------------------------------------- identifiers

PROJECT = gid("project")
MAIN_GROUP = gid("group", "main")
PRODUCTS_GROUP = gid("group", "products")
FRAMEWORKS_GROUP = gid("group", "frameworks")

APP_TARGET = gid("target", "app")
CLIP_TARGET = gid("target", "clip")
APP_PRODUCT = gid("product", "app")
CLIP_PRODUCT = gid("product", "clip")

CONFIG_LIST_PROJECT = gid("configlist", "project")
CONFIG_LIST_APP = gid("configlist", "app")
CONFIG_LIST_CLIP = gid("configlist", "clip")

CLIP_EMBED_BUILD = gid("build", "embed-clip")

file_refs = {}
groups = {}
lines = []


def emit(text=""):
    lines.append(text)


def file_ref(path, explicit_type=None):
    if path in file_refs:
        return file_refs[path]
    identifier = gid("file", path)
    file_refs[path] = identifier
    return identifier


def file_type(path):
    if path.endswith(".swift"):
        return "sourcecode.swift"
    if path.endswith(".xcassets"):
        return "folder.assetcatalog"
    if path.endswith(".xcprivacy"):
        return "text.plist.xml"
    if path.endswith(".plist"):
        return "text.plist.xml"
    if path.endswith(".entitlements"):
        return "text.plist.entitlements"
    if path.endswith(".xcconfig"):
        return "text.xcconfig"
    if path.endswith(".xcframework"):
        return "wrapper.xcframework"
    return "text"


# ------------------------------------------------------------------ file tree

ALL_PATHS = sorted(
    set(APP_SOURCES + CLIP_SOURCES + APP_RESOURCES + CLIP_RESOURCES + XCCONFIGS + OTHER_FILES)
)
for path in ALL_PATHS:
    file_ref(path)


def build_tree(paths):
    """Nested dict mirroring the directory layout, so Xcode shows real folders."""
    tree = {}
    for path in paths:
        parts = path.split("/")
        node = tree
        for part in parts[:-1]:
            node = node.setdefault(part, {})
        node.setdefault("__files__", []).append(path)
    return tree


TREE = build_tree(ALL_PATHS)


def group_identifier(prefix):
    return gid("group", prefix or "root")


def emit_groups(node, prefix, identifier):
    children = []
    for name in sorted(k for k in node if k != "__files__"):
        child_prefix = f"{prefix}/{name}" if prefix else name
        child_id = group_identifier(child_prefix)
        children.append((child_id, name))
        emit_groups(node[name], child_prefix, child_id)
    files = sorted(node.get("__files__", []))
    groups[identifier] = {
        "name": prefix.split("/")[-1] if prefix else None,
        "path": prefix.split("/")[-1] if prefix else None,
        "children": children,
        "files": files,
    }


ROOT_GROUP_ID = group_identifier("")
emit_groups(TREE, "", ROOT_GROUP_ID)

# ------------------------------------------------------------ build file rows

build_files = {}


def build_file(path, target_key):
    key = (path, target_key)
    if key in build_files:
        return build_files[key]
    identifier = gid("build", target_key, path)
    build_files[key] = identifier
    return identifier


for path in APP_SOURCES:
    build_file(path, "app")
for path in CLIP_SOURCES:
    build_file(path, "clip")
for path in APP_RESOURCES:
    build_file(path, "app")
for path in CLIP_RESOURCES:
    build_file(path, "clip")

# --------------------------------------------------------------- package refs

package_paths = {name: f"Packages/{name}" for name in LOCAL_PACKAGES}
package_paths.update({name: path for name, path in APP_ONLY_PACKAGES.items()})

APP_PACKAGES = LOCAL_PACKAGES + list(APP_ONLY_PACKAGES)
CLIP_PACKAGES = LOCAL_PACKAGES

package_refs = {}
product_deps = {}
package_build_files = {}
for name in APP_PACKAGES:
    package_refs[name] = gid("packageref", name)
for target_key, names in (("app", APP_PACKAGES), ("clip", CLIP_PACKAGES)):
    for name in names:
        product_deps[(name, target_key)] = gid("productdep", name, target_key)
        package_build_files[(name, target_key)] = gid("packagebuild", name, target_key)

# ----------------------------------------------------------------- emit start

emit("// !$*UTF8*$!")
emit("{")
emit("\tarchiveVersion = 1;")
emit("\tclasses = {")
emit("\t};")
emit("\tobjectVersion = 77;")
emit("\tobjects = {")
emit()

# PBXBuildFile
emit("/* Begin PBXBuildFile section */")
for (path, target_key), identifier in sorted(build_files.items(), key=lambda item: item[1]):
    ref = file_refs[path]
    name = path.split("/")[-1]
    emit(
        f"\t\t{identifier} /* {name} in {target_key} */ = {{isa = PBXBuildFile; "
        f"fileRef = {ref} /* {name} */; }};"
    )
for (name, target_key), identifier in sorted(package_build_files.items(), key=lambda item: item[1]):
    dep = product_deps[(name, target_key)]
    emit(
        f"\t\t{identifier} /* {name} in {target_key} */ = {{isa = PBXBuildFile; "
        f"productRef = {dep} /* {name} */; }};"
    )
emit(
    f"\t\t{CLIP_EMBED_BUILD} /* MultiSet AR Clip.app in Embed App Clips */ = {{isa = PBXBuildFile; "
    f"fileRef = {CLIP_PRODUCT} /* MultiSet AR Clip.app */; "
    f"settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};"
)
emit("/* End PBXBuildFile section */")
emit()

# PBXFileReference
emit("/* Begin PBXFileReference section */")
for path, identifier in sorted(file_refs.items(), key=lambda item: item[1]):
    name = path.split("/")[-1]
    emit(
        f'\t\t{identifier} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {file_type(path)}; '
        f'path = "{name}"; sourceTree = "<group>"; }};'
    )
emit(
    f'\t\t{APP_PRODUCT} /* MultiSet AR.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; '
    f'includeInIndex = 0; path = "MultiSet AR.app"; sourceTree = BUILT_PRODUCTS_DIR; }};'
)
emit(
    f'\t\t{CLIP_PRODUCT} /* MultiSet AR Clip.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; '
    f'includeInIndex = 0; path = "MultiSet AR Clip.app"; sourceTree = BUILT_PRODUCTS_DIR; }};'
)
emit("/* End PBXFileReference section */")
emit()

# PBXGroup
emit("/* Begin PBXGroup section */")
for identifier, group in sorted(groups.items()):
    children = []
    for child_id, child_name in group["children"]:
        children.append(f"\t\t\t\t{child_id} /* {child_name} */,")
    for path in group["files"]:
        children.append(f"\t\t\t\t{file_refs[path]} /* {path.split('/')[-1]} */,")
    if identifier == ROOT_GROUP_ID:
        children.append(f"\t\t\t\t{PRODUCTS_GROUP} /* Products */,")
    emit(f"\t\t{identifier} /* {group['name'] or PROJECT_NAME} */ = {{")
    emit("\t\t\tisa = PBXGroup;")
    emit("\t\t\tchildren = (")
    for child in children:
        emit(child)
    emit("\t\t\t);")
    if group["path"]:
        emit(f'\t\t\tpath = "{group["path"]}";')
    emit('\t\t\tsourceTree = "<group>";')
    emit("\t\t};")

emit(f"\t\t{PRODUCTS_GROUP} /* Products */ = {{")
emit("\t\t\tisa = PBXGroup;")
emit("\t\t\tchildren = (")
emit(f"\t\t\t\t{APP_PRODUCT} /* MultiSet AR.app */,")
emit(f"\t\t\t\t{CLIP_PRODUCT} /* MultiSet AR Clip.app */,")
emit("\t\t\t);")
emit("\t\t\tname = Products;")
emit('\t\t\tsourceTree = "<group>";')
emit("\t\t};")
emit("/* End PBXGroup section */")
emit()

# PBXFrameworksBuildPhase
APP_FRAMEWORKS_PHASE = gid("phase", "app", "frameworks")
CLIP_FRAMEWORKS_PHASE = gid("phase", "clip", "frameworks")
emit("/* Begin PBXFrameworksBuildPhase section */")
emit(f"\t\t{APP_FRAMEWORKS_PHASE} /* Frameworks */ = {{")
emit("\t\t\tisa = PBXFrameworksBuildPhase;")
emit("\t\t\tbuildActionMask = 2147483647;")
emit("\t\t\tfiles = (")
for name in APP_PACKAGES:
    emit(f"\t\t\t\t{package_build_files[(name, 'app')]} /* {name} */,")
emit("\t\t\t);")
emit("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
emit("\t\t};")
emit(f"\t\t{CLIP_FRAMEWORKS_PHASE} /* Frameworks */ = {{")
emit("\t\t\tisa = PBXFrameworksBuildPhase;")
emit("\t\t\tbuildActionMask = 2147483647;")
emit("\t\t\tfiles = (")
for name in CLIP_PACKAGES:
    emit(f"\t\t\t\t{package_build_files[(name, 'clip')]} /* {name} */,")
emit("\t\t\t);")
emit("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
emit("\t\t};")
emit("/* End PBXFrameworksBuildPhase section */")
emit()

# PBXSourcesBuildPhase
APP_SOURCES_PHASE = gid("phase", "app", "sources")
CLIP_SOURCES_PHASE = gid("phase", "clip", "sources")
emit("/* Begin PBXSourcesBuildPhase section */")
for phase_id, sources, target_key in (
    (APP_SOURCES_PHASE, APP_SOURCES, "app"),
    (CLIP_SOURCES_PHASE, CLIP_SOURCES, "clip"),
):
    emit(f"\t\t{phase_id} /* Sources */ = {{")
    emit("\t\t\tisa = PBXSourcesBuildPhase;")
    emit("\t\t\tbuildActionMask = 2147483647;")
    emit("\t\t\tfiles = (")
    for path in sources:
        emit(f"\t\t\t\t{build_files[(path, target_key)]} /* {path.split('/')[-1]} */,")
    emit("\t\t\t);")
    emit("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    emit("\t\t};")
emit("/* End PBXSourcesBuildPhase section */")
emit()

# PBXResourcesBuildPhase
APP_RESOURCES_PHASE = gid("phase", "app", "resources")
CLIP_RESOURCES_PHASE = gid("phase", "clip", "resources")
emit("/* Begin PBXResourcesBuildPhase section */")
for phase_id, resources, target_key in (
    (APP_RESOURCES_PHASE, APP_RESOURCES, "app"),
    (CLIP_RESOURCES_PHASE, CLIP_RESOURCES, "clip"),
):
    emit(f"\t\t{phase_id} /* Resources */ = {{")
    emit("\t\t\tisa = PBXResourcesBuildPhase;")
    emit("\t\t\tbuildActionMask = 2147483647;")
    emit("\t\t\tfiles = (")
    for path in resources:
        emit(f"\t\t\t\t{build_files[(path, target_key)]} /* {path.split('/')[-1]} */,")
    emit("\t\t\t);")
    emit("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    emit("\t\t};")
emit("/* End PBXResourcesBuildPhase section */")
emit()

# PBXCopyFilesBuildPhase — embed the framework and the Clip
EMBED_CLIP_PHASE = gid("phase", "app", "embed-clip")
emit("/* Begin PBXCopyFilesBuildPhase section */")
emit(f"\t\t{EMBED_CLIP_PHASE} /* Embed App Clips */ = {{")
emit("\t\t\tisa = PBXCopyFilesBuildPhase;")
emit("\t\t\tbuildActionMask = 2147483647;")
emit('\t\t\tdstPath = "$(CONTENTS_FOLDER_PATH)/AppClips";')
emit("\t\t\tdstSubfolderSpec = 16;")
emit("\t\t\tfiles = (")
emit(f"\t\t\t\t{CLIP_EMBED_BUILD} /* MultiSet AR Clip.app in Embed App Clips */,")
emit("\t\t\t);")
emit('\t\t\tname = "Embed App Clips";')
emit("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
emit("\t\t};")
emit("/* End PBXCopyFilesBuildPhase section */")
emit()

# PBXTargetDependency
CLIP_DEPENDENCY = gid("dependency", "clip")
CLIP_CONTAINER_PROXY = gid("proxy", "clip")
emit("/* Begin PBXTargetDependency section */")
emit(f"\t\t{CLIP_DEPENDENCY} /* PBXTargetDependency */ = {{")
emit("\t\t\tisa = PBXTargetDependency;")
emit(f'\t\t\ttarget = {CLIP_TARGET} /* MultiSet AR Clip */;')
emit(f"\t\t\ttargetProxy = {CLIP_CONTAINER_PROXY} /* PBXContainerItemProxy */;")
emit("\t\t};")
emit("/* End PBXTargetDependency section */")
emit()

emit("/* Begin PBXContainerItemProxy section */")
emit(f"\t\t{CLIP_CONTAINER_PROXY} /* PBXContainerItemProxy */ = {{")
emit("\t\t\tisa = PBXContainerItemProxy;")
emit(f"\t\t\tcontainerPortal = {PROJECT} /* Project object */;")
emit("\t\t\tproxyType = 1;")
emit(f"\t\t\tremoteGlobalIDString = {CLIP_TARGET};")
emit('\t\t\tremoteInfo = "MultiSet AR Clip";')
emit("\t\t};")
emit("/* End PBXContainerItemProxy section */")
emit()

# XCBuildConfiguration
CONFIGS = {}
for scope, base_config in (("project", None), ("app", "Config/App.xcconfig"), ("clip", "Config/Clip.xcconfig")):
    for name in ("Debug", "Release"):
        CONFIGS[(scope, name)] = gid("config", scope, name)

emit("/* Begin XCBuildConfiguration section */")
for (scope, name), identifier in sorted(CONFIGS.items(), key=lambda item: item[1]):
    emit(f"\t\t{identifier} /* {name} */ = {{")
    emit("\t\t\tisa = XCBuildConfiguration;")
    if scope == "project":
        base = f"Config/{name}.xcconfig"
        emit(f"\t\t\tbaseConfigurationReference = {file_refs[base]} /* {name}.xcconfig */;")
    else:
        base = "Config/App.xcconfig" if scope == "app" else "Config/Clip.xcconfig"
        emit(f'\t\t\tbaseConfigurationReference = {file_refs[base]} /* {base.split("/")[-1]} */;')
    emit("\t\t\tbuildSettings = {")
    if scope == "clip":
        # PRODUCT_NAME is set in Clip.xcconfig; nothing to override here.
        pass
    emit("\t\t\t};")
    emit(f"\t\t\tname = {name};")
    emit("\t\t};")
emit("/* End XCBuildConfiguration section */")
emit()

# XCConfigurationList
emit("/* Begin XCConfigurationList section */")
for scope, identifier in (
    ("project", CONFIG_LIST_PROJECT),
    ("app", CONFIG_LIST_APP),
    ("clip", CONFIG_LIST_CLIP),
):
    emit(f"\t\t{identifier} /* Build configuration list */ = {{")
    emit("\t\t\tisa = XCConfigurationList;")
    emit("\t\t\tbuildConfigurations = (")
    emit(f"\t\t\t\t{CONFIGS[(scope, 'Debug')]} /* Debug */,")
    emit(f"\t\t\t\t{CONFIGS[(scope, 'Release')]} /* Release */,")
    emit("\t\t\t);")
    emit("\t\t\tdefaultConfigurationIsVisible = 0;")
    emit("\t\t\tdefaultConfigurationName = Release;")
    emit("\t\t};")
emit("/* End XCConfigurationList section */")
emit()

# XCLocalSwiftPackageReference
emit("/* Begin XCLocalSwiftPackageReference section */")
for name, identifier in sorted(package_refs.items(), key=lambda item: item[1]):
    emit(f'\t\t{identifier} /* XCLocalSwiftPackageReference "{package_paths[name]}" */ = {{')
    emit("\t\t\tisa = XCLocalSwiftPackageReference;")
    emit(f'\t\t\trelativePath = "{package_paths[name]}";')
    emit("\t\t};")
emit("/* End XCLocalSwiftPackageReference section */")
emit()

# XCSwiftPackageProductDependency
emit("/* Begin XCSwiftPackageProductDependency section */")
for (name, target_key), identifier in sorted(product_deps.items(), key=lambda item: item[1]):
    emit(f"\t\t{identifier} /* {name} */ = {{")
    emit("\t\t\tisa = XCSwiftPackageProductDependency;")
    emit(f"\t\t\tproductName = {name};")
    emit("\t\t};")
emit("/* End XCSwiftPackageProductDependency section */")
emit()

# PBXNativeTarget
emit("/* Begin PBXNativeTarget section */")
emit(f'\t\t{APP_TARGET} /* MultiSet AR */ = {{')
emit("\t\t\tisa = PBXNativeTarget;")
emit(f"\t\t\tbuildConfigurationList = {CONFIG_LIST_APP} /* Build configuration list */;")
emit("\t\t\tbuildPhases = (")
emit(f"\t\t\t\t{APP_SOURCES_PHASE} /* Sources */,")
emit(f"\t\t\t\t{APP_FRAMEWORKS_PHASE} /* Frameworks */,")
emit(f"\t\t\t\t{APP_RESOURCES_PHASE} /* Resources */,")
emit(f"\t\t\t\t{EMBED_CLIP_PHASE} /* Embed App Clips */,")
emit("\t\t\t);")
emit("\t\t\tbuildRules = (")
emit("\t\t\t);")
emit("\t\t\tdependencies = (")
emit(f"\t\t\t\t{CLIP_DEPENDENCY} /* PBXTargetDependency */,")
emit("\t\t\t);")
emit('\t\t\tname = "MultiSet AR";')
emit("\t\t\tpackageProductDependencies = (")
for name in APP_PACKAGES:
    emit(f"\t\t\t\t{product_deps[(name, 'app')]} /* {name} */,")
emit("\t\t\t);")
emit('\t\t\tproductName = "MultiSet AR";')
emit(f'\t\t\tproductReference = {APP_PRODUCT} /* MultiSet AR.app */;')
emit("\t\t\tproductType = \"com.apple.product-type.application\";")
emit("\t\t};")

emit(f'\t\t{CLIP_TARGET} /* MultiSet AR Clip */ = {{')
emit("\t\t\tisa = PBXNativeTarget;")
emit(f"\t\t\tbuildConfigurationList = {CONFIG_LIST_CLIP} /* Build configuration list */;")
emit("\t\t\tbuildPhases = (")
emit(f"\t\t\t\t{CLIP_SOURCES_PHASE} /* Sources */,")
emit(f"\t\t\t\t{CLIP_FRAMEWORKS_PHASE} /* Frameworks */,")
emit(f"\t\t\t\t{CLIP_RESOURCES_PHASE} /* Resources */,")
emit("\t\t\t);")
emit("\t\t\tbuildRules = (")
emit("\t\t\t);")
emit("\t\t\tdependencies = (")
emit("\t\t\t);")
emit('\t\t\tname = "MultiSet AR Clip";')
emit("\t\t\tpackageProductDependencies = (")
for name in CLIP_PACKAGES:
    emit(f"\t\t\t\t{product_deps[(name, 'clip')]} /* {name} */,")
emit("\t\t\t);")
emit('\t\t\tproductName = "MultiSet AR Clip";')
emit(f'\t\t\tproductReference = {CLIP_PRODUCT} /* MultiSet AR Clip.app */;')
emit('\t\t\tproductType = "com.apple.product-type.application.on-demand-install-capable";')
emit("\t\t};")
emit("/* End PBXNativeTarget section */")
emit()

# PBXProject
emit("/* Begin PBXProject section */")
emit(f"\t\t{PROJECT} /* Project object */ = {{")
emit("\t\t\tisa = PBXProject;")
emit("\t\t\tattributes = {")
emit("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
emit("\t\t\t\tLastSwiftUpdateCheck = 2660;")
emit("\t\t\t\tLastUpgradeCheck = 2660;")
emit("\t\t\t\tTargetAttributes = {")
emit(f"\t\t\t\t\t{APP_TARGET} = {{")
emit("\t\t\t\t\t\tCreatedOnToolsVersion = 26.6;")
emit("\t\t\t\t\t};")
emit(f"\t\t\t\t\t{CLIP_TARGET} = {{")
emit("\t\t\t\t\t\tCreatedOnToolsVersion = 26.6;")
emit("\t\t\t\t\t};")
emit("\t\t\t\t};")
emit("\t\t\t};")
emit(f"\t\t\tbuildConfigurationList = {CONFIG_LIST_PROJECT} /* Build configuration list */;")
emit("\t\t\tpreferredProjectObjectVersion = 77;")
emit("\t\t\tdevelopmentRegion = en;")
emit("\t\t\thasScannedForEncodings = 0;")
emit("\t\t\tknownRegions = (")
emit("\t\t\t\ten,")
emit("\t\t\t\tBase,")
emit("\t\t\t);")
emit(f"\t\t\tmainGroup = {ROOT_GROUP_ID};")
emit("\t\t\tpackageReferences = (")
for name in APP_PACKAGES:
    emit(f'\t\t\t\t{package_refs[name]} /* XCLocalSwiftPackageReference "{package_paths[name]}" */,')
emit("\t\t\t);")
emit(f"\t\t\tproductRefGroup = {PRODUCTS_GROUP} /* Products */;")
emit('\t\t\tprojectDirPath = "";')
emit('\t\t\tprojectRoot = "";')
emit("\t\t\ttargets = (")
emit(f'\t\t\t\t{APP_TARGET} /* MultiSet AR */,')
emit(f'\t\t\t\t{CLIP_TARGET} /* MultiSet AR Clip */,')
emit("\t\t\t);")
emit("\t\t};")
emit("/* End PBXProject section */")
emit()

emit("\t};")
emit(f"\trootObject = {PROJECT} /* Project object */;")
emit("}")

project_dir = os.path.join(ROOT, f"{PROJECT_NAME}.xcodeproj")
os.makedirs(project_dir, exist_ok=True)
with open(os.path.join(project_dir, "project.pbxproj"), "w") as handle:
    handle.write("\n".join(lines) + "\n")

print(f"wrote {PROJECT_NAME}.xcodeproj/project.pbxproj")
print(f"  app target:  {len(APP_SOURCES)} swift files")
print(f"  clip target: {len(CLIP_SOURCES)} swift files")
print(f"  app packages:  {', '.join(APP_PACKAGES)}")
print(f"  clip packages: {', '.join(CLIP_PACKAGES)}")
