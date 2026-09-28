#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"

ROOT = File.expand_path("..", __dir__)
PROJECT_DIR = File.join(ROOT, "BuildSweep.xcodeproj")

def uid(seed)
  Digest::SHA1.hexdigest("BuildSweep:#{seed}")[0, 24].upcase
end

def q(value)
  %Q{"#{value.gsub('"', '\\"')}"}
end

app_sources = Dir.glob(File.join(ROOT, "BuildSweep/**/*.swift")).sort
test_sources = Dir.glob(File.join(ROOT, "BuildSweepTests/**/*.swift")).sort
ui_sources = Dir.glob(File.join(ROOT, "BuildSweepUITests/**/*.swift")).sort
helper_sources = Dir.glob(File.join(ROOT, "BuildSweepMCP/**/*.swift")).sort
helper_files = helper_sources + [File.join(ROOT, "BuildSweepMCP/BuildSweepMCP.entitlements")]
app_files = app_sources + [
  File.join(ROOT, "BuildSweep/Assets.xcassets"),
  File.join(ROOT, "BuildSweep/PrivacyInfo.xcprivacy"),
  File.join(ROOT, "BuildSweep/Info.plist"),
  File.join(ROOT, "BuildSweep/BuildSweep.entitlements")
]
resource_files = app_files.select { |path| path.end_with?(".xcassets", ".xcprivacy") }

file_ref = ->(path) { uid("fileref:#{path}") }
build_file = ->(path, phase) { uid("build:#{phase}:#{path}") }

project_id = uid("project")
main_group = uid("group:main")
app_group = uid("group:app")
tests_group = uid("group:tests")
ui_group = uid("group:uitests")
helper_group = uid("group:helper")
products_group = uid("group:products")
app_target = uid("target:app")
tests_target = uid("target:tests")
ui_target = uid("target:uitests")
helper_target = uid("target:mcp-helper")
app_product = uid("product:app")
tests_product = uid("product:tests")
ui_product = uid("product:uitests")
helper_product = uid("product:mcp-helper")
mcp_package = uid("package:mcp-sdk")
mcp_package_product = uid("packageproduct:mcp-sdk")

objects = []

app_sources.each do |path|
  objects << "\t\t#{build_file.call(path, 'sources')} /* #{File.basename(path)} in Sources */ = {isa = PBXBuildFile; fileRef = #{file_ref.call(path)} /* #{File.basename(path)} */; };"
end
test_sources.each do |path|
  objects << "\t\t#{build_file.call(path, 'tests')} /* #{File.basename(path)} in Sources */ = {isa = PBXBuildFile; fileRef = #{file_ref.call(path)} /* #{File.basename(path)} */; };"
end
ui_sources.each do |path|
  objects << "\t\t#{build_file.call(path, 'uitests')} /* #{File.basename(path)} in Sources */ = {isa = PBXBuildFile; fileRef = #{file_ref.call(path)} /* #{File.basename(path)} */; };"
end
helper_sources.each do |path|
  objects << "\t\t#{build_file.call(path, 'helper')} /* #{File.basename(path)} in Sources */ = {isa = PBXBuildFile; fileRef = #{file_ref.call(path)} /* #{File.basename(path)} */; };"
end
objects << "\t\t#{uid('build:package:mcp-sdk')} /* MCP in Frameworks */ = {isa = PBXBuildFile; productRef = #{mcp_package_product}; };"
objects << "\t\t#{uid('build:embed:mcp-helper')} /* BuildSweepMCP in Embed Helper Tools */ = {isa = PBXBuildFile; fileRef = #{helper_product}; settings = {ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, ); }; };"
resource_files.each do |path|
  objects << "\t\t#{build_file.call(path, 'resources')} /* #{File.basename(path)} in Resources */ = {isa = PBXBuildFile; fileRef = #{file_ref.call(path)} /* #{File.basename(path)} */; };"
end

objects << "\t\t#{uid('proxy:tests')} /* PBXContainerItemProxy */ = {isa = PBXContainerItemProxy; containerPortal = #{project_id} /* Project object */; proxyType = 1; remoteGlobalIDString = #{app_target}; remoteInfo = BuildSweep; };"
objects << "\t\t#{uid('proxy:uitests')} /* PBXContainerItemProxy */ = {isa = PBXContainerItemProxy; containerPortal = #{project_id} /* Project object */; proxyType = 1; remoteGlobalIDString = #{app_target}; remoteInfo = BuildSweep; };"

