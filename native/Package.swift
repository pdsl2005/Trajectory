// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "TrajectoryCore",
  platforms: [.iOS(.v17), .macOS(.v13)],
  products: [.library(name: "TrajectoryCore", targets: ["TrajectoryCore"])],
  targets: [
    .target(name: "TrajectoryCore"),
    .testTarget(name: "TrajectoryCoreTests", dependencies: ["TrajectoryCore"], resources: [.process("Fixtures")])
  ]
)
