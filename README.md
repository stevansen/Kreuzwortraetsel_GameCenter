# Kreuzwort

Native Rätsel-App für iOS, iPadOS, macOS und tvOS mit **zwei Varianten** — klassisches
Kreuzworträtsel und Schwedenrätsel (Fragen im Gitter, Pfeile) —, prozeduraler
Rätselerzeugung, Game Center und geräteübergreifendem Spielstand.

Bundle-Prefix `com.kreuzwort.*` · CloudKit-Container `iCloud.com.kreuzwort`

## Die tragende Idee

Ein Rätsel wird **nie gespeichert oder übertragen** — nur sein Seed:

```
(seed, variant, difficulty, generatorVersion, catalogVersion)   ≈ 20 Bytes
```

Der Generator ist bit-exakt deterministisch, jedes Gerät regeneriert daraus
dasselbe Gitter. Daraus folgt fast alles Angenehme:

- **Tagesrätsel ohne Server**: `seed = SHA256("daily|" + Datum + "|" + Variante + "|" + Stufe)`.
  Alle Geräte weltweit erhalten dasselbe Rätsel — Voraussetzung für ein faires Leaderboard.
- **Spielstand-Sync** überträgt Seeds und Buchstaben, keine Gitter.
- **„Schick mir dieses Rätsel"** ist ein Link, kein Datentransfer.
- Unendlich viele Rätsel, ohne etwas auszuliefern.

Der Preis: Determinismus muss erzwungen werden. Drei Quellcode-Scans laufen als
Tests und bewachen das (siehe `SeamScanTests`):

1. kein `Date()`, `arc4random`, `hashValue` oder nicht-seedbarer Zufall in `PuzzleKit`
2. kein `if variant ==` außerhalb von `Layout/`
3. `PuzzleKit` importiert kein Foundation und kein Apple-Framework

Textbreiten kommen aus einer **eingecheckten Glyph-Tabelle**, nie aus CoreText:
beim Schwedenrätsel entscheidet die Breite eines Kurzclues, ob er in die Zelle
passt, und ist damit ein Füll-Constraint. Würde sie zur Laufzeit gemessen,
könnten iPhone und Mac aus demselben Seed unterschiedliche Rätsel bauen.

## Aufbau

```
Packages/
  PuzzleKit/      Modelle, Layouts, Füll-Engine, Validator, Scoring
                  — kein Foundation, kein Apple-Framework, baut für alle Zielplattformen
    Layout/       LayoutProvider (der Varianten-Seam) + ClassicLayout + Templatesuche
    Fill/         PatternIndex (Bitsets) + varianten-agnostische CSP-Engine
  ClueCatalog/    SQLite, Normalisierung, QA, Assembler, Häufigkeiten
  GameServices/   GameKit-Facade                       (M7)
  SyncKit/        ProgressStore lokal; CKSyncEngine folgt   (M8)
Tools/
  catalogbuild    Rohdaten → catalog.sqlite + Abdeckungsreport
  puzzlegen       Templatesuche, Generierung, ASCII-Vorschau, Diagnose
scripts/          Harvester (Wikipedia, Wiktionary, Leipzig), Breitentabelle
Resources/        Templates, Abkürzungsregeln, Glyph-Breiten
```

## Fragenkatalog

Drei Quellen, jede für das, was sie am besten kann:

| Quelle | Beitrag | Lizenz |
|---|---|---|
| **Deutsches Wiktionary** (Dump) | Definitionen — die besten Fragen | CC BY-SA 4.0 |
| **Wikidata / Wikipedia** | Kurzbeschreibungen, Eigennamen, Spezialwortschatz | CC0 / CC BY-SA 4.0 |
| **Leipzig Corpora Collection** | Worthäufigkeit auf der Zipf-Skala | CC BY 4.0 |

Vier Leipzig-Korpora unterschiedlicher Textsorten werden zusammengeführt
(71 Mio. Tokens): ein Nachrichtenkorpus allein kennt konkrete Substantive
schlecht. `ATTRIBUTION.md` wird beim Bau generiert.

**Harte Invariante:** Das Füllvokabular ist eine Teilmenge des Clue-Katalogs —
bei `arrow` zusätzlich eine Teilmenge der Antworten mit passendem Kurzclue. Ein
Wort ohne darstellbare Frage kommt nie ins Gitter.

Das Ambiguitätsgatter läuft **zweimal**: auf der Langform und nach dem Kürzen.
Kürzen erzeugt Mehrdeutigkeit — „Hauptstadt von Frankreich" → „Stadt" sieht
formal gültig aus und ist unbrauchbar.

## Synchronisierung