app_files.each do |path|
  relative = path.delete_prefix(File.join(ROOT, "BuildSweep/"))
  ext = File.extname(path)
  type = case ext
         when ".swift" then "sourcecode.swift"
         when ".plist" then "text.plist.xml"
         when ".xcprivacy" then "text.xml"
         when ".xcassets" then "folder.assetcatalog"
         else "text"
         end
  objects << "\t\t#{file_ref.call(path)} /* #{File.basename(path)} */ = {isa = PBXFileReference; lastKnownFileType = #{type}; path = #{q(relative)}; sourceTree = \"<group>\"; };"
end
(test_sources + ui_sources + [File.join(ROOT, "BuildSweepMCP/BuildSweepMCP.entitlements")]).each do |path|
  next if path.include?("BuildSweepMCP")
  group_root = path.include?("BuildSweepUITests") ? "BuildSweepUITests" : "BuildSweepTests"
  relative = path.delete_prefix(File.join(ROOT, "#{group_root}/"))
  objects << "\t\t#{file_ref.call(path)} /* #{File.basename(path)} */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = #{q(relative)}; sourceTree = \"<group>\"; };"
end
helper_files.each do |path|
  relative = path.delete_prefix(File.join(ROOT, "BuildSweepMCP/"))
  ext = File.extname(path)
  type = ext == ".swift" ? "sourcecode.swift" : "text.plist.entitlements"
  objects << "\t\t#{file_ref.call(path)} /* #{File.basename(path)} */ = {isa = PBXFileReference; lastKnownFileType = #{type}; path = #{q(relative)}; sourceTree = \"<group>\"; };"
end
helper_sources.each do |path|
  relative = path.delete_prefix(File.join(ROOT, "BuildSweepMCP/"))
  objects << "\t\t#{file_ref.call(path)} /* #{File.basename(path)} */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = #{q(relative)}; sourceTree = \"<group>\"; };"
end
objects << "\t\t#{app_product} /* BuildSweep.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = BuildSweep.app; sourceTree = BUILT_PRODUCTS_DIR; };"
objects << "\t\t#{tests_product} /* BuildSweepTests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = BuildSweepTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };"
objects << "\t\t#{ui_product} /* BuildSweepUITests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = BuildSweepUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };"
objects << "\t\t#{helper_product} /* BuildSweepMCP */ = {isa = PBXFileReference; explicitFileType = " + q("compiled.mach-o.executable") + "; includeInIndex = 0; path = BuildSweepMCP; sourceTree = BUILT_PRODUCTS_DIR; };"

def phase(id, isa, files)
  "\t\t#{id} = {isa = #{isa}; buildActionMask = 2147483647; files = (\n#{files.map { |value| "\t\t\t\t#{value}," }.join("\n")}\n\t\t\t); runOnlyForDeploymentPostprocessing = 0; };"
end

app_source_entries = app_sources.map { |p| "#{build_file.call(p, 'sources')} /* #{File.basename(p)} in Sources */" }
test_source_entries = test_sources.map { |p| "#{build_file.call(p, 'tests')} /* #{File.basename(p)} in Sources */" }
ui_source_entries = ui_sources.map { |p| "#{build_file.call(p, 'uitests')} /* #{File.basename(p)} in Sources */" }
helper_source_entries = helper_sources.map { |p| "#{build_file.call(p, 'helper')} /* #{File.basename(p)} in Sources */" }
resource_entries = resource_files.map { |p| "#{build_file.call(p, 'resources')} /* #{File.basename(p)} in Resources */" }

