import XCTest

// **Nicht für tvOS.** Dort wird mit `XCUIRemote` geprüft
// (RemoteNavigationTests); ein Tipp auf eine Fläche gibt es dort nicht.
#if !os(tvOS)

/// Eingabe per Finger.
///
/// **Warum es diesen Test gibt.** Die Buchstabenleiste war als Lösung für den
/// Fernseher gebaut und an `hasFocusEngine` geknüpft. Auf dem iPhone gab es
/// sie deshalb nicht — und sonst auch nichts: keine Bildschirmtastatur, kein
/// `TextField`, und `onKeyPress` antwortet nur auf echte Tasten. Gemessen
/// zählte der Rätselbildschirm **sieben Knöpfe**, davon keiner ein Buchstabe.
/// Ins Gitter kam man nur über „Buchstabe aufdecken".
///
/// Aufgefallen ist das durch eine Frage, nicht durch einen Test. Diesen hier
/// gibt es, damit die nächste Antwort darauf gemessen ist.
final class TouchInputTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    /// Wie viele Gitterzellen sind leer?
    ///
    /// Gezählt wird über beide Elementtypen: ob eine Zelle als `otherElement`
    /// oder als `staticText` im Baum steht, wechselt zwischen Läufen.
    private func emptyCells() -> Int {
        let needle = ", leer"
        // **Drei Typen.** Wo eine Zelle im Baum landet, wechselt: als
        // `otherElement`, als `staticText` — und seit sie ein `Button` ist,
        // auch dort. Ein Anlauf, der nur einen Typ fragte, meldete
        // verlässlich null und ließ eine funktionierende App durchfallen.
        return app.otherElements.matching(NSPredicate(
                   format: "label CONTAINS %@", needle)).count
             + app.staticTexts.matching(NSPredicate(
                   format: "label CONTAINS %@", needle)).count
             + app.buttons.matching(NSPredicate(
                   format: "label CONTAINS %@", needle)).count
    }

    func testLetterCanBeEnteredWithoutAKeyboard() throws {
        let play = app.buttons["Losspielen"]
        XCTAssertTrue(play.waitForExistence(timeout: 40),
                      "Startbildschirm zeigt keinen Losspielen-Knopf")
        play.tap()

        let letterA = app.buttons["A"]
        XCTAssertTrue(letterA.waitForExistence(timeout: 90),
                      "Keine Buchstabenleiste — ohne Tastatur gibt es dann "
                      + "überhaupt keinen Weg, einen Buchstaben einzutragen")

        let vorher = emptyCells()
        XCTAssertGreaterThan(vorher, 0, "Kein leeres Feld gefunden — die "
                             + "Abfrage trifft nichts, der Test prüft nichts")
        letterA.tap()
        usleep(800_000)
        XCTAssertLessThan(emptyCells(), vorher,
                          "Nach dem Tippen ist kein Feld gefüllt")
    }

    /// Die Hilfeknöpfe müssen einen Namen haben.
    ///
    /// Sie tragen nur ein Symbol; den Titel blendet `LabelStyleForSurface` auf
    /// schmalen Flächen aus. Eine Zeit lang blendete er ihn **auch für
    /// VoiceOver** aus: gemessen hatten alle fünf Knöpfe eine leere
    /// Beschriftung. Für das Auge unsichtbar, für die Bedienung fatal.
    func testControlsAreNamed() throws {
        let play = app.buttons["Losspielen"]
        XCTAssertTrue(play.waitForExistence(timeout: 40))
        play.tap()
        XCTAssertTrue(app.buttons["A"].waitForExistence(timeout: 90))

        let ohneNamen = app.buttons.allElementsBoundByIndex
            .filter { $0.label.trimmingCharacters(in: .whitespaces).isEmpty }
        XCTAssertTrue(ohneNamen.isEmpty,
                      "\(ohneNamen.count) Knöpfe ohne Beschriftung — "
                      + "VoiceOver liest dort nur „Taste“")
    }
}
#endif
