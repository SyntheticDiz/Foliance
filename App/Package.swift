// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Foliance",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "Foliance", targets: ["FolianceApp"])],
    targets: [
        .target(name: "FolianceCore"),
        .target(name: "SnowballDutch", path: "Sources/NativeSearchSupport/SnowballDutch", publicHeadersPath: "include",
                cSettings: [.headerSearchPath("runtime"), .headerSearchPath("src_c")]),
        .target(name: "RapidFuzzNative", path: "Sources/NativeSearchSupport/RapidFuzz", publicHeadersPath: "include",
                cxxSettings: [.headerSearchPath("vendor")]),
        .executableTarget(name: "FolianceApp", dependencies: ["FolianceCore", "SnowballDutch", "RapidFuzzNative"]),
        .testTarget(name: "FolianceCoreTests", dependencies: ["FolianceCore"]),
        .testTarget(name: "FolianceAppTests", dependencies: ["FolianceApp", "FolianceCore"])
    ],
    cxxLanguageStandard: .cxx17
)
