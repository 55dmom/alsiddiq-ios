import XCTest

/// v3.8 (CI, demo data on the phone only): every settings / «الإدارة» / «المزيد» row opens its page, and «رجوع»
/// goes back to exactly that list — never to the «الأدوات» sheet (his bug report, Nov 8 10:24 PM).
final class NavBackUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private var results: [String] = []

    private func shot(_ name: String) {
        guard let dir = env["SHOTS_DIR"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
    }
    private func note(_ s: String) {
        results.append(s)
        NSLog("ALSIDDIQ_UITEST %@", s)
        if let dir = env["SHOTS_DIR"] {
            try? (results.joined(separator: "\n") + "\n").write(to: URL(fileURLWithPath: dir).appendingPathComponent("navback_results.txt"), atomically: true, encoding: .utf8)
        }
    }
    private func any(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func launch(_ who: String, _ route: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA", "-forceDemo", "YES", "-autoLogin", who, "-startRoute", route]
        app.launch()
        sleep(4)
        return app
    }

    private func back(_ app: XCUIApplication) -> Bool {
        for id in ["directBack"] {
            let b = app.buttons[id]
            if b.exists { b.tap(); return true }
        }
        let b = app.buttons.matching(NSPredicate(format: "label == %@", "رجوع")).firstMatch
        if b.exists { b.tap(); return true }
        let nb = app.navigationBars.buttons.firstMatch
        if nb.exists { nb.tap(); return true }
        return false
    }

    private func check(_ who: String, _ route: String, list marker: String, rows: [String], tag: String) {
        let app = launch(who, route)
        note("\(tag): list shown=\(any(app, marker).waitForExistence(timeout: 10))")
        for (k, row) in rows.enumerated() {
            let cell = any(app, row)
            if !cell.waitForExistence(timeout: 4) {
                app.swipeUp()
            }
            guard cell.waitForExistence(timeout: 4) else { note("\(tag) | \(row) | row not found"); continue }
            cell.tap()
            sleep(2)
            if k == 0 { shot("N_\(tag)_\(k)_open") }
            let tapped = back(app)
            sleep(2)
            let onList = any(app, marker).exists || any(app, row).exists
            let toolsSheet = app.buttons.matching(NSPredicate(format: "label == %@", "إغلاق")).firstMatch.exists
            note("\(tag) | \(row) | back tapped=\(tapped) | on the list again=\(onList) | tools sheet=\(toolsSheet) | \(onList && !toolsSheet ? "OK" : "FAIL")")
            if k == 0 || !(onList && !toolsSheet) { shot("N_\(tag)_\(k)_after_back") }
            if !onList || toolsSheet {
                // get back to the list for the next row
                let close = app.buttons.matching(NSPredicate(format: "label == %@", "إغلاق")).firstMatch
                if close.exists { close.tap(); sleep(1) }
            }
        }
    }

    func testAdminRowsReturnToTheList() throws {
        continueAfterFailure = true
        check("admin", "more", list: "كلمات السر", rows: ["الثيمات", "عن المركز", "تواصل مع المطوّر", "عن التطبيق", "المتفوقون", "حضور وغياب المعلمين", "الميزانية", "كشف الاشتراكات"], tag: "admin")
    }

    func testViewerSettingsReturnToTheList() throws {
        continueAfterFailure = true
        check("viewer", "viewer_settings", list: "قفل التطبيق", rows: ["الثيمات", "عن المركز", "تواصل مع المطوّر", "عن التطبيق"], tag: "viewer")
    }

    func testTeacherMoreReturnToTheList() throws {
        continueAfterFailure = true
        check("teacher", "teacher_more", list: "طالب جديد", rows: ["الثيمات", "عن المركز", "تواصل مع المطوّر", "كشف الاشتراكات"], tag: "teacher")
    }
}