**Zusammengeführt wird lokal.** Kein Backend entscheidet, welche Fassung gewinnt:
`PuzzleProgress.merged` und `PlayerProfile.merged` tun das, und beide sind
kommutativ und idempotent. Die Reihenfolge, in der sich Geräte melden, ist
deshalb ohne Bedeutung.

**Optimistische Sperre, kein blindes Überschreiben.** Lädt ein Gerät hoch, ohne
vorher zu holen, wirft das Backend einen Konflikt und liefert den Server-Stand
mit. Der Coordinator führt zusammen und sendet einmal erneut. Ohne das verliert
ein Gerät die Daten des anderen — nicht lokal, aber in der Cloud und damit für
jedes dritte Gerät. Das ist CloudKits `serverRecordChanged`.

Das In-Memory-Backend führt einen Versionsstand **pro Datensatz**, so wie
CloudKit einen `recordChangeTag` je `CKRecord` führt. Eine globale Uhr ist zu
grob: nach einem Konflikt an einem Datensatz gälten sonst alle als bekannt, und
der Wiederholversuch scheitert am selben Konflikt.

**Nicht verifiziert:** `CloudKitSyncBackend` kompiliert und folgt dem
dokumentierten `CKSyncEngine`-Ablauf, ist aber gegen echtes CloudKit nie
gelaufen — das braucht ein bezahltes Entwicklerkonto, einen bereitgestellten
Container und Entitlements. Deshalb liegt alles, was falsch sein *kann*, im
`SyncCoordinator` und ist über `InMemorySyncBackend` mit zwei simulierten
Geräten getestet. `LocalOnlySyncBackend` ist der ausdrückliche Rückfall: ohne ihn
wäre die App in der Entwicklung nicht startbar.

**Widgets:** der Datenpfad steht und ist getestet (`SharedSnapshot` — klein und
flach, weil ein Widget keine 43-MB-Katalogdatei öffnen darf). Offen ist die
Extension-Target-Plumbing im Xcode-Projekt; sie braucht eine
App-Group-Entitlement und damit Provisioning. Nebenbei gelernt: auf macOS liefert
`containerURL(forSecurityApplicationGroupIdentifier:)` auch für eine erfundene
Gruppe eine anlegbare URL — `isShared` ist dort kein verlässliches Signal, auf
iOS schon.

## Rätsel teilen und weitergeben

Ein Rätsel ist vollständig durch seinen Seed beschrieben, also ist „schick mir
dieses Rätsel" ein Link:

```
kreuzwort://p/arrow/schwer/4711
https://kreuzwort.app/p/arrow/schwer/4711
```

Der Parser ist nachsichtig bei Kleinigkeiten (abschließender Schrägstrich,
Groß- und Kleinschreibung) und **unnachsichtig bei allem anderen**: eine
unbekannte Variante wird abgelehnt und nicht auf `classic` geraten, sonst öffnet
ein Tippfehler das falsche Rätsel. Versionsangaben sind optional — ein Link soll
nicht brechen, weil der Katalog gewachsen ist.

Handoff nutzt dieselbe Nutzlast über `NSUserActivity`: der schnelle Pfad, während
CloudKit der verlässliche ist. Das Rätsel auf dem iPad weiterzuspielen soll nicht
auf eine Synchronisierung warten.

## Game Center

**Game Center ist Anzeige, nicht Quelle der Wahrheit.** GameKit gibt
Achievement-Fortschritt nur begrenzt zurück und ist gar nicht verfügbar, solange
der Spieler nicht angemeldet ist. Die Wahrheit ist `PlayerProfile` im Kern; Game
Center wird daraus beschrieben.

Jedes Feld des Profils ist so gewählt, dass Zusammenführen **nicht schiefgehen
kann**: wachsende Zähler je Gerät, Mengenvereinigung, logisches Oder. Kein
Zeitstempel, kein Tiebreak. Wo das konkret wird: die **Serie** ist eine Menge von
Tagen, kein Zähler — zwei Geräte, die denselben Tag lösen, würden einen Zähler
beide erhöhen.

Achievement-Fortschritt ist **berechnet, nicht gespeichert**: das Profil hält die
Rohzahlen, `AchievementEvaluator` leitet die 22 Auszeichnungen daraus ab. Zwei
Wahrheiten zu pflegen wäre genau der Fehler, den die Trennung vermeiden soll.

Die `SubmissionOutbox` ist für den **Normalfall** gebaut, nicht den
Ausnahmefall: die App ist ohne Anmeldung voll spielbar, also entstehen Punkte
regelmäßig bevor Game Center erreichbar ist. Sie überlebt App-Neustarts, fasst
wiederholte Meldungen zusammen, und eine abgelehnte Meldung nimmt die anderen
nicht mit.

