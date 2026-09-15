import XCTest

@testable import MemoBookNetworking

/// Ce qui garantit qu'un iPhone ne parle jamais à `localhost` — la seconde
/// ceinture, derrière `Config/Debug.xcconfig` qui ne donne la boucle locale
/// qu'au simulateur. Une fonction pure, donc testée sans appareil.
final class APIConfigurationTests: XCTestCase {
    private let local = APIConfiguration(baseURL: URL(string: "http://localhost:3000")!)
    private let loopbackIP = APIConfiguration(baseURL: URL(string: "http://127.0.0.1:3000")!)
    private let lan = APIConfiguration(baseURL: URL(string: "http://192.168.1.20:3000")!)
    private let production = APIConfiguration(
        baseURL: URL(string: "https://api-production-9f35a.up.railway.app")!
    )

    func testLoopbackIsRecognised() {
        XCTAssertTrue(local.isLoopback)
        XCTAssertTrue(loopbackIP.isLoopback)
        XCTAssertTrue(APIConfiguration(baseURL: URL(string: "http://[::1]:3000")!).isLoopback)
        XCTAssertFalse(lan.isLoopback)
        XCTAssertFalse(production.isLoopback)
    }

    func testSimulatorKeepsLocalhostWithProductionAsFallback() {
        let resolved = APIConfiguration.effective(
            configured: local, productionFallback: production, runsInSimulator: true
        )
        XCTAssertEqual(resolved?.baseURL, local.baseURL)
        // La production n'est pas remplacée, elle est **derrière** : le client
        // y bascule si rien n'écoute sur le Mac.
        XCTAssertEqual(resolved?.fallbackBaseURL, production.baseURL)
    }

    func testSimulatorWithoutProductionKeepsLocalhostAlone() {
        let resolved = APIConfiguration.effective(
            configured: local, productionFallback: nil, runsInSimulator: true
        )
        XCTAssertEqual(resolved?.baseURL, local.baseURL)
        XCTAssertNil(resolved?.fallbackBaseURL)
    }

    func testRemoteAddressNeverGetsAFallback() {
        // La production, ou l'IP du Mac : une adresse distante qui ne répond pas
        // est une vraie panne, pas un back-end qu'on a oublié de lancer.
        let resolved = APIConfiguration.effective(
            configured: lan, productionFallback: production, runsInSimulator: true
        )
        XCTAssertEqual(resolved, lan)
        XCTAssertNil(resolved?.fallbackBaseURL)
    }

    func testDeviceNeverKeepsLocalhost() {
        let resolved = APIConfiguration.effective(
            configured: local, productionFallback: production, runsInSimulator: false
        )
        XCTAssertEqual(resolved, production)

        let resolvedIP = APIConfiguration.effective(
            configured: loopbackIP, productionFallback: production, runsInSimulator: false
        )
        XCTAssertEqual(resolvedIP, production)
    }

    func testDeviceKeepsAnExplicitRemoteAddress() {
        // L'IP du Mac posée dans `Secrets.xcconfig`, ou la production elle-même :
        // ce n'est pas une boucle locale, l'appareil la garde.
        XCTAssertEqual(
            APIConfiguration.effective(configured: lan, productionFallback: production, runsInSimulator: false),
            lan
        )
        XCTAssertEqual(
            APIConfiguration.effective(
                configured: production, productionFallback: production, runsInSimulator: false
            ),
            production
        )
    }

    func testMissingConfigurationFallsBackToProduction() {
        XCTAssertEqual(
            APIConfiguration.effective(configured: nil, productionFallback: production, runsInSimulator: false),
            production
        )
        XCTAssertNil(
            APIConfiguration.effective(configured: nil, productionFallback: nil, runsInSimulator: true)
        )
    }

    func testDeviceWithoutFallbackKeepsWhatItHas() {
        // Un build construit de travers, sans clé de production : on rend la
        // seule adresse connue plutôt que rien — c'est l'app qui décide alors
        // de s'arrêter, et le message dit pourquoi.
        XCTAssertEqual(
            APIConfiguration.effective(configured: local, productionFallback: nil, runsInSimulator: false),
            local
        )
    }
}
