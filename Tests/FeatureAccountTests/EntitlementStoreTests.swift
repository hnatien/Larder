import Foundation
import LarderCore
import Testing
@testable import FeatureAccount

@MainActor
@Suite("EntitlementStore")
struct EntitlementStoreTests {
    private func started(_ script: FakeStoreFront.Script = .init(), dates: any DateProvider = FixedDates())
        async -> (EntitlementStore, FakeStoreFront)
    {
        let front = FakeStoreFront(script)
        let store = EntitlementStore(storeFront: front, dates: dates)
        await store.start()
        return (store, front)
    }

    @Test func startLoadsProductsInPlusOrder() async {
        let (store, _) = await started()
        #expect(store.products.map(\.id) == [monthlyID, annualID])
        #expect(store.isLoading == false)
        #expect(store.error == nil)
    }

    @Test func productLoadFailureSetsErrorAndKeepsFree() async {
        let (store, _) = await started(.init(failsProducts: true))
        #expect(store.products.isEmpty)
        #expect(store.error == .productsUnavailable)
        #expect(store.tier == .free)
    }

    @Test func retryingProductsClearsTheError() async {
        let (store, front) = await started(.init(failsProducts: true))
        front.update { $0.failsProducts = false }
        await store.loadProducts()
        #expect(store.error == nil)
        #expect(store.products.count == 2)
    }

    @Test func noEntitlementsIsFree() async {
        let (store, _) = await started()
        #expect(store.tier == .free)
        #expect(store.activeRecord == nil)
    }

    @Test func activeSubscriptionIsPlus() async {
        let active = record(monthlyID)
        let (store, _) = await started(.init(entitlements: [active]))
        #expect(store.tier == .plus)
        #expect(store.activeRecord == active)
    }

    @Test func expiredSubscriptionIsFree() async {
        let (store, _) = await started(.init(entitlements: [record(expires: referenceNow.addingTimeInterval(-1))]))
        #expect(store.tier == .free)
    }

    @Test func revokedSubscriptionIsFree() async {
        let refunded = record(revoked: referenceNow.addingTimeInterval(-3_600))
        let (store, _) = await started(.init(entitlements: [refunded]))
        #expect(store.tier == .free)
    }

    @Test func upgradedTransactionGivesWayToItsReplacement() async {
        let upgraded = record(monthlyID, expires: referenceNow.addingTimeInterval(400_000), upgraded: true)
        let annual = record(annualID, expires: referenceNow.addingTimeInterval(86_400))
        let (store, _) = await started(.init(entitlements: [upgraded, annual]))
        #expect(store.tier == .plus)
        #expect(store.activeRecord?.productID == annualID)
    }

    @Test func upgradedTransactionAloneIsFree() async {
        let (store, _) = await started(.init(entitlements: [record(monthlyID, upgraded: true)]))
        #expect(store.tier == .free)
    }

    @Test func unverifiedTransactionIsIgnored() async {
        let (store, _) = await started(.init(entitlements: [record(verified: false)]))
        #expect(store.tier == .free)
        #expect(store.activeRecord == nil)
        #expect(await store.entitlementJWS() == nil)
    }

    @Test func unverifiedRecordCarriesNoJWS() {
        #expect(record(verified: false, jws: "forged").signedJWS == nil)
    }

    @Test func unknownProductDoesNotGrantPlus() async {
        let (store, _) = await started(.init(entitlements: [record("com.example.other")]))
        #expect(store.tier == .free)
    }

    @Test func longestActiveRecordWins() async {
        let short = record(monthlyID, expires: referenceNow.addingTimeInterval(3_600))
        let long = record(annualID, expires: referenceNow.addingTimeInterval(300 * 86_400))
        let (store, _) = await started(.init(entitlements: [short, long]))
        #expect(store.activeRecord == long)
    }

    @Test func updateFlipsFreeToPlus() async {
        let (store, front) = await started()
        front.send(record())
        #expect(await eventually { store.tier == .plus })
    }

    @Test func revocationUpdateFlipsPlusToFree() async {
        let (store, front) = await started(.init(entitlements: [record()]))
        #expect(store.tier == .plus)
        front.send(record(revoked: referenceNow))
        #expect(await eventually { store.tier == .free })
        #expect(store.activeRecord == nil)
    }

    @Test func unverifiedUpdateCannotRevoke() async {
        let (store, front) = await started(.init(entitlements: [record()]))
        front.send(record(revoked: referenceNow, verified: false))
        front.send(record(monthlyID, expires: referenceNow.addingTimeInterval(2 * 86_400)))
        #expect(await eventually { store.activeRecord?.productID == monthlyID })
        front.send(record(monthlyID, revoked: referenceNow))
        #expect(await eventually { store.activeRecord?.productID == annualID })
        #expect(store.tier == .plus)
    }

    @Test func unverifiedUpdateCannotGrant() async {
        let (store, front) = await started()
        front.send(record(verified: false))
        front.send(record(monthlyID))
        #expect(await eventually { store.activeRecord?.productID == monthlyID })
        front.send(record(monthlyID, revoked: referenceNow))
        #expect(await eventually { store.tier == .free })
        #expect(store.activeRecord == nil)
    }