objects << phase(uid("phase:app:sources"), "PBXSourcesBuildPhase", app_source_entries)
objects << phase(uid("phase:app:frameworks"), "PBXFrameworksBuildPhase", [])
objects << phase(uid("phase:app:resources"), "PBXResourcesBuildPhase", resource_entries)
objects << phase(uid("phase:tests:sources"), "PBXSourcesBuildPhase", test_source_entries)
objects << phase(uid("phase:tests:frameworks"), "PBXFrameworksBuildPhase", [])
objects << phase(uid("phase:tests:resources"), "PBXResourcesBuildPhase", [])
objects << phase(uid("phase:ui:sources"), "PBXSourcesBuildPhase", ui_source_entries)
objects << phase(uid("phase:ui:frameworks"), "PBXFrameworksBuildPhase", [])
objects << phase(uid("phase:ui:resources"), "PBXResourcesBuildPhase", [])
objects << phase(uid("phase:helper:sources"), "PBXSourcesBuildPhase", helper_source_entries)
objects << phase(uid("phase:helper:frameworks"), "PBXFrameworksBuildPhase", ["#{uid('build:package:mcp-sdk')} /* MCP in Frameworks */"])
objects << phase(uid("phase:helper:resources"), "PBXResourcesBuildPhase", [])
objects << "\t\t#{uid('phase:app:embed-helper')} /* Embed Helper Tools */ = {isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = \"$(TARGET_BUILD_DIR)/$(CONTENTS_FOLDER_PATH)/Library/HelperTools\"; dstSubfolderSpec = 0; files = (#{uid('build:embed:mcp-helper')} /* BuildSweepMCP in Embed Helper Tools */, ); name = \"Embed Helper Tools\"; runOnlyForDeploymentPostprocessing = 0; };"

app_children = app_files.map { |p| "#{file_ref.call(p)} /* #{File.basename(p)} */" }
test_children = test_sources.map { |p| "#{file_ref.call(p)} /* #{File.basename(p)} */" }
ui_children = ui_sources.map { |p| "#{file_ref.call(p)} /* #{File.basename(p)} */" }
helper_children = helper_files.map { |p| "#{file_ref.call(p)} /* #{File.basename(p)} */" }

objects << "\t\t#{main_group} = {isa = PBXGroup; children = (#{app_group}, #{tests_group}, #{ui_group}, #{helper_group}, #{products_group}); sourceTree = \"<group>\"; };"
objects << "\t\t#{app_group} /* BuildSweep */ = {isa = PBXGroup; children = (#{app_children.join(', ')}); path = BuildSweep; sourceTree = \"<group>\"; };"
objects << "\t\t#{tests_group} /* BuildSweepTests */ = {isa = PBXGroup; children = (#{test_children.join(', ')}); path = BuildSweepTests; sourceTree = \"<group>\"; };"
objects << "\t\t#{ui_group} /* BuildSweepUITests */ = {isa = PBXGroup; children = (#{ui_children.join(', ')}); path = BuildSweepUITests; sourceTree = \"<group>\"; };"
objects << "\t\t#{helper_group} /* BuildSweepMCP */ = {isa = PBXGroup; children = (#{helper_children.join(', ')}); path = BuildSweepMCP; sourceTree = \"<group>\"; };"
objects << "\t\t#{products_group} /* Products */ = {isa = PBXGroup; children = (#{app_product}, #{tests_product}, #{ui_product}, #{helper_product}); name = Products; sourceTree = \"<group>\"; };"

objects << "\t\t#{app_target} /* BuildSweep */ = {isa = PBXNativeTarget; buildConfigurationList = #{uid('configlist:app')}; buildPhases = (#{uid('phase:app:sources')}, #{uid('phase:app:frameworks')}, #{uid('phase:app:resources')}, #{uid('phase:app:embed-helper')}); buildRules = (); dependencies = (#{uid('dependency:helper')}); name = BuildSweep; productName = BuildSweep; productReference = #{app_product}; productType = \"com.apple.product-type.application\"; };"
objects << "\t\t#{tests_target} /* BuildSweepTests */ = {isa = PBXNativeTarget; buildConfigurationList = #{uid('configlist:tests')}; buildPhases = (#{uid('phase:tests:sources')}, #{uid('phase:tests:frameworks')}, #{uid('phase:tests:resources')}); buildRules = (); dependencies = (#{uid('dependency:tests')}); name = BuildSweepTests; productName = BuildSweepTests; productReference = #{tests_product}; productType = \"com.apple.product-type.bundle.unit-test\"; };"
objects << "\t\t#{ui_target} /* BuildSweepUITests */ = {isa = PBXNativeTarget; buildConfigurationList = #{uid('configlist:uitests')}; buildPhases = (#{uid('phase:ui:sources')}, #{uid('phase:ui:frameworks')}, #{uid('phase:ui:resources')}); buildRules = (); dependencies = (#{uid('dependency:uitests')}); name = BuildSweepUITests; productName = BuildSweepUITests; productReference = #{ui_product}; productType = \"com.apple.product-type.bundle.ui-testing\"; };"
objects << "\t\t#{helper_target} /* BuildSweepMCP */ = {isa = PBXNativeTarget; buildConfigurationList = #{uid('configlist:helper')}; buildPhases = (#{uid('phase:helper:sources')}, #{uid('phase:helper:frameworks')}, #{uid('phase:helper:resources')}); buildRules = (); dependencies = (); name = BuildSweepMCP; packageProductDependencies = (#{mcp_package_product}); productName = BuildSweepMCP; productReference = #{helper_product}; productType = \"com.apple.product-type.tool\"; };"

