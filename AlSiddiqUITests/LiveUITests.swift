import XCTest

/// CI only, against the REAL database with throwaway passwords: the passwords are TYPED into the real screens.
/// Passwords arrive as environment variables (TEST_RUNNER_*); screenshots and results go to SHOTS_DIR.
final class LiveUITests: XCTestCase {
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
            try? (results.joined(separator: "\n") + "\n").write(to: URL(fileURLWithPath: dir).appendingPathComponent("uitest_results.txt"), atomically: true, encoding: .utf8)
        }
    }
    private func text(_ app: XCUIApplication, _ contains: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", contains)).firstMatch
    }
    private func button(_ app: XCUIApplication, _ contains: String) -> XCUIElement {
        _ = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", contains)).firstMatch.waitForExistence(timeout: 8)
        let b = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", contains)).firstMatch
        return b.exists ? b : text(app, contains)
    }
    private func type(_ app: XCUIApplication, _ value: String) {
        let f = app.secureTextFields["passwordField"]
        _ = f.waitForExistence(timeout: 20)
        f.tap()
        sleep(1)
        if !f.hasFocus { f.tap(); sleep(1) }
        f.typeText(value)
        note("typed \(value.count) chars, field shows \((f.value as? String)?.count ?? -1)")
        let b = app.buttons["loginButton"]
        if b.exists { b.tap() } else { f.typeText("\n") }
    }

    func testPasswordsTypedOnRealScreens() throws {
        continueAfterFailure = true
        let vp = env["VP"] ?? "", ap = env["AP"] ?? "", tp = env["TP"] ?? ""
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA", "-forceDemo", "NO", "-autoLogin", "none"]
        app.launch()

        // 1) the opening screen: one password field
        let field = app.secureTextFields["passwordField"]
        note("password screen: \(field.waitForExistence(timeout: 40))")
        shot("21_cloud_password_screen")

        // 2) a wrong password -> the server's Arabic answer
        type(app, "wrong-pass-x1")
        let err = app.staticTexts["loginError"]
        sleep(2)
        note("wrong password error shown: \(err.waitForExistence(timeout: 25)) text=\(err.exists ? err.label : "-")")
        shot("22_cloud_wrong_password")

        // 3) the general password -> read-only view
        type(app, vp)
        let banner = text(app, "وضع العرض")
        note("general password -> viewer home: \(banner.waitForExistence(timeout: 40))")
        if !banner.exists { note("TREE:\n" + app.debugDescription.prefix(6000)) }
        shot("23_cloud_viewer_home")

        // 4) Settings -> two big buttons
        button(app, "الإعدادات").tap()
        let tBtn = app.buttons["btnTeachers"]
        note("settings with الإدارة/المعلمين: \(tBtn.waitForExistence(timeout: 15)) admin=\(app.buttons["btnAdmin"].exists)")
        shot("24_cloud_viewer_settings")

        // 5) «المعلمين» box refuses the admin password, accepts the teachers' password
        tBtn.tap()
        _ = app.secureTextFields["passwordField"].waitForExistence(timeout: 15)
        shot("25_cloud_teachers_password_screen")
        type(app, ap)
        let err2 = app.staticTexts["loginError"]
        note("teachers box with the ADMIN password refused: \(err2.waitForExistence(timeout: 25)) text=\(err2.exists ? err2.label : "-")")
        shot("26_cloud_teachers_box_refuses_admin")
        type(app, tp)
        let tStrip = text(app, "قسم المعلمين")
        note("teachers' password -> teachers section: \(tStrip.waitForExistence(timeout: 40))")
        sleep(3)
        shot("27_cloud_teacher_home")
        let c2 = button(app, "TEST حلقة ب")
        if c2.waitForExistence(timeout: 5) { c2.tap(); sleep(2); note("teacher circle picker -> circle B: ok"); shot("28_cloud_teacher_circle_b") }
        else { note("teacher circle picker: circle B chip not found") }

        // 6) leave -> back to the general view; «الإدارة» with the admin password
        let leave = app.buttons["leaveRole"]
        if leave.waitForExistence(timeout: 10) { leave.tap() }
        note("leave -> general view: \(text(app, "وضع العرض").waitForExistence(timeout: 20))")
        button(app, "الإعدادات").tap()
        let aBtn = app.buttons["btnAdmin"]
        if aBtn.waitForExistence(timeout: 15) { aBtn.tap() }
        type(app, ap)
        let aStrip = text(app, "قسم الإدارة")
        note("admin password -> admin section: \(aStrip.waitForExistence(timeout: 40))")
        sleep(3)
        shot("29_cloud_admin_home")
        button(app, "الإدارة").tap()
        sleep(2)
        shot("30_cloud_admin_panel")
        note("done")
    }
}
