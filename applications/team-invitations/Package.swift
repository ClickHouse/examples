// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "team-invitations",
    products: [.executable(name: "Invitations", targets: ["Run"])],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", exact: "4.122.2"),
        .package(url: "https://github.com/vapor/fluent.git", exact: "4.13.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", exact: "2.14.0"),
    ],
    targets: [
        .target(name: "App", dependencies: [
            .product(name: "Vapor", package: "vapor"),
            .product(name: "Fluent", package: "fluent"),
            .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
        ]),
        .executableTarget(name: "Run", dependencies: [.target(name: "App")]),
        .testTarget(name: "AppTests", dependencies: [
            .target(name: "App"), .product(name: "XCTVapor", package: "vapor"),
        ]),
    ],
    swiftLanguageModes: [.v6]
)
