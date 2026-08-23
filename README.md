# Kreuzwort

Native Rätsel-App für alle Apple-Plattformen mit **zwei Varianten** — klassisches
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
                  — kein Foundation, kein Apple-Framework, baut für alle Plattformen
    Layout/       LayoutProvider (der Varianten-Seam) + ClassicLayout + Templatesuche
    Fill/         PatternIndex (Bitsets) + varianten-agnostische CSP-Engine
  ClueCatalog/    SQLite, Normalisierung, QA, Assembler, Häufigkeiten
  GameServices/   GameKit-Facade                       (M7)
  SyncKit/        CKSyncEngine, Merge-Logik            (M8)
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

## Bauen

```bash
swift build && swift test
```

Der Katalog ist ein generiertes Artefakt und liegt nicht im Repo. Neu erzeugen:

```bash
python3 scripts/harvest_wiktionary.py     # 267-MB-Dump, ~4 min
python3 scripts/harvest_leipzig.py --archives raw/leipzig/*.tar.gz
python3 scripts/harvest_wikipedia.py      # gedrosselt, gecheckpointet, wiederaufnehmbar
swift run -c release catalogbuild build
```

Die Downloads stehen in den Skriptköpfen. Wikimedia drosselt anonyme Clients
hart; der Wikipedia-Harvester hat deshalb Backoff und einen Cache und kann
jederzeit erneut gestartet werden.

## Rätsel erzeugen

```bash
swift run -c release puzzlegen templates --count 24     # Schwarzfeldmuster suchen
swift run -c release puzzlegen gen --difficulty schwer --seed 1
swift run -c release puzzlegen diag --difficulty mittel # Kandidatenpools je Slot
```

## Stand

| Meilenstein | Stand |
|---|---|
| M0 Repo, SPM, sechs Plattformen, CI-Skript | ✅ |
| M1 `PuzzleKit`-Kern, Layout-Seam, Templatesuche, Seam-Scans | ✅ |
| M2 Katalogpipeline, drei Quellen, Abdeckungsreport | ✅ |
| M3 Füll-Engine, `classic`-Generator, CLI | ✅ |
| M4 `ArrowLayout` (Schwedenrätsel) | teilweise — Layout ja, Füllen nein |
| M5–M6 App, beide Varianten spielbar | offen |
| M7 Game Center · M8 CloudKit + Handoff + Widgets | offen |
| M9 tvOS · M10 watchOS · M11 Barrierefreiheit, Lokalisierung | offen |

## Bekannte Lücken

Ehrlich statt hübsch. Alles hier ist gemessen, nicht vermutet.

**Der Katalog ist der Engpass, nicht die Suche.** 126.041 Antworten klingt viel,
aber die Schwierigkeitsbänder schneiden schmale Scheiben heraus: bei zipf ≥ 4,5
(Stufe „Leicht") bleiben 1.251 Antworten der Länge 3–10. Voll verzahnte Gitter
brauchen Wortlisten in der Größenordnung 50.000 pro Band — deshalb sind die
Gitter hier bewusst nicht voll verzahnt (siehe `DifficultyProfile`). Der
nächstgrößte Hebel ist mehr Vokabular, nicht mehr Suchheuristik.

**`arrow`: Layout steht, Füllen noch nicht.** Für Mittel, Schwer und Experte
liefert `ArrowLayout` gültige Topologien (Test-Suite `ArrowLayout`). Das
anschließende Füllen scheitert bisher am Breitenbudget der Kurzclues: es ist
korrekt als Füll-Constraint verdrahtet, verkleinert den Kandidatenpool aber
zusätzlich zum Schwierigkeitsband.

**`arrow/leicht`: Slot-Graph zerfällt.** Die Platzierung bewertet den
Zusammenhang des Slot-Graphen nicht — nur den der Buchstabenzellen. Ihn in die
Verstoßsumme aufzunehmen kostet je Bewertung eine `Topology`-Konstruktion und
trieb die Platzierung von Sekunden auf Minuten. Der richtige Weg ist eine
inkrementelle Zusammenhangsprüfung direkt auf den Läufen. Als `withKnownIssue`
im Test geführt, damit die Lücke sichtbar bleibt.

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