`FakeGameCenterService` ist keine Testbequemlichkeit, sondern Voraussetzung:
ohne sie wäre die halbe Anbindung nur auf einem echten Gerät mit eingerichteten
Leaderboards prüfbar — also praktisch nie.

## Sprachen

Die **Oberfläche** gibt es in Deutsch, Englisch und Italienisch
(`Packages/KreuzwortUI/Sources/Resources/*.lproj`). Ein Test prüft, dass alle
drei dieselben Schlüssel haben, keine leeren Werte enthalten und **dieselben
Format-Platzhalter** verwenden — eine Übersetzung mit abweichender
Platzhalterzahl stürzt zur Laufzeit ab, und zwar nur in dieser einen Sprache.

Die **Rätsel** bleiben deutsch: der Fragenkatalog stammt aus deutschem
Wiktionary, Wikidata und deutschen Korpora. Eine italienische oder englische
Fassung der Rätsel wäre ein eigener Katalog — dieselbe Arbeit wie die
Katalogpipeline noch einmal, pro Sprache. Für Südtirol ist „italienische
Oberfläche, deutsche Rätsel" die naheliegende Kombination, und die App hat eine
eigene Sprachwahl, weil Systemsprache und gewünschte Oberflächensprache dort
regelmäßig auseinanderfallen.

Anzeigetexte liegen deshalb **nicht** im Kern: `PuzzleKit` importiert kein
Foundation und kann nicht lokalisieren. `ScoreBreakdown.lines` liefert Arten
(`.base`, `.streak`, `.total`), nicht Texte; die Sprache kommt aus
`KreuzwortUI`. Die alten Roh-Labels heißen `debugLabel` und sind nur für CLI und
Debugging.

## Bauen

```bash
swift build && swift test                       # Bibliotheken und CLIs
python3 scripts/make-xcodeproj.py               # Apps/Kreuzwort.xcodeproj erzeugen
xcodebuild -project Apps/Kreuzwort.xcodeproj -scheme Kreuzwort \
  -destination 'platform=macOS' build
```

Das Xcode-Projekt ist **handgeschrieben** und wird von
`scripts/make-xcodeproj.py` erzeugt — kein XcodeGen, kein Tuist, keine
Abhängigkeit. Die UUIDs sind aus stabilen Namen abgeleitet, ein zweiter Lauf
ergibt dieselbe Datei. Ein App-Target für iOS, iPadOS und macOS, das die
Bibliotheken über `XCLocalSwiftPackageReference` aus diesem Verzeichnis zieht:
`swift build` und Xcode sehen dieselben Quellen. Die App-Quellen unter
`Apps/Kreuzwort/` tragen beide Build-Systeme.

Der Katalog liegt als **Ordnerverweis** in der Resources-Phase, nicht als
Einzeldateiverweis — er ist ein generiertes 43-MB-Artefakt und nicht im Git; ein
Dateiverweis würde den Build brechen, sobald er fehlt.

Der Katalog ist ein generiertes Artefakt und liegt nicht im Repo. Neu erzeugen:

```bash
python3 scripts/harvest_wiktionary.py     # 267-MB-Dump, ~4 min
python3 scripts/harvest_leipzig.py --archives raw/leipzig/*.tar.gz
python3 scripts/harvest_wikipedia.py      # gedrosselt, gecheckpointet, wiederaufnehmbar
swift run -c release catalogbuild build
swift run -c release puzzlegen verify                   # geprüfte Seeds, Pflicht
```

Der letzte Schritt ist **Pflicht, nicht optional**: `Resources/seeds.txt` gilt nur
für die Katalog- und Generatorversion, gegen die sie geprüft wurde. Nach einem
Katalog-Neubau ist die alte Liste ungültig, die App fällt dann auf blindes
Seed-Wählen zurück, und `ShippedSeedsTests` macht es beim Testen sichtbar statt
im Feld.

Die Downloads stehen in den Skriptköpfen. Wikimedia drosselt anonyme Clients
hart; der Wikipedia-Harvester hat deshalb Backoff und einen Cache und kann
jederzeit erneut gestartet werden.

## Rätsel erzeugen

```bash
swift run -c release puzzlegen templates --count 24     # Schwarzfeldmuster suchen
swift run -c release puzzlegen gen --difficulty schwer --seed 1
swift run -c release puzzlegen diag --difficulty mittel # Kandidatenpools je Slot
swift run -c release puzzlegen sweep --seeds 100        # Erfolgsquote messen
swift run -c release puzzlegen verify --target 24       # erzeugbare Seeds suchen
```

`verify` schreibt nach **jedem** Erfolg. Ein vollständiger Durchlauf dauert
Stunden, weil ein Fehlschlag bei classic/experte rund 8 Minuten kostet; ein
Abbruch darf davon nichts verlieren, und ein erneuter Aufruf setzt auf der
vorhandenen Datei auf. Flags: `--target` (Seeds je Kombination), `--max-seconds`
(Deckel je Kombination), `--max-seed`, `--variant`, `--difficulty`.

