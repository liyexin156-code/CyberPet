// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PetTaskBuddy",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PetTaskBuddy", targets: ["PetTaskBuddy"])
    ],
    targets: [
        .executableTarget(
            name: "PetTaskBuddy",
            path: ".",
            exclude: [
                "PHASE0_ACCEPTANCE.md",
                "PHASE1_TASKS_ACCEPTANCE.md",
                "PHASE1B_ACCEPTANCE.md",
                "PHASE15_SCHEDULE_ACCEPTANCE.md",
                "PHASE16_THOUGHT_BUBBLES_ACCEPTANCE.md",
                "PHASE2_AI_ACCEPTANCE.md",
                "BUILD_AND_INSTALL.md",
                "Packaging",
                "Tools",
                "Tests"
            ],
            sources: ["Sources/PetTaskBuddy"],
            resources: [
                .copy("Assets/pet")
            ]
        ),
        .testTarget(
            name: "PetTaskBuddyTests",
            dependencies: ["PetTaskBuddy"],
            path: "Tests/PetTaskBuddyTests"
        )
    ]
)