    @Test func secondStartDoesNotReload() async {
        let (store, front) = await started()
        front.update { $0.entitlements = [record()] }
        await store.start()
        #expect(store.tier == .free)
    }

    @Test func purchaseSuccessGrantsPlus() async {
        let (store, front) = await started(.init(purchaseOutcome: .success(record())))
        let result = await store.purchase(annualProduct)
        #expect(result == .purchased)
        #expect(store.tier == .plus)
        #expect(store.error == nil)
        #expect(front.state.purchased == [annualID])
    }

    @Test func purchaseWithUnverifiedTransactionFails() async {
        let (store, _) = await started(.init(purchaseOutcome: .success(record(verified: false))))
        let result = await store.purchase(annualProduct)
        #expect(result == .failed)
        #expect(store.error == .verificationFailed)
        #expect(store.tier == .free)
    }

    @Test func pendingPurchaseWaitsUntilApproved() async {
        let (store, front) = await started(.init(purchaseOutcome: .pending))
        #expect(await store.purchase(monthlyProduct) == .pending)
        #expect(store.isAwaitingApproval)
        #expect(store.tier == .free)
        front.send(record(monthlyID))
        #expect(await eventually { store.tier == .plus })
        #expect(store.isAwaitingApproval == false)
    }

    @Test func cancelledPurchaseChangesNothing() async {
        let (store, _) = await started(.init(purchaseOutcome: .userCancelled))
        #expect(await store.purchase(monthlyProduct) == .cancelled)
        #expect(store.error == nil)
        #expect(store.tier == .free)
    }

    @Test func purchaseErrorSetsError() async {
        let (store, _) = await started(.init(failsPurchase: true))
        #expect(await store.purchase(monthlyProduct) == .failed)
        #expect(store.error == .purchaseFailed)
        #expect(store.isLoading == false)
    }

    @Test func systemPurchaseFailureIsReported() async {
        let (store, _) = await started()
        #expect(store.complete(.failure(FakeError.failed)) == .failed)
        #expect(store.error == .purchaseFailed)
    }

    @Test func restoreReloadsEntitlements() async {
        let (store, front) = await started(.init(restoredEntitlements: [record()]))
        #expect(store.tier == .free)
        await store.restore()
        #expect(front.state.restoreCount == 1)
        #expect(store.tier == .plus)
        #expect(store.error == nil)
    }

    @Test func restoreFailureSetsErrorAndKeepsTier() async {
        let (store, front) = await started(.init(failsRestore: true, restoredEntitlements: [record()]))
        await store.restore()
        #expect(store.error == .restoreFailed)
        #expect(store.tier == .free)
        #expect(front.state.restoreCount == 1)
    }

    @Test func entitlementJWSIsTheActiveRecords() async {
        let active = record(annualID, jws: "header.payload.signature")
        let (store, _) = await started(.init(entitlements: [record(monthlyID, upgraded: true), active]))
        #expect(await store.entitlementJWS() == "header.payload.signature")
    }

    @Test func entitlementJWSIsNilWhenFree() async {
        let (store, _) = await started(.init(entitlements: [record(expires: referenceNow)]))
        #expect(await store.entitlementJWS() == nil)
    }

    @Test func isPlusFollowsExpiryWithoutAnUpdate() async {
        let dates = MutableDates()
        let (store, _) = await started(.init(entitlements: [record(expires: referenceNow.addingTimeInterval(60))]), dates: dates)
        let isPlus = store.isPlus
        #expect(await isPlus())
        dates.advance(by: 120)
        #expect(await isPlus() == false)
        #expect(store.tier == .free)
        #expect(await store.entitlementJWS() == nil)
    }
}

@Suite("TrialWeekGate and comfort preferences")
struct TrialWeekGateTests {
    @Test func freshGateAllowsOneWeek() {
        #expect(TrialWeekGate(store: InMemoryKeyValueStore()).canGenerateFreeWeek)
    }

    @Test func markingUsedClosesTheGate() {
        let gate = TrialWeekGate(store: InMemoryKeyValueStore())
        gate.markFreeWeekUsed()
        #expect(gate.canGenerateFreeWeek == false)
    }

    @Test func usedWeekPersistsAcrossInstances() {
        let store = InMemoryKeyValueStore()
        TrialWeekGate(store: store).markFreeWeekUsed()
        #expect(TrialWeekGate(store: store).canGenerateFreeWeek == false)
    }

    @Test func comfortDefaults() {
        let preferences = ComfortPreferences(store: InMemoryKeyValueStore())
        #expect(preferences.prefersSimpleLayout == false)
        #expect(preferences.timersFlashAndVibrate)
    }

    @Test func userDefaultsStoreRoundTripsAndReportsMissingKeys() throws {
        let suite = "larder.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsKeyValueStore(defaults: defaults)
        #expect(store.bool(forKey: "missing") == nil)
        store.set(false, forKey: "flag")
        #expect(store.bool(forKey: "flag") == false)
    }
}
