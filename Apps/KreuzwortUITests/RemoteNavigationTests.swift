import XCTest

/// Bedienbarkeit mit der Apple-TV-Fernbedienung.
///
/// **Warum es diesen Test gibt.** Die tvOS-Fassung war gebaut, gerendert und
/// eingereicht — aber nie *bedient*. Von außen geht das nicht: `osascript` hat
/// auf der Baumaschine keine Berechtigung für Tastatureingaben, die
/// Simulator-Steuerung antwortet mit `touchUnsupportedOnAppleTV`, und `simctl`
/// kennt überhaupt keine Eingabe. `XCUIRemote` läuft **im** Simulator und ist
/// damit der einzige Weg.
///
/// Gefunden hat das Fehlen dieser Prüfung erst die Ablehnung durch Apple.
final class RemoteNavigationTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try XCTSkipUnless(isTV, "Fernbedienung gibt es nur auf tvOS")
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    private var isTV: Bool {
        #if os(tvOS)
        true
        #else
        false
        #endif
    }

    /// Bewegt den Fokus, bis das Element den Fokus hat — oder gibt auf.
    ///
    /// Die Fokus-Engine braucht je Schritt einen Moment; ohne Warten meldet die
    /// Abfrage den alten Stand.
    @discardableResult
    private func focus(_ element: XCUIElement, pressing button: XCUIRemote.Button,
                       limit: Int = 12) -> Bool {
        for _ in 0 ..< limit {
            if element.exists, element.hasFocus { return true }
            XCUIRemote.shared.press(button)
            usleep(400_000)
        }
        return element.exists && element.hasFocus
    }

    /// Wie viele Gitterzellen sind leer?
    ///
    /// **Warum nicht nach dem Buchstaben gefragt wird.** Zwei Anläufe haben
    /// hier das falsche Signal geprüft: `staticTexts["A"]` gibt es nie (die
    /// Zelle trägt eine zusammengesetzte Beschriftung), und „, A, Teil von"
    /// steht nur an Zellen, die in der *aktuellen* Richtung zu einem Wort
    /// gehören. Dazu kommt, dass `newPuzzle()` den Seed aus der Uhrzeit zieht
    /// — **jeder Lauf spielt ein anderes Rätsel**. Eine Prüfung, die von der
    /// Lage einer bestimmten Zelle abhängt, ist damit ein Münzwurf.
    ///
    /// Die Zahl der leeren Zellen ist von alldem unabhängig: sie muss mit
    /// jedem eingetragenen Buchstaben sinken, in jedem Rätsel.
    private func emptyCells() -> Int {
        let needle = ", leer"
        return app.otherElements.matching(NSPredicate(
                   format: "label CONTAINS %@", needle)).count
             + app.staticTexts.matching(NSPredicate(
                   format: "label CONTAINS %@", needle)).count
    }

    /// Der Startbildschirm ist mit der Fernbedienung erreichbar und startet ein
    /// Rätsel.
    func testHomeScreenIsOperable() throws {
        let play = app.buttons["Losspielen"]
        XCTAssertTrue(play.waitForExistence(timeout: 20),
                      "Startbildschirm zeigt keinen Losspielen-Knopf")
        XCTAssertTrue(focus(play, pressing: .down),
                      "„Losspielen“ ließ sich mit der Fernbedienung nicht erreichen")
        XCUIRemote.shared.press(.select)
    }

    /// **Der eigentliche Prüfstein.** Im Rätsel muss sich der Fokus bewegen
    /// lassen und ein Buchstabe eintragbar sein. Genau das war der Verdacht bei
    /// der Ablehnung: ein fokussierbarer Container über dem ganzen Bildschirm
    /// kann den Fokus schlucken, sodass weder Gitter noch Buchstabenleiste
    /// erreichbar sind.
    func testPuzzleIsPlayableWithTheRemote() throws {
        let play = app.buttons["Losspielen"]
        XCTAssertTrue(play.waitForExistence(timeout: 20))
        XCTAssertTrue(focus(play, pressing: .down))
        XCUIRemote.shared.press(.select)

        // Das Gitter braucht einen Moment: das Rätsel wird erzeugt.
        let letterA = app.buttons["A"]
        XCTAssertTrue(letterA.waitForExistence(timeout: 60),
                      "Buchstabenleiste erscheint nicht — ohne sie ist auf dem "
                      + "Fernseher keine Eingabe möglich")

        // **Keine Abfrage über alle Nachfahren.** Zwei Anläufe sind daran
        // gescheitert („Failed to get matching snapshots: Timed out while
        // evaluating UI query") — auch mit Prädikat, weil XCTest den ganzen
        // Baum abbilden muss und ein 169-Zellen-Gitter dafür zu groß ist.
        //
        // Die Frage „hat irgendetwas den Fokus" ist ohnehin die schwächere. Was
        // zählt, ist ob ein Spieler die Buchstabenleiste **erreicht** — und das
        // prüft der Schritt darunter mit billigen Einzelabfragen. Hat nichts den
        // Fokus, bewirken die Tastendrücke nichts und er schlägt fehl.
        // Bis zur Buchstabenleiste und einen Buchstaben setzen.
        // 40 statt 20: ein Gitter hat bis zu 13 Reihen, darunter liegen
        // Frageleiste und Hilfeknöpfe. Bleibt es auch dann erfolglos, steckt
        // der Fokus fest — das unterscheidet „zu weit" von „blockiert".
        XCTAssertTrue(focus(letterA, pressing: .down, limit: 40),
                      "Buchstabe „A“ ließ sich nicht fokussieren")

        // **Der Buchstabe muss im Gitter ankommen.** Ihn nur fokussieren zu
        // können beweist noch nicht, dass gespielt werden kann: dazwischen
        // liegen Cursor, Eingaberouter und Zellendarstellung.
        let vorher = emptyCells()
        XCTAssertGreaterThan(vorher, 0, "Kein leeres Feld gefunden — die "
                             + "Abfrage trifft nichts, der Test prüft nichts")
        XCUIRemote.shared.press(.select)
        usleep(800_000)
        let nachA = emptyCells()
        XCTAssertLessThan(nachA, vorher,
                          "Nach dem Drücken ist kein Feld gefüllt — die "
                          + "Fernbedienung kann nichts eintragen")

        // Und ein zweiter Buchstabe: das beweist, dass der Fokus auf der
        // Leiste bleibt und der Cursor weiterrückt. Vorher riss jeder
        // Buchstabe den Fokus zurück ins Gitter.
        let letterB = app.buttons["B"]
        XCTAssertTrue(focus(letterB, pressing: .right, limit: 4),
                      "Buchstabe „B“ liegt rechts neben „A“, war aber nicht "
                      + "erreichbar — der Fokus hat die Leiste verlassen")
        XCUIRemote.shared.press(.select)
        usleep(800_000)
        XCTAssertLessThan(emptyCells(), nachA,
                          "Der zweite Buchstabe kam nicht an")
    }
}
