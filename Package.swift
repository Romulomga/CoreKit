// swift-tools-version: 6.0

import PackageDescription

// One package, one library per concern: an app links only the products it imports, and only
// those get compiled. SwiftPM still downloads every dependency declared here (Firebase,
// Mixpanel) for any app that resolves the package, but never builds one the app doesn't use.

let package = Package(
    name: "CoreKit",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "CoreKit", targets: ["CoreKit"]),
        .library(name: "CoreKitNavigation", targets: ["CoreKitNavigation"]),
        .library(name: "CoreKitAnalytics", targets: ["CoreKitAnalytics"]),
        .library(name: "CoreKitFirebase", targets: ["CoreKitFirebase"]),
        .library(name: "CoreKitMixpanel", targets: ["CoreKitMixpanel"]),
        .library(name: "CoreKitStore", targets: ["CoreKitStore"]),
        .library(name: "CoreKitReview", targets: ["CoreKitReview"]),
        .library(name: "CoreKitPersistence", targets: ["CoreKitPersistence"]),
        .library(name: "CoreKitTesting", targets: ["CoreKitTesting"]),
    ],
    dependencies: [
        .package(url: "https://github.com/firebase/firebase-ios-sdk", from: "12.15.0"),
        .package(url: "https://github.com/mixpanel/mixpanel-swift", from: "6.6.1"),
    ],
    targets: [
        .target(name: "CoreKit"),
        .target(name: "CoreKitNavigation", dependencies: ["CoreKit"]),
        .target(name: "CoreKitAnalytics"),
        .target(
            name: "CoreKitFirebase",
            dependencies: [
                "CoreKitAnalytics",
                .product(name: "FirebaseAnalytics", package: "firebase-ios-sdk"),
                .product(name: "FirebaseCrashlytics", package: "firebase-ios-sdk"),
            ]
        ),
        .target(
            name: "CoreKitMixpanel",
            dependencies: [
                "CoreKitAnalytics",
                .product(name: "Mixpanel", package: "mixpanel-swift"),
            ]
        ),
        .target(name: "CoreKitStore"),
        .target(name: "CoreKitReview"),
        .target(name: "CoreKitPersistence"),
        .target(name: "CoreKitTesting", dependencies: ["CoreKitAnalytics", "CoreKitStore"]),

        .testTarget(name: "CoreKitTests", dependencies: ["CoreKit"]),
        .testTarget(name: "CoreKitNavigationTests", dependencies: ["CoreKitNavigation"]),
        .testTarget(name: "CoreKitAnalyticsTests", dependencies: ["CoreKitAnalytics", "CoreKitTesting"]),
        .testTarget(
            name: "CoreKitFirebaseTests",
            dependencies: [
                "CoreKitFirebase",
                "CoreKitAnalytics",
                .product(name: "FirebaseCore", package: "firebase-ios-sdk"),
            ]
        ),
        .testTarget(name: "CoreKitStoreTests", dependencies: ["CoreKitStore", "CoreKitTesting"]),
        .testTarget(name: "CoreKitReviewTests", dependencies: ["CoreKitReview"]),
        .testTarget(name: "CoreKitPersistenceTests", dependencies: ["CoreKitPersistence"]),
        .testTarget(name: "CoreKitTestingTests", dependencies: ["CoreKitTesting"]),
    ]
)