objects << "\t\t#{project_id} /* Project object */ = {isa = PBXProject; attributes = {BuildIndependentTargetsInParallel = 1; LastSwiftUpdateCheck = 2660; LastUpgradeCheck = 2660; TargetAttributes = {#{app_target} = {CreatedOnToolsVersion = 26.0;}; #{tests_target} = {CreatedOnToolsVersion = 26.0; TestTargetID = #{app_target};}; #{ui_target} = {CreatedOnToolsVersion = 26.0; TestTargetID = #{app_target};}; #{helper_target} = {CreatedOnToolsVersion = 26.0;};};}; buildConfigurationList = #{uid('configlist:project')}; compatibilityVersion = \"Xcode 15.0\"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = #{main_group}; packageReferences = (#{mcp_package}, ); productRefGroup = #{products_group}; projectDirPath = \"\"; projectRoot = \"\"; targets = (#{app_target}, #{tests_target}, #{ui_target}, #{helper_target}); };"

objects << "\t\t#{uid('dependency:tests')} = {isa = PBXTargetDependency; target = #{app_target}; targetProxy = #{uid('proxy:tests')}; };"
objects << "\t\t#{uid('dependency:uitests')} = {isa = PBXTargetDependency; target = #{app_target}; targetProxy = #{uid('proxy:uitests')}; };"
objects << "\t\t#{uid('dependency:helper')} = {isa = PBXTargetDependency; target = #{helper_target}; targetProxy = #{uid('proxy:helper')}; };"
objects << "\t\t#{uid('proxy:helper')} /* PBXContainerItemProxy */ = {isa = PBXContainerItemProxy; containerPortal = #{project_id} /* Project object */; proxyType = 1; remoteGlobalIDString = #{helper_target}; remoteInfo = BuildSweepMCP; };"
objects << "\t\t#{mcp_package} /* XCRemoteSwiftPackageReference \"swift-sdk\" */ = {isa = XCRemoteSwiftPackageReference; repositoryURL = \"https://github.com/modelcontextprotocol/swift-sdk.git\"; requirement = {kind = exactVersion; version = 0.12.1; }; };"
objects << "\t\t#{mcp_package_product} /* MCP */ = {isa = XCSwiftPackageProductDependency; package = #{mcp_package}; productName = MCP; };"