## Oberfläche ansehen

```bash
swift run -c release uishot --variant arrow --difficulty mittel
swift run -c release KreuzwortMac                       # spielbar auf dem Mac
```

`uishot` rendert die Ansichten **headless** in PNGs unter `build/shots/` — drei
Flächen (Schreibtisch, Handheld, Wohnzimmer) × hell/dunkel, plus Fragenliste und
Abschlussbildschirm. Ein Build beweist, dass etwas kompiliert, nicht dass es
aussieht; `ImageRenderer` schließt die Lücke ohne Simulator und deterministisch,
und dieselbe Mechanik trägt später die Snapshot-Tests.

Drei SwiftUI-Bausteine rendern dort **nicht** und sind deshalb bewusst vermieden
oder gekapselt: `List` zeigt einen Platzhalter, `ScrollView` und `LazyVStack`
bleiben leer (kein View-Host bzw. kein Sichtfenster), und `Menu` zeigt ebenfalls
einen Platzhalter. Die Fragenliste ist darum in `ClueListContent` (testbar) und
`ClueListView` (scrollbar) geteilt, und die Hilfen sind Symbolknöpfe statt eines
Menüs.

## Stand

| Meilenstein | Stand |
|---|---|
| M0 Repo, SPM, sechs Plattformen, CI-Skript | ✅ |
| M1 `PuzzleKit`-Kern, Layout-Seam, Templatesuche, Seam-Scans | ✅ |
| M2 Katalogpipeline, drei Quellen, Abdeckungsreport | ✅ |
| M3 Füll-Engine, `classic`-Generator (alle vier Stufen), CLI | ✅ |
| M4 `ArrowLayout` (Schwedenrätsel), alle vier Stufen | ✅ |
| M5 Spielansicht, Scoring, Eingabe, Persistenz, Startbildschirm | ✅ |
| M6 Xcode-Projekt für iOS/iPadOS/macOS, Lokalisierung de/en/it | ✅ |
| M7 Game Center: Profil, Achievements, Leaderboards, Outbox | ✅ |
| M8 Sync-Schicht, Deep Links, Handoff, Widget-Datenpfad | ✅ mit Einschränkung (siehe unten) |
| M9 tvOS-Oberfläche | fertig |
| M10 Barrierefreiheit, Lokalisierung | offen |

## Bekannte Lücken

Ehrlich statt hübsch. Alles hier ist gemessen, nicht vermutet.

**Eine schwere Stufe soll seltene Wörter zulassen, nicht aus ihnen bestehen.**
Die Kandidaten-Vorauswahl zielte auf `minZipf + 0,8` — bei classic/experte
(minZipf 2,0) also auf zipf ≈ 2,8, und das sind rund 30.000 Wörter aus dem langen
Wiktionary-Schwanz. Die verzahnen schlecht: ungewöhnliche Buchstabenmuster,
wenige passende Kreuzungen. Die Pools waren mit 1.200 bis 11.500 Kandidaten je
Slot die größten im ganzen Projekt, und trotzdem füllte nichts. Mit einem Boden
bei zipf 3,6 (`FillEngine.preferredZipfFloor`) füllt dasselbe Gitter in 20
Sekunden. Wer eine Stufe „schwerer" machen will, senkt `minZipf` — nicht das
bevorzugte Niveau.

