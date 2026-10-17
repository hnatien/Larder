import LarderCore
import LarderDesign
import StoreKit
import SwiftUI

/// Legal pages linked from the paywall. Placeholders under larder.app until the real pages are published.
nonisolated enum LegalLinks {
    static let terms = URL(string: "https://larder.app/terms")
    static let privacy = URL(string: "https://larder.app/privacy")
}

/// What Larder Plus adds and how to get it. "Not now" stays on screen in words, never a bare close icon.
public struct PaywallView: View {
    private let entitlements: EntitlementStore
    private let onDismiss: () -> Void
    @ScaledSpacing(.l) private var gutter

    /// Creates the paywall; `onDismiss` runs for "Not now" and after a completed purchase.
    public init(entitlements: EntitlementStore, onDismiss: @escaping () -> Void) {
        self.entitlements = entitlements
        self.onDismiss = onDismiss
    }

    public var body: some View {
        storeContent
            .background(LarderColor.surface.canvas)
            .task {
                if entitlements.products.isEmpty { await entitlements.loadProducts() }
            }
            .onChange(of: entitlements.error) { _, error in
                if let error {
                    AccessibilityNotification.Announcement(AccountCopy.message(for: error)).post()
                }
            }
    }

    @ViewBuilder
    private var storeContent: some View {
        #if os(iOS)
        if entitlements.products.isEmpty {
            fallback
        } else {
            // The plans, the subscribe button, Restore and the legal links all sit in the system's own
            // control area, so the pitch keeps the rest of the screen and nothing is stacked under it.
            SubscriptionStoreView(groupID: EntitlementStore.subscriptionGroupID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: LarderSpacing.l) {
                        status
                        pitch
                        HintText(AccountCopy.Paywall.renews)
                    }
                    .padding(gutter)
                }
            }
            .subscriptionStoreControlStyle(.compactPicker)
            .subscriptionStoreButtonLabel(.multiline)
            .storeButton(.visible, for: .restorePurchases, .policies)
            .storeButton(.hidden, for: .cancellation)
            .policyDestination(LegalLinks.terms, for: .termsOfService)
            .policyDestination(LegalLinks.privacy, for: .privacyPolicy)
            .tint(LarderColor.accent.brand)
            .containerBackground(LarderColor.surface.canvas, for: .subscriptionStore)
            .overlay(alignment: .topTrailing) {
                Button(Copy.Action.notNow, action: onDismiss)
                    .font(LarderFont.body(.body, weight: .semibold))
                    .foregroundStyle(LarderColor.ink.primary)
                    .buttonStyle(.glass)
                    .frame(minHeight: 44)
                    .padding(.trailing, gutter)
                    .padding(.top, LarderSpacing.s)
            }
            .onInAppPurchaseCompletion { _, result in
                let outcome: Result<PurchaseOutcome, any Error>
                do {
                    outcome = .success(try await LiveStoreFront.outcome(for: result.get()))
                } catch {
                    outcome = .failure(error)
                }
                if entitlements.complete(outcome) == .purchased { onDismiss() }
            }
        }
        #else
        fallback
        #endif
    }

    /// The custom product list, used where the system subscription view is unavailable or prices failed to load.
    private var fallback: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LarderSpacing.xl) {
                pitch
                VStack(alignment: .leading, spacing: LarderSpacing.s) {
                    ForEach(entitlements.products) { product in
                        Button {
                            Task {
                                if await entitlements.purchase(product) == .purchased { onDismiss() }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: LarderSpacing.xxs) {
                                Text(product.displayName)
                                Text(AccountCopy.Paywall.price(product))
                                    .font(LarderFont.body(.subheadline))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.larderPrimary)
                        .disabled(entitlements.isLoading)
                    }
                    if entitlements.products.isEmpty, entitlements.error == .productsUnavailable {
                        Button(AccountCopy.tryAgain) { Task { await entitlements.loadProducts() } }
                            .buttonStyle(.larderSecondary)
                    }
                }
                status
                actions
            }
            .padding(gutter)
        }
    }

    private var pitch: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.l) {
            Image(systemName: "sparkles")
                .font(LarderFont.body(.title, weight: .semibold))
                .foregroundStyle(LarderColor.ink.onAccent)
                .frame(width: 64, height: 64)
                .background(LarderColor.accent.brand, in: RoundedRectangle(cornerRadius: LarderRadius.panel, style: .continuous))
                .accessibilityHidden(true)
            Text(Copy.Plus.name)
                .font(LarderFont.display(.largeTitle))
                .foregroundStyle(LarderColor.ink.primary)
                .accessibilityAddTraits(.isHeader)
            BodyText(Copy.Plus.pitch)
            PaperCard {
                VStack(alignment: .leading, spacing: LarderSpacing.m) {
                    ForEach(AccountCopy.Paywall.features, id: \.text) { feature in
                        Label {
                            BodyText(feature.text)
                        } icon: {
                            Image(systemName: feature.symbol)
                                .foregroundStyle(LarderColor.accent.second)
                        }
                    }
                    HintText(AccountCopy.Paywall.staysFree)
                }
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        if entitlements.isAwaitingApproval {
            Label(AccountCopy.Paywall.pending, systemImage: "hourglass")
                .font(LarderFont.body(.body))
                .foregroundStyle(LarderColor.ink.primary)
        }
        if let error = entitlements.error {
            Label(AccountCopy.message(for: error), systemImage: "exclamationmark.triangle")
                .font(LarderFont.body(.body))
                .foregroundStyle(LarderColor.status(.danger))
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.s) {
            Button(action: onDismiss) {
                Text(Copy.Action.notNow).frame(maxWidth: .infinity)
            }
            .buttonStyle(.larderSecondary)
            Button(Copy.Plus.restore) { Task { await entitlements.restore() } }
                .buttonStyle(.larderQuiet)
                .disabled(entitlements.isLoading)
            HintText(AccountCopy.Paywall.renews)
            HStack(spacing: LarderSpacing.l) {
                if let terms = LegalLinks.terms {
                    Link(AccountCopy.Paywall.terms, destination: terms)
                }
                if let privacy = LegalLinks.privacy {
                    Link(AccountCopy.Paywall.privacy, destination: privacy)
                }
            }
            .font(LarderFont.body(.footnote))
            .foregroundStyle(LarderColor.accent.second)
            .frame(minHeight: 44)
        }
    }
}

#if os(iOS)
private extension View {
    /// Links a store policy to its page, when the page has an address.
    @ViewBuilder
    func policyDestination(_ url: URL?, for policy: SubscriptionStorePolicyKind) -> some View {
        if let url {
            subscriptionStorePolicyDestination(url: url, for: policy)
        } else {
            self
        }
    }
}
#endif

#if DEBUG
#Preview("Paywall") {
    let entitlements = PreviewSupport.entitlements()
    PaywallView(entitlements: entitlements, onDismiss: {})
        .task { await entitlements.start() }
}
#endif