project_settings = {
  "ALWAYS_SEARCH_USER_PATHS" => "NO", "CLANG_ENABLE_MODULES" => "YES",
  "CLANG_ENABLE_OBJC_ARC" => "YES", "MACOSX_DEPLOYMENT_TARGET" => "14.0",
  "SDKROOT" => "macosx", "SWIFT_VERSION" => "5.0"
}
app_settings = {
  "ASSETCATALOG_COMPILER_ACCENT_COLOR_NAME" => "AccentColor",
  "ASSETCATALOG_COMPILER_APPICON_NAME" => "AppIcon",
  "CODE_SIGN_ENTITLEMENTS" => "BuildSweep/BuildSweep.entitlements",
  "CODE_SIGN_STYLE" => "Automatic", "CURRENT_PROJECT_VERSION" => "1",
  "ENABLE_APP_SANDBOX" => "YES",
  "ENABLE_HARDENED_RUNTIME" => "YES", "GENERATE_INFOPLIST_FILE" => "NO",
  "INFOPLIST_FILE" => "BuildSweep/Info.plist", "MARKETING_VERSION" => "1.0.0",
  "PRODUCT_BUNDLE_IDENTIFIER" => "com.ayush.buildsweep", "PRODUCT_NAME" => "$(TARGET_NAME)",
  "SWIFT_EMIT_LOC_STRINGS" => "YES", "SWIFT_VERSION" => "5.0"
}
tests_settings = {
  "BUNDLE_LOADER" => "$(TEST_HOST)", "CODE_SIGN_STYLE" => "Automatic",
  "GENERATE_INFOPLIST_FILE" => "YES",
  "PRODUCT_BUNDLE_IDENTIFIER" => "com.ayush.buildsweep.tests", "PRODUCT_NAME" => "$(TARGET_NAME)",
  "SWIFT_VERSION" => "5.0", "TEST_HOST" => "$(BUILT_PRODUCTS_DIR)/BuildSweep.app/Contents/MacOS/BuildSweep"
}
ui_settings = {
  "CODE_SIGN_STYLE" => "Automatic",
  "GENERATE_INFOPLIST_FILE" => "YES", "PRODUCT_BUNDLE_IDENTIFIER" => "com.ayush.buildsweep.uitests",
  "PRODUCT_NAME" => "$(TARGET_NAME)", "SWIFT_VERSION" => "5.0", "TEST_TARGET_NAME" => "BuildSweep"
}
helper_settings = {
  "CODE_SIGN_ENTITLEMENTS" => "BuildSweepMCP/BuildSweepMCP.entitlements",
  "CODE_SIGN_STYLE" => "Automatic", "ENABLE_APP_SANDBOX" => "YES",
  "CREATE_INFOPLIST_SECTION_IN_BINARY" => "YES",
  "ENABLE_HARDENED_RUNTIME" => "YES", "GENERATE_INFOPLIST_FILE" => "YES",
  "MACOSX_DEPLOYMENT_TARGET" => "14.0", "PRODUCT_BUNDLE_IDENTIFIER" => "com.ayush.buildsweep.mcp",
  "PRODUCT_NAME" => "BuildSweepMCP", "SKIP_INSTALL" => "YES", "SWIFT_VERSION" => "6.0"
}

def configuration(id, name, settings)
  body = settings.map { |key, value| "\t\t\t\t#{key} = #{value.include?(' ') || value.include?('$') ? q(value) : value};" }.join("\n")
  "\t\t#{id} /* #{name} */ = {isa = XCBuildConfiguration; buildSettings = {\n#{body}\n\t\t\t}; name = #{name}; };"
end

{
  "project" => project_settings,
  "app" => app_settings,
  "tests" => tests_settings,
  "uitests" => ui_settings,
  "helper" => helper_settings
}.each do |scope, settings|
  debug_settings = settings.merge("DEBUG_INFORMATION_FORMAT" => "dwarf", "SWIFT_OPTIMIZATION_LEVEL" => q("-Onone"))
  debug_settings["ENABLE_TESTABILITY"] = "YES" if scope == "app"
  objects << configuration(uid("config:#{scope}:debug"), "Debug", debug_settings)
  objects << configuration(uid("config:#{scope}:release"), "Release", settings.merge("DEBUG_INFORMATION_FORMAT" => "dwarf-with-dsym", "SWIFT_COMPILATION_MODE" => "wholemodule"))
  objects << "\t\t#{uid("configlist:#{scope}")} = {isa = XCConfigurationList; buildConfigurations = (#{uid("config:#{scope}:debug")}, #{uid("config:#{scope}:release")}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };"
end

pbx = <<~PBX
  // !$*UTF8*$!
  {
    archiveVersion = 1;
    classes = {};
    objectVersion = 63;
    objects = {
  #{objects.join("\n")}
    };
    rootObject = #{project_id} /* Project object */;
  }
PBX

FileUtils.mkdir_p(PROJECT_DIR)
File.write(File.join(PROJECT_DIR, "project.pbxproj"), pbx)
puts "Generated #{File.join(PROJECT_DIR, 'project.pbxproj')}"