**Der Katalog ist der Engpass, nicht die Suche.** 128.584 Antworten klingt viel,
aber die Schwierigkeitsbänder schneiden schmale Scheiben heraus: bei zipf ≥ 4,5
(Stufe „Leicht") bleiben 1.258 Antworten der Länge 3–10. Voll verzahnte Gitter
brauchen Wortlisten in der Größenordnung 50.000 pro Band — deshalb sind die
Gitter hier bewusst nicht voll verzahnt (siehe `DifficultyProfile`). Der
nächstgrößte Hebel ist mehr Vokabular, nicht mehr Suchheuristik.

**Fragen-Trennschärfe: geschärft, und sie hat einen Preis.** „EIS — Wasser" war
formal eindeutig (kein anderer Dreibuchstaber trug genau diese Kurzform), als
Frage aber wertlos. Drei Gatter greifen jetzt zusätzlich: Schwelle 2 statt 3 bei
gleicher Länge, ein katalogweiter Deckel von 4 Vorkommen, und eine Wortart-Prüfung
(ein Adjektiv bekommt keine Substantiv-Kurzfrage mehr). Danach fielen beim
Rendern vier weitere Fehler auf, die vorher im Rauschen lagen und ebenfalls
behoben sind:

| Fehler im Rätsel | Ursache | Regel |
|---|---|---|
| `ASYL — Rechtssprache; kein Plural: Schutz` | Wiktionary-Kontextangabe im Bedeutungstext | Präfix vor dem Doppelpunkt entfernen, wenn es kein Präpositionalwort enthält |
| `DOMAIN — Ein Namensbereich, der dazu dient` | Langform an einer Klausengrenze gekappt | angefangenen Nebensatz abschneiden, Rest zu kurz → verwerfen |
| `ERDE — Belebter und dritter` | aggressiver Schnitt vor dem Substantiv | mehrwortige Kurzform ohne Substantiv verwerfen |
| `TAL — Tiefergelegenes Gelände zwischen` | 20 Präpositionen fehlten in der Dangler-Liste | nachgetragen; kostet keinen Pool, weil nur das letzte Wort entfällt |

Der Preis: 25 % weniger Kurzfragen (131.131 → 98.039). Langfragen **gewannen**
dabei (160.396 → 164.467 Clues), weil der Kontext-Strip und der Nebensatz-Schnitt
Texte retten, die vorher als zu lang verworfen wurden.

Das einwortige Adjektivfragment liess sich am Ende doch lösen, und der Umweg
lohnt als Notiz. Der erste Versuch fragte nach der **Endung** und riss drei
bestehende Tests mit: `-er` fängt „Lehrer" und „Zucker", `-e` fängt „Sonne" und
„Rose". Die Bedingung, die den Unterschied macht, ist nicht die Endung allein,
sondern **ob geschnitten wurde**: „Flaches" entsteht aus „Flaches Gebäck aus
Mürbeteig", „Zucker" steht so in der Quelle. Mit dieser Zusatzbedingung kostet die
Regel 892 Kurzfragen (0,75 %) statt der halben Ernte. Bezahlbar wurde sie erst
durch den grösseren Pool — vorher hätte dieselbe Regel Kombinationen gekippt.

Die Endung `-e` bleibt bewusst ausgenommen, weil dort die Substantive überwiegen
(„Sonne", „Rose", „Sprache"). Einwortige Fragmente auf `-e` überleben deshalb
weiter: „Feine" aus „Feine Zucker- und Backwaren aus Weizenmehl" ist der Rest,
der bleibt.

**Der Kurzfragen-Pool: vergeben statt verwerfen.** Nach der Schärfung fehlten
66.428 Kurzformen — davon fielen 61.990 (93 %) im Ambiguitätsgatter und nur ~4.400
schon bei der Ableitung. Das Gatter war die Ursache, nicht die Textqualität. Zwei
Änderungen:

1. **Kandidatenlisten statt einer Kurzform.** Rang 0 bleibt die erste Klausel;
   danach kommen die späteren Klauseln, weil das im Wiktionary oft Synonyme sind
   und damit spezifischer als eine gekappte erste Klausel: „Tiefergelegenes
   Gelände zwischen Erhebungen, **Geländeeinschnitt**". Angehängte Relativsätze
   („die etwas Gutes bewirkt") und Fortsetzungen („zum Beispiel auch einer
   Unterlage") sind gefiltert — sie setzen die Definition fort statt sie zu
   ersetzen.
2. **Anspruch statt Verwerfen.** Vorher verloren bei einer Kollision *beide*
   Antworten die Kurzform. Eine Kurzfrage, die genau **einer** Antwort je Länge
   gehört, ist aber per Konstruktion eindeutig — es gab keinen Grund, sie auch
   der ersten wegzunehmen. Vergeben wird in Runden über die Kandidatenränge, damit
   eine Frage mit vielen Ausweichmöglichkeiten nicht die Ansprüche einer Frage mit
   nur einer verdrängt. Reihenfolge nach Antwort sortiert: willkürlich, aber
   deterministisch — Pflicht, weil der Katalog in den Rätsel-Seed eingeht.

Ergebnis: **98.039 → 117.971 Kurzfragen (+20 %)**, Antworten ohne jede Kurzform
**46.882 → 31.529 (−33 %)**, arrow/leicht-Pool je Länge rund +30 %.

Der grössere Pool legte vier weitere Textfehler frei, die vorher zu selten waren,
um aufzufallen — alle vier behoben und mit Test festgenagelt:

| Fehler im Rätsel | Ursache |
|---|---|
| `AALBUCH — Im Osten gelegener Teil v.` | abgekürzte Präpositionen („v.", „d.", „f.") fehlten in der Dangler-Liste |
| `ACHÄER — Angeh.` | eine Kurzform, die nur aus Abkürzungen besteht, sagt nichts |
| `ABBAUARBEIT — Meist im Plural: die Tätigkeit` | Kontext-Strip verweigerte, weil „im" wie eine Definition aussah — jetzt erkennt er das geschlossene Marker-Vokabular statt der Abwesenheit von Präpositionen |
| `ABSCHIED — Auch bildlich; Plural selten}}` | durchgesickerte Wikitext-Klammern; solcher Text ist kaputt, nicht kürzbar, und wird verworfen |
| `ABADDON — Christliche und jüdische Religion:` | Fachgebiets-Etikett ohne Definition dahinter |
| `Welche` als ganze Frage | reines Funktionswort — die Listen für „darf nicht enden" und „darf nicht anfangen" sagen zusammen auch „darf nicht daraus bestehen" |
| `Flaches`, `Beheizbarer`, `Obergäriges` | einwortiges Adjektivfragment |

Beim letzten Punkt lohnt die Notiz, weil ich zuerst falsch abgebogen bin: ich habe
zweimal Marker-Vokabular nachgetragen („Plural", „Botanik", „zumeist") und war
immer noch bei 1.603 Kurzformen mit Doppelpunkt. Erst die allgemeine Regel griff:
**eine Kurzfrage enthält keinen Doppelpunkt** — steht rechts davon etwas
Brauchbares, gewinnt das, sonst fällt der Kandidat. Für Langformen gilt die Regel
bewusst nicht: dort trägt der Rest des Satzes genug, um ein Etikett zu verkraften.

**Die Schärfung kostete Füllbarkeit — und deckte dieselbe Doppelschranke zum
dritten und vierten Mal auf.** Mit 26 % weniger Kurzfragen scheiterte
classic/schwer auf 5 von 6 Seeds und arrow/mittel auf Seed 1. Beide Male band
nicht `minZipf`, sondern der Tier-Deckel: Tier 5 enthält 129.075 der 164.467
Clues, classic/schwer sah mit `clueTiers: 1...4` also ein Fünftel des Katalogs —
bei Länge 3, dem knappsten Fach, 370 statt 615 Wörtern. Merkregel, jetzt viermal
bestätigt: **`minZipf` regelt das Vokabular, `clueTiers` die Fragenhärte, und sie
dürfen sich nicht überdecken.** Wer eine Kombination anfasst, prüft zuerst mit
SQL, welcher der beiden Werte den Pool wirklich bindet — die Fehlermeldung sagt
es nicht.

**Zuverlässigkeit je Seed: 20 von 24 gemessen.** 8 Kombinationen × 3 Seeds nach
der Fragen-Schärfung. Jede Kombination gelingt auf der Mehrheit ihrer Seeds,
keine ist systematisch kaputt — aber vier Tripel scheitern: arrow/experte s1,
classic/experte s2, arrow/schwer s2, arrow/leicht s3. Für Tagesrätsel ist der
Seed das Datum, das wären also grob jeder sechste Tag ohne Rätsel. Das ist ein
offener Produktfehler, kein gelöster.

Zwei Gegenmaßnahmen sind gemessen und verworfen:

* **Sonde lockern** half nur halb. Der Boden von 45 % auf 30 % rettete
  arrow/mittel, aber classic/experte s2 starb weiter an der Sonde — alle zehn
  Versuche, nach 30.328 von 2.500.000 Knoten. Der **letzte** Versuch läuft jetzt
  ohne Sonde (einmal ehrlich bis ans Budget); er kostet nichts, weil er nur
  erreicht wird, wenn alles andere gescheitert ist. arrow/leicht s3 scheitert
  auch damit, nach vollen 300.000 Knoten in 28 Sekunden.
* **Länge 3 für arrow/leicht zulassen** wurde verworfen, weil gemessen: 59
  Dreibuchstaber unter dem Doppelzellen-Budget. Ein Dreibuchstaber-Slot ist der
  am stärksten gekreuzte im Gitter; ein 59-Wort-Fach bremst mehr, als die extra
  Länge einbringt. Die Grenze 4…7 im Profil ist damit bestätigt, nicht geraten.

Der Engpass ist derselbe wie überall in diesem Abschnitt: der Kurzfragen-Pool.
arrow/leicht wählt aus 151 bis 217 Wörtern je Länge. Wer die Zuverlässigkeit auf
100 % bringen will, braucht mehr Kurzfragen — nicht mehr Suchheuristik.

**Fragen in Schwedenrätsel-Zellen: Wortbrüche behoben, Kürzung bleibt.**
Im gerenderten Rätsel stand „Möbelstü ck", „Flüssigkei t", „Sprechweis e" — SwiftUI
brach lange deutsche Wörter ohne Trennstrich. Zwei getrennte Ursachen:

*Erstens* `minimumScaleFactor(0.5)`: SwiftUI zwang jede Frage in die Zelle, indem
es sie auf die halbe Größe schrumpfte. Der Breiten-Etat aus dem Katalog war damit
wirkungslos und die Schrift unlesbar. Jetzt 0,8.

*Zweitens* die fehlende Trennung. Der Etat einer Doppelzelle ist 9.500
Tausendstel-Em auf zwei Zeilen — 4,75 Em je Zeile, bei deutschem Text etwa neun
Zeichen. „Möbelstück" hat zehn. Ein hartes Kriterium „längstes Wort passt in eine
Zeile" hätte rund 90 % des Doppelzellen-Pools verworfen: die Zelle ist zu schmal
für die Sprache, nicht der Katalog zu schlecht. Gelöst wird es deshalb im
Renderer, mit weichen Trennzeichen aus den Sprachdaten des Systems
(`CFStringGetHyphenationLocationBeforeIndex`, siehe `Hyphenation.swift`). Aus
„Möbelstü ck" wird „Möbel-stück", aus „Bundeskanzleramt" „Bundes-kanzleramt".

**Was bleibt: zu lange Fragen werden in der Zelle gekürzt** („Randbe-reich
zwische…"). Zwei Zeilen à 4,75 Em fassen nicht zuverlässig 9,5 Em Text, weil beim
Umbrechen Platz verlorengeht. Zwei Auswege sind gemessen und beide bezahlt:

* **Etat kürzen** kostet unverhältnismäßig viel: −20 % Breite bedeutet −30 % Pool
  (Länge 6: 533 → 381 Antworten für arrow/mittel). Dieselbe Größenordnung hatte
  vorher zwei Kombinationen unfüllbar gemacht.
* **Kleinere Gitter auf dem Telefon** ist durch die Architektur ausgeschlossen:
  das Tagesrätsel ist weltweit dasselbe, die Gittergröße darf also nicht vom
  Gerät abhängen.

Deshalb bleibt die Kürzung, und sie ist vertretbar: die Frageleiste unter dem
Gitter zeigt die ausgewählte Frage vollständig. Das ist bei Schwedenrätseln auf
kleinen Schirmen übliche Praxis.

Die klassische Variante ist von allem nicht betroffen — dort stehen die Fragen in
einer Liste neben dem Gitter und dürfen umbrechen.

**Die Fernbedienung ist auf dieser Maschine nicht prüfbar.** Die tvOS-Oberfläche
ist gerendert und auf der Apple TV im Simulator gesehen — die **Bedienung** mit
der Fernbedienung nicht. Der Simulator nimmt Tastendrücke nur über die
Simulator-App an, und `osascript` hat hier keine Berechtigung dafür
(„osascript ist nicht berechtigt, Tastatureingaben zu senden"). Verifiziert ist
damit die Darstellung, nicht die Fokus-Navigation.

Der Eingabeweg selbst ist geteilt: die Buchstabenleiste ruft dieselbe Umwandlung
wie die Tastatur (`handleCharacter` → `.enter`), und die ist von Tests gedeckt.
Ungeprüft bleibt die SwiftUI-Verdrahtung — ob der Fokus im Gitter wirklich zur
Nachbarzelle wandert und der Cursor mitzieht. Das braucht einen Durchgang von
Hand mit der Fernbedienung.

Vier Fehler hat erst das echte Gerät gezeigt, alle behoben: `xcodebuild` fand
kein tvOS-Ziel, weil `TARGETED_DEVICE_FAMILY` die 3 fehlte (`SUPPORTED_PLATFORMS`
allein genügt nicht); die Buchstabenleiste lief mit zwei Reihen à 15 aus dem Bild
und begann bei „C"; die Sprachnamen im Startbildschirm waren abgeschnitten, weil
dort `maxWidth: 560` auf einem 1920 Punkte breiten Schirm stand; und die
fokussierte Tageskachel schob sich über die Überschrift, weil die Fokus-Engine sie
anhebt und 8 Punkte Abstand dafür zu wenig sind.

**Arrow-Topologien gelingen nicht bei jedem Seed.** Ein einzelner Anlauf auf
9×11 scheitert oft; der Generator kommt durch, weil er bis `maxAttempts` mal mit
abgeleiteten Seeds neu ansetzt. Die Testsuite prüft genau diese Zusage. Eine
verlässlichere Platzierung braucht eine inkrementelle Bewertung statt einer
Neuberechnung je Zug.

**Die Wertreihenfolge war der Hebel beim Füllen.** Kandidaten praktisch zufällig
zu probieren brachte die Suche bei Schwedenrätseln auf 60 % der Slots und dort
zum Stehen — 500.000 Knoten ohne Ergebnis. Mit **Least-Constraining-Value**
(nimm den Kandidaten, der den kreuzenden Slots am meisten Auswahl lässt) füllt
dasselbe Rätsel in 7.500 Knoten. Wer hier weiter optimieren will, sollte bei der
Wertreihenfolge anfangen, nicht bei den Budgets.

**Die Generierung ist noch zu langsam für „on device".** Der Prompt setzt p95
unter 1,5 s an. Gemessen auf einem M-Mac im Release-Build, nach der
Fortschritts-Sondierung:

| | Leicht | Mittel | Schwer | Experte |
|---|---|---|---|---|
| classic | 0,0 s | 2,2 s | 24 s | 6 s |
| arrow | 8 s | 0,4 s | 41 s | 20 s |

Für den im Prompt vorgesehenen Hintergrund-Vorrat (drei Rätsel je Variante und
Stufe) reicht das; als Sofort-Generierung auf Knopfdruck nicht. Der nächste
Hebel ist erneut **nicht** die Innenschleife (siehe unten), sondern die
Reihenfolge, in der Layouts probiert werden: die Templatesuche könnte Layouts
nach geschätzter Füllbarkeit vorsortieren, statt sie zufällig zu ziehen.

**Gemessen statt geraten — drei verworfene Optimierungen.** Der Reihe nach, weil
die Fehlschläge nützlicher sind als das Ergebnis:

1. *Allokationen vermeiden* — Kandidatenzählung ohne Bitset-Aufbau, Wortpuffer
   statt Kopie, `inout`-Durchreichung. Sauber gemessen bei identischer
   Knotenzahl: **20,4 s vorher, 30,3 s nachher.** `formIntersection` ist
   inlinebar und vektorisiert, ein Wortpuffer über drei `inout`-Ebenen nicht.
2. *Begrenzte Auswahl statt vollständiger Sortierung* in `order()`. Ein Slot hat
   bis zu 11.524 Kandidaten, von denen 80 gebraucht werden — die Sortierung
   wirkte wie der offensichtliche Verschwender. Gemessen: **98 s.**
3. *Gestaffeltes Knotenbudget je Versuch.* Denkfehler: Versuch und Layout sind
   gekoppelt, ein kleines Budget bestraft also nicht das hoffnungslose Layout,
   sondern das früh gezogene. Drei von acht Kombinationen scheiterten ganz.
4. *Stillstandsdetektor* („seit N Knoten kein neuer Bestwert"). Beim Füllen der
   letzten Slots gibt es lange Plateaus ohne neuen Bestwert — genau die wurden
   abgewürgt. classic/experte und arrow/leicht fielen aus.

Was geholfen hat, kam aus dem Blick auf die richtige Zahl: bei classic/schwer
stand im Report „acht Versuche, der erfolgreiche brauchte 1.184 Knoten" — bei 26
Sekunden Laufzeit. Über 95 % der Zeit floss in Layouts, die nie eine Chance
hatten. Die **Fortschritts-Sondierung** bricht ein Layout ab, das nach 30.000
Knoten nie 45 % der Slots belegt hat. Wirkung: classic/experte 20 s → 6 s,
arrow/experte 93 s → 20 s. Bei arrow/experte sank die Knotenzahl von 471.208 auf
83.813 — die Sondierung landet schneller auf einem gutartigen Layout.

Die Lehre für den nächsten Anlauf: erst die Verteilung der Kosten messen, dann
optimieren. Vier von fünf Versuchen hier waren Verschlechterungen, und alle vier
klangen vorher plausibel.

**Templatevielfalt bei großen Gittern.** Die Suche findet für 15×15 nur eine
Handvoll Muster (für 7×7 und 9×9 dutzende). Aufeinanderfolgende Experte-Rätsel
sehen sich deshalb ähnlich. Die Suche ist ein einmaliger Offline-Schritt — hier
hilft schlicht ein längerer Lauf mit mehr Seeds.

**`zipf` ist gut, aber nicht perfekt.** 71 Mio. Tokens aus vier Leipzig-Korpora
deckt 69 % der Katalogeinträge ab; der Rest fällt auf einen konservativen
Aufrufzahlen-Schätzer zurück, der bewusst unter dem Band der Stufe „Leicht"
bleibt. Mehr Korpora heben die Abdeckung.

**Eine Restklasse hängender Kurzclues.** „Roh oder gekocht essbare" — beim
Kürzen bleibt ein Adjektiv am Ende stehen. Präpositionalphrasen und abgekürzte
Adjektive werden erkannt und abgeschnitten; für den Rest fehlt
Wortart-Information.

## Lizenz

Code: noch nicht festgelegt. Katalogdaten: siehe `ATTRIBUTION.md` — die
Wiktionary-Definitionen stehen unter CC BY-SA 4.0, was Namensnennung und
Share-Alike verlangt.
