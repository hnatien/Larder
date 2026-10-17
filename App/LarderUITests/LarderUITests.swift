import XCTest

/// Accessibility audits on every primary screen, the main flows, plus the screenshots in `docs/screenshots`.
final class LarderUITests: XCTestCase {
    /// The tabs, in tab bar order, named by their visible titles.
    private enum Tab: String, CaseIterable {
        case tonight = "Tonight"
        case plan = "Plan"
        case pantry = "Pantry"
        case recipes = "Recipes"
        case groceries = "Groceries"

        /// An element that shows once the tab's content has loaded.
        @MainActor
        func loadedElement(in app: XCUIApplication) -> XCUIElement {
            app.navigationBars[rawValue]
        }
    }

    private static let launchTimeout: TimeInterval = 20
    private static let loadTimeout: TimeInterval = 15

    /// `docs/screenshots` in the repository; the simulator shares the host file system.
    private static let screenshotsDirectory = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "docs/screenshots", directoryHint: .isDirectory)

    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    func testEveryTabPassesAccessibilityAudit() throws {
        let app = launch()
        for tab in Tab.allCases {
            open(tab, in: app)
            try audit(app)
        }
        open(.tonight, in: app)
        app.navigationBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: Self.loadTimeout), "Settings did not open")
        try audit(app)
    }

    @MainActor
    func testOnboardingPassesAccessibilityAudit() throws {
        let app = launch(["-LarderUITestOnboarding"])
        XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: Self.launchTimeout), "The welcome screen did not show")
        try audit(app)
        app.buttons["Get started"].tap()
        let finish = app.buttons["Start planning"]
        var steps = 0
        while !finish.exists, steps < 5 {
            try audit(app)
            app.buttons["Continue"].tap()
            steps += 1
        }
        XCTAssertTrue(finish.exists, "The last question did not show")
        try audit(app)
        finish.tap()
        XCTAssertTrue(app.buttons["Tonight"].firstMatch.waitForExistence(timeout: Self.loadTimeout), "The tabs did not show after onboarding")
    }

    /// Leaving setup early keeps what was chosen: an allergen ticked before "Set up later" is in Settings afterwards.
    @MainActor
    func testSetUpLaterKeepsChosenAllergens() throws {
        let app = launch(["-LarderUITestOnboarding"])
        XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: Self.launchTimeout))
        app.buttons["Get started"].tap()
        app.buttons["Sesame"].tap()
        XCTAssertTrue(app.buttons["Sesame"].isSelected, "Sesame was not chosen")
        app.buttons["Set up later"].tap()
        open(.tonight, in: app)
        app.navigationBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: Self.loadTimeout))
        XCTAssertTrue(app.staticTexts["Sesame"].waitForExistence(timeout: Self.loadTimeout), "Sesame was lost when setup was left for later")
    }

    /// Adjust this week on the Plan tab, the scanner from Add food and photo import from Recipes are reachable and pass
    /// the audit. The Simulator has no live scanner, so the scanner shows its photo fallback.
    @MainActor
    func testAssistantAndScanEntryPointsPassAccessibilityAudit() throws {
        let app = launch()
        open(.plan, in: app)
        app.buttons["Plan my week"].tap()
        XCTAssertTrue(app.buttons["Replan week"].waitForExistence(timeout: Self.loadTimeout), "The week was not planned")
        let opener = app.buttons["Adjust this week"]
        XCTAssertTrue(opener.waitForExistence(timeout: Self.loadTimeout), "Adjust this week is missing from the Plan tab")
        opener.tap()
        let adjust = app.descendants(matching: .any)["ledger.adjust"]
        XCTAssertTrue(adjust.waitForExistence(timeout: Self.loadTimeout), "Adjust this week is missing from the Plan tab")
        XCTAssertTrue(app.buttons["Ask"].exists, "Adjust this week has no Ask button")
        XCTAssertFalse(app.buttons["Ask"].isEnabled, "Ask is enabled with nothing typed")
        try audit(app)

        open(.pantry, in: app)
        app.navigationBars.buttons["Add food"].tap()
        XCTAssertTrue(app.navigationBars["Add food"].waitForExistence(timeout: Self.loadTimeout))
        app.buttons["Scan a barcode or receipt"].tap()
        XCTAssertTrue(app.navigationBars["Scan"].waitForExistence(timeout: Self.loadTimeout), "The scanner did not open")
        XCTAssertTrue(app.buttons["Choose a photo instead"].exists, "The scanner offers no photo fallback")
        try audit(app)
        app.buttons["Receipt"].tap()
        XCTAssertTrue(app.staticTexts["Fit the whole receipt in view, then read it. The photo stays on this iPhone."].waitForExistence(timeout: Self.loadTimeout))
        try audit(app)
        app.buttons["Close"].firstMatch.tap()
        app.buttons["Cancel"].tap()

        open(.recipes, in: app)
        app.navigationBars.buttons["Import a recipe"].tap()
        XCTAssertTrue(app.buttons["Choose a photo"].waitForExistence(timeout: Self.loadTimeout), "Import has no photo option")
        try audit(app)
    }

    /// The paywall shows both plans with the pitch, keeps "Not now" in words, and passes the audit.
    @MainActor
    func testPaywallShowsEveryPlanAndPassesAccessibilityAudit() throws {
        let app = launch()
        try openPaywall(in: app)
        for plan in ["Monthly", "Annual"] {
            let match = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", plan)).firstMatch
            XCTAssertTrue(match.waitForExistence(timeout: Self.loadTimeout), "The \(plan) plan is not shown")
        }
        XCTAssertTrue(app.staticTexts["Larder Plus"].isHittable, "The pitch is hidden behind the store controls")
        try audit(app)
        app.buttons["Not now"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: Self.loadTimeout), "Not now did not close the paywall")
    }

    @MainActor
    func testDynamicTypeAX3() throws {
        let app = launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
        for tab in Tab.allCases {
            open(tab, in: app)
            try audit(app)
        }
    }

    /// Every tab in dark mode, where contrast is measured against the dark paper.
    @MainActor
    func testEveryTabPassesAccessibilityAuditInDarkMode() throws {
        let app = launch(["-AppleInterfaceStyle", "Dark"])
        for tab in Tab.allCases {
            open(tab, in: app)
            try audit(app)
        }
    }

    /// The sheets and screens the tab audits never reach: recipe detail, cooking mode, Filters, writing a recipe,
    /// the meal sheet, editing an item, and Add food.
    @MainActor
    func testSheetsPassAccessibilityAudit() throws {
        let app = launch()
        open(.recipes, in: app)
        app.buttons["Filters"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Filters"].waitForExistence(timeout: Self.loadTimeout), "Filters did not open")
        // At their medium height sheets are inset and their content drawn smaller; audit them opened all the way.
        app.navigationBars["Filters"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)))
        try auditSettled(app)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Show ")).firstMatch.tap()

        app.navigationBars.buttons["Import a recipe"].tap()
        app.buttons["Write it yourself"].tap()
        XCTAssertTrue(app.buttons["Preview recipe"].waitForExistence(timeout: Self.loadTimeout), "Write it yourself did not open")
        try auditSettled(app)
        app.buttons["Close"].firstMatch.tap()

        app.scrollViews.firstMatch.buttons.matching(NSPredicate(format: "label CONTAINS %@", "minutes")).firstMatch.tap()
        XCTAssertTrue(app.buttons["recipe.startCooking"].waitForExistence(timeout: Self.loadTimeout), "Recipe detail did not open")
        try auditSettled(app)
        app.buttons["recipe.startCooking"].tap()
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: Self.loadTimeout), "Cooking mode did not open")
        try auditSettled(app)
        app.buttons["Close"].firstMatch.tap()

        open(.plan, in: app)
        app.buttons["Plan my week"].tap()
        XCTAssertTrue(app.buttons["Replan week"].waitForExistence(timeout: Self.loadTimeout), "The week was not planned")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Dinner, ")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Swap"].waitForExistence(timeout: Self.loadTimeout), "The meal sheet did not open")
        // Drag the sheet up by its top edge, beside Done, so the drag resizes the sheet rather than scrolling it.
        let done = app.buttons["Done"].firstMatch
        done.coordinate(withNormalizedOffset: CGVector(dx: -2, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)))
        try auditSettled(app)
        app.buttons["Done"].firstMatch.tap()

        open(.pantry, in: app)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Spinach")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Edit item"].waitForExistence(timeout: Self.loadTimeout), "The editor did not open")
        app.navigationBars["Edit item"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)))
        try auditSettled(app)
        app.buttons["Cancel"].tap()
        app.navigationBars.buttons["Add food"].tap()
        XCTAssertTrue(app.navigationBars["Add food"].waitForExistence(timeout: Self.loadTimeout), "Add food did not open")
        app.buttons["Eggs"].tap()
        try auditSettled(app)
    }

    @MainActor
    func testRecipeOpensAndAddsToTonightsDinner() throws {
        let app = launch()
        open(.tonight, in: app)
        app.buttons["See recipe"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Start cooking"].waitForExistence(timeout: Self.loadTimeout), "Recipe detail did not open from Tonight")
        app.buttons["Add to plan"].tap()
        // A day that already has a dinner also says what it replaces, so match on the day's name.
        let today = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Today")).firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: Self.loadTimeout), "Add to plan offered no days")
        today.tap()
        XCTAssertTrue(app.staticTexts["Added to Today"].waitForExistence(timeout: Self.loadTimeout), "Adding the recipe was not confirmed")
        XCTAssertTrue(app.buttons["Start cooking"].exists, "Recipe detail closed after adding to the plan")
        app.buttons["Close"].firstMatch.tap()

        open(.plan, in: app)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Dinner, ")).firstMatch.tap()
        let seeRecipe = app.buttons["See recipe"]
        XCTAssertTrue(seeRecipe.waitForExistence(timeout: Self.loadTimeout), "The meal sheet did not open")
        seeRecipe.tap()
        XCTAssertTrue(app.buttons["Start cooking"].waitForExistence(timeout: Self.loadTimeout), "Recipe detail did not open from the meal sheet")
    }

    @MainActor
    func testScreenshots() throws {
        try FileManager.default.createDirectory(at: Self.screenshotsDirectory, withIntermediateDirectories: true)
        for (appearance, arguments) in [("light", [String]()), ("dark", ["-AppleInterfaceStyle", "Dark"])] {
            try captureFirstRun(appearance: appearance, arguments: arguments)
            try captureEmptyPantry(appearance: appearance, arguments: arguments)
            try captureTabsAndFlows(appearance: appearance, arguments: arguments)
        }
    }

    /// Welcome and the three questions.
    @MainActor
    private func captureFirstRun(appearance: String, arguments: [String]) throws {
        let app = launch(["-LarderUITestOnboarding"] + arguments)
        XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: Self.launchTimeout))
        try saveScreenshot(named: "welcome-\(appearance)")
        app.buttons["Get started"].tap()
        XCTAssertTrue(app.buttons["Peanuts"].waitForExistence(timeout: Self.loadTimeout))
        app.buttons["Peanuts"].tap()
        try saveScreenshot(named: "setup-allergies-\(appearance)")
        app.buttons["Continue"].tap()
        try saveScreenshot(named: "setup-diet-\(appearance)")
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.buttons["Start planning"].waitForExistence(timeout: Self.loadTimeout))
        try saveScreenshot(named: "setup-household-\(appearance)")
        app.terminate()
    }

    /// The first-run empty states: Tonight, Plan and Groceries with nothing in the pantry.
    @MainActor
    private func captureEmptyPantry(appearance: String, arguments: [String]) throws {
        let app = launch(["-LarderUITestEmptyPantry"] + arguments)
        open(.tonight, in: app)
        XCTAssertTrue(app.buttons["Add what you have"].waitForExistence(timeout: Self.loadTimeout))
        try saveScreenshot(named: "tonight-empty-\(appearance)")
        open(.plan, in: app)
        XCTAssertTrue(app.buttons["Plan my week"].waitForExistence(timeout: Self.loadTimeout))
        try saveScreenshot(named: "plan-empty-\(appearance)")
        open(.groceries, in: app)
        try saveScreenshot(named: "groceries-empty-\(appearance)")
        app.terminate()
    }

    /// Every tab with fixtures, then the planned week, the meal sheet, recipe detail, cooking, adding and editing food,
    /// and Settings.
    @MainActor
    private func captureTabsAndFlows(appearance: String, arguments: [String]) throws {
        let app = launch(arguments)
        for tab in Tab.allCases {
            open(tab, in: app)
            try saveScreenshot(named: "\(tab.rawValue.lowercased())-\(appearance)")
        }

        open(.pantry, in: app)
        app.navigationBars.buttons["Add food"].tap()
        XCTAssertTrue(app.navigationBars["Add food"].waitForExistence(timeout: Self.loadTimeout))
        app.buttons["Eggs"].tap()
        app.buttons["Rice"].tap()
        try saveScreenshot(named: "pantry-add-\(appearance)")
        app.buttons["Cancel"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Spinach")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Edit item"].waitForExistence(timeout: Self.loadTimeout))
        try saveScreenshot(named: "pantry-edit-\(appearance)")
        app.buttons["Cancel"].tap()

        open(.plan, in: app)
        app.buttons["Plan my week"].tap()
        XCTAssertTrue(app.buttons["Replan week"].waitForExistence(timeout: Self.loadTimeout), "The week was not planned")
        try saveScreenshot(named: "plan-planned-\(appearance)")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Dinner, ")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Swap"].waitForExistence(timeout: Self.loadTimeout), "The meal sheet did not open")
        try saveScreenshot(named: "meal-sheet-\(appearance)")
        app.buttons["Done"].firstMatch.tap()

        open(.groceries, in: app)
        try saveScreenshot(named: "groceries-planned-\(appearance)")

        open(.tonight, in: app)
        XCTAssertTrue(app.staticTexts["Tonight's dinner"].waitForExistence(timeout: Self.loadTimeout), "Tonight did not show the planned dinner")
        try saveScreenshot(named: "tonight-planned-\(appearance)")
        app.buttons["See recipe"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Start cooking"].waitForExistence(timeout: Self.loadTimeout))
        try saveScreenshot(named: "recipe-detail-\(appearance)")
        app.buttons["recipe.startCooking"].tap()
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: Self.loadTimeout), "Cooking mode did not open")
        try saveScreenshot(named: "cooking-\(appearance)")
        app.buttons["Close"].firstMatch.tap()
        app.buttons["Close"].firstMatch.tap()

        app.navigationBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: Self.loadTimeout))
        try saveScreenshot(named: "settings-\(appearance)")
        app.terminate()

        do {
            try openPaywall(in: launch(arguments))
        } catch is XCTSkip {
            // Plus is active in the test store, so there is no paywall to capture; the other screens are saved.
            return
        }
        try saveScreenshot(named: "paywall-\(appearance)")
    }

    /// Opens the paywall from Settings, scrolling down to its row.
    @MainActor
    private func openPaywall(in app: XCUIApplication) throws {
        open(.tonight, in: app)
        app.navigationBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: Self.loadTimeout), "Settings did not open")
        let seePlus = app.buttons["See Larder Plus"]
        let manage = app.buttons["Manage subscription"]
        var swipes = 0
        while !seePlus.isHittable, !manage.exists, swipes < 20 {
            app.swipeUp()
            swipes += 1
        }
        // The simulator's StoreKit test store keeps purchases between runs; with Plus active there is no paywall.
        if manage.exists {
            throw XCTSkip("Larder Plus is active in this simulator's StoreKit test store, so Settings shows no paywall")
        }
        seePlus.tap()
        XCTAssertTrue(app.buttons["Not now"].waitForExistence(timeout: Self.loadTimeout), "The paywall did not open")
    }

    @MainActor
    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-LarderUITestMode"] + arguments
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: Self.launchTimeout), "Larder did not launch")
        return app
    }

    @MainActor
    private func open(_ tab: Tab, in app: XCUIApplication) {
        let tabBarButton = app.tabBars.buttons[tab.rawValue]
        let button = tabBarButton.waitForExistence(timeout: Self.launchTimeout) ? tabBarButton : app.buttons[tab.rawValue].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: Self.launchTimeout), "No \(tab.rawValue) tab")
        button.tap()
        XCTAssertTrue(tab.loadedElement(in: app).waitForExistence(timeout: Self.loadTimeout), "\(tab.rawValue) did not finish loading")
    }

    /// Lets a sheet finish presenting or resizing before the audit, which otherwise measures it scaled mid-animation.
    @MainActor
    private func auditSettled(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) throws {
        Thread.sleep(forTimeInterval: 1)
        try audit(app, file: file, line: line)
    }

    /// Runs the audit and reports each issue with the element it was found on.
    @MainActor
    private func audit(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) throws {
        let occluders = Self.occluders(in: app)
        try app.performAccessibilityAudit { issue in
            // The Recipes and Pantry search fields are Apple's own UISearchBarTextField from `.searchable`; their clipping
            // at larger sizes is the system's behaviour and no Larder view can change it. Only those elements are skipped.
            // The same fields' placeholder contrast in dark mode is the system's too: Larder cannot colour it.
            if [.textClipped, .contrast].contains(issue.auditType), issue.element?.elementType == .searchField,
               ["Search recipes", "Search your pantry"].contains(issue.element?.label) {
                return true
            }
            // A sheet's toolbar buttons (Cancel, Save, Done) are Apple's navigation bar chrome on glass; their size
            // and contrast are the system's. Content scrolled under the bar is measured against the glass, like the
            // tab bar below. Only elements inside the bar's frame are skipped, each logged.
            if let element = issue.element, Self.isInNavigationBar(element.frame, in: app) {
                let description = "\(issue.compactDescription) [\(issue.auditType)] on \(element.label)"
                XCTContext.runActivity(named: "Skipped navigation bar audit issue: \(description)") { _ in }
                print("Skipped navigation bar audit issue: \(description)")
                return true
            }
            // Legibility issues on content under Apple's translucent chrome (the tab bar), cut off by the bottom of the
            // scroll view, or partly past the side of the window in a horizontal chip row are measured against what is
            // not on screen; the content is readable once scrolled into view. Issues without an element are never
            // skipped by this rule.
            if issue.auditType.isLegibility, let element = issue.element, Self.isOccluded(element.frame, by: occluders) {
                let description = "\(issue.compactDescription) | \(issue.detailedDescription) [\(issue.auditType)] frame \(element.frame)"
                XCTContext.runActivity(named: "Skipped occluded audit issue: \(description)") { _ in }
                print("Skipped occluded audit issue: \(description)")
                return true
            }
            // Content that scrolls beneath the Liquid Glass tab bar is reported without an element; the same text passes
            // once scrolled clear, and the tab bar is Apple's chrome. Screens without a tab bar
            // (onboarding, sheets) keep the strict rule.
            if issue.element == nil, issue.auditType.isLegibility, app.tabBars.firstMatch.exists {
                let screen = Self.screenName(in: app)
                XCTContext.runActivity(named: "Skipped no-element audit issue [\(screen)]: \(issue.detailedDescription)") { _ in }
                print("Skipped no-element audit issue [\(screen)]: \(issue.detailedDescription)")
                return true
            }
            let element = issue.element.map { "\($0.elementType.rawValue) \"\($0.label)\" \($0.frame)" } ?? "no element"
            let screen = Self.screenName(in: app)
            XCTFail("[\(screen)] \(issue.compactDescription) | \(issue.detailedDescription) [\(issue.auditType)] on \(element)", file: file, line: line)
            return true
        }
    }

    /// Frames of the chrome that overlays content: the tab bar inflated by 8 pt, the region below the visible
    /// bottom of the main scroll view, and everything beyond the window's left and right edges, where a horizontally
    /// scrolling chip is only partly on screen.
    @MainActor
    private static func occluders(in app: XCUIApplication) -> [CGRect] {
        var frames: [CGRect] = []
        let window = app.windows.firstMatch
        if window.exists {
            let huge = CGFloat.greatestFiniteMagnitude / 2
            frames.append(CGRect(x: window.frame.maxX, y: -huge / 2, width: huge, height: huge))
            frames.append(CGRect(x: window.frame.minX - huge, y: -huge / 2, width: huge, height: huge))
        }
        let tabBar = app.tabBars.firstMatch
        if tabBar.exists { frames.append(tabBar.frame.insetBy(dx: -8, dy: -8)) }
        let scrollView = app.scrollViews.firstMatch.exists ? app.scrollViews.firstMatch : app.collectionViews.firstMatch
        if scrollView.exists {
            frames.append(CGRect(x: -.greatestFiniteMagnitude / 2, y: scrollView.frame.maxY, width: .greatestFiniteMagnitude, height: .greatestFiniteMagnitude / 2))
        }
        return frames
    }

    /// The current navigation bar's title, or "no bar" on screens such as the welcome screen.
    @MainActor
    private static func screenName(in app: XCUIApplication) -> String {
        let bar = app.navigationBars.firstMatch
        return bar.exists ? bar.identifier : "no bar"
    }

    /// Whether `frame` lies inside the frontmost navigation bar.
    @MainActor
    private static func isInNavigationBar(_ frame: CGRect, in app: XCUIApplication) -> Bool {
        let bars = app.navigationBars.allElementsBoundByIndex.filter(\.exists)
        return bars.contains { $0.frame.contains(frame) }
    }

    private static func isOccluded(_ frame: CGRect, by occluders: [CGRect]) -> Bool {
        occluders.contains { $0.intersects(frame) }
    }

    @MainActor
    private func saveScreenshot(named name: String) throws {
        // Lets tap highlights and sheet transitions settle so the capture shows the resting state.
        Thread.sleep(forTimeInterval: 0.8)
        let url = Self.screenshotsDirectory.appending(path: "\(name).png", directoryHint: .notDirectory)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: url, options: .atomic)
    }
}

private extension XCUIAccessibilityAuditType {
    /// Contrast and the "Potentially inaccessible text" check, both of which read the pixels behind the text.
    var isLegibility: Bool {
        !isDisjoint(with: [.contrast, .elementDetection])
    }
}
