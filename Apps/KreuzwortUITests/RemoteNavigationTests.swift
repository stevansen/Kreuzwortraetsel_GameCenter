import XCTest

// **Übersetzt nur für tvOS.** `XCUIRemote` gibt es auf keiner anderen
// Plattform; ein `XCTSkip` zur Laufzeit kommt zu spät, die Datei scheitert
// schon beim Übersetzen. Aufgefallen, als dasselbe Testziel einmal gegen
// einen iPhone-Simulator lief.
#if os(tvOS)

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

        // **Die Oberfläche muss währenddessen ansprechbar bleiben.** Das
        // Rätsel wird erst beim Druck erzeugt, und das dauert. Lief die
        // Erzeugung auf dem Hauptthread, stand der Bildschirm still: gemessen
        // 6,4 s ohne Fortschrittsanzeige und ohne Reaktion auf die
        // Fernbedienung — auf einem Apple TV, der ein Vielfaches langsamer
        // rechnet als der Mac unter diesem Simulator, wirkt das wie ein
        // Absturz.
        //
        // Geprüft wird nicht die Dauer der Erzeugung — die hängt vom Seed ab,
        // und jeder Lauf zieht einen anderen — sondern ob eine billige
        // Abfrage rechtzeitig antwortet. Bei blockiertem Hauptthread tut sie
        // das nicht.
        let vorAbfrage = Date()
        _ = app.staticTexts.firstMatch.exists
        let dauer = Date().timeIntervalSince(vorAbfrage)
        XCTAssertLessThan(dauer, 5,
                          "Die Oberfläche antwortet während der Erzeugung "
                          + "nicht (\(dauer) s) — der Hauptthread ist belegt")

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

    /// **Der neue Weg: Feld wählen führt zur Eingabe, „zurück“ aufs Feld.**
    ///
    /// Vorher waren das zwei getrennte Wanderungen quer über den Bildschirm —
    /// erst die Zelle ansteuern, dann zu den Buchstaben laufen, für den
    /// nächsten Buchstaben wieder zurück. Jetzt ist es dieselbe Geste wie auf
    /// dem Telefon.
    func testSelectingACellOpensTheLetters() throws {
        let play = app.buttons["Losspielen"]
        XCTAssertTrue(play.waitForExistence(timeout: 20))
        XCTAssertTrue(focus(play, pressing: .down))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["A"].waitForExistence(timeout: 60))

        // Ins Gitter. Gitterzellen sind keine Knöpfe — steht kein Knopf im
        // Fokus, ist der Fokus dort.
        //
        // Die Richtung wird gewechselt, weil der Startpunkt nicht feststeht:
        // ein erster Anlauf drückte zehnmal „hoch" und blieb dabei in der
        // Buchstabenspalte, die selbst zehn Reihen hat.
        var imGitter = false
        let weg: [XCUIRemote.Button] = [.right, .up, .right, .up, .up, .right,
                                        .up, .up, .right, .up, .up, .right]
        for taste in weg {
            if imGitterFokussiert() { imGitter = true; break }
            XCUIRemote.shared.press(taste)
            usleep(500_000)
        }
        if !imGitter { imGitter = imGitterFokussiert() }
        XCTAssertTrue(imGitter, "Das Gitter ließ sich nicht ansteuern — "
                      + "im Fokus steht \(fokussierteKnöpfe())")

        print("VOR AUSWAHL: \(fokussierteKnöpfe())")
        // Auswählen muss zur Buchstabenauswahl führen.
        XCUIRemote.shared.press(.select)
        usleep(700_000)
        let nachAuswahl = fokussierteKnöpfe()
        XCTAssertTrue(nachAuswahl.contains { $0.count == 1 },
                      "Nach dem Auswählen einer Zelle steht kein Buchstabe im "
                      + "Fokus, sondern \(nachAuswahl)")

        // Eintragen — der Buchstabe muss ankommen.
        let vorher = emptyCells()
        XCUIRemote.shared.press(.select)
        usleep(800_000)
        XCTAssertLessThan(emptyCells(), vorher, "Der Buchstabe kam nicht an")

        // Zurück aufs Spielfeld.
        XCUIRemote.shared.press(.menu)
        usleep(800_000)
        XCTAssertTrue(imGitterFokussiert(),
                      "„Zurück“ führt nicht ins Gitter — im Fokus steht noch "
                      + "\(fokussierteKnöpfe())")
    }

    /// Welche Knöpfe haben gerade den Fokus?
    ///
    /// Nur über `buttons`: eine Abfrage über alle Nachfahren läuft an einem
    /// 169-Zellen-Gitter in die Zeitüberschreitung.
    /// Steht der Fokus auf einer Gitterzelle?
    ///
    /// Erkennbar an der Beschriftung „Zeile r, Spalte c, …". Seit die Zellen
    /// Knöpfe sind, ist das eine genauere Auskunft als die frühere Hilfsregel
    /// „kein Knopf im Fokus, also im Gitter".
    private func imGitterFokussiert() -> Bool {
        fokussierteKnöpfe().contains { $0.hasPrefix("Zeile ") }
    }

    private func fokussierteKnöpfe() -> [String] {
        app.buttons.allElementsBoundByIndex.filter { $0.hasFocus }.map { $0.label }
    }
}
#endif
