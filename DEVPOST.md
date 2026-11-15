# Devpost submission copy

Draft text for the Arbiter Hacks V1 submission form (Theme track: waste reduction,
sorting, recycling). Edit the voice to your own before submitting.

---

## Tagline

One product is not one piece of waste — and the right bin depends on where you're standing.

---

## Inspiration

I kept noticing that people who genuinely want to recycle still get it wrong, and that
the apps meant to help all make the same two assumptions:

1. That a product is **one** piece of waste. It isn't — a yogurt pot is a polystyrene
   pot, an aluminium lid and a cardboard sleeve.
2. That the answer is **universal**. It isn't — it's municipal, and it contradicts itself
   across borders.

The moment that convinced me this was worth building: a PET bottle in Kraków should be
**squashed flat** and put in the yellow bin. The same bottle in Berlin must be **left
uncrushed** and returned to a shop, because the deposit machine has to read its shape and
barcode. Two cities, one object, directly contradictory instructions. An app that returns
a single global answer is guaranteed to be wrong in one of them.

## What it does

BinMate scans a product barcode, breaks the packaging into its actual components, and
tells you where each individual piece goes **in your city** — with the physical
instruction and the thing people get wrong.

- **Decomposes the product.** Bottle, cap, label — each resolved separately.
- **Answers locally.** Bundled rulesets for Kraków, Berlin, San Francisco and Tokyo, each
  compiled from that city's own published guidance.
- **Shows you the money.** Berlin's Pfand and California's CRV are deposit streams, so
  BinMate tells you a six-pack of cans is 1.50 € waiting to be reclaimed, not rubbish.
- **Compares cities instantly.** Tap another city and the whole product re-sorts live.
  It's instant because resolving is a pure function over bundled data.
- **Shows its working.** Tap *Why?* on any part and the app lays out every step: the
  material, the part, which rule matched and whether it had to fall back to a broader
  one, and the source it came from. An app that says "yellow bin" and cannot say why is
  asking to be trusted on authority.
- **Checks its own rules for contradictions.** A rule shadowed by a broader one above it
  never fires, and nothing else would notice — the answer would just be wrong, with a
  confident explanation attached.
- **Says how sure it is, and why not more.** Uncertainty is a set of distinct reasons
  rather than a percentage: the material is unknown, there is no rule for it specifically,
  the rule covers any part in a city that narrows other rules by part, the ruleset is two
  years old. Several apply at once, and each carries a remedy — a warning with nothing to
  do about it is noise.
- **Lets the data leave.** All five rulesets export as CSV, Markdown or JSON, each
  carrying its source, its compile date and its caveat. "Cities are data" is only worth
  saying if someone else can take the data.
- **Asks one question instead of showing a form.** When a record is thin, the app usually
  knows what is missing — a bottle with no cap listed, a material it cannot place — so it
  asks, with plausible answers ready. A product that is already well described is left
  alone.
- **Weighs what you handled, and says how much of it it actually knows.** Three things
  get called "recovered" and only two are knowable: mass *recognised* from the data, mass
  *directed* by a real rule, and mass actually recovered by a facility — which BinMate
  cannot know and does not claim. The parser refuses volumes, because `25 cl` is what was
  in the bottle, not what the bottle weighs.
- **Reports on its own data.** One screen collects every check — rulesets that failed to
  load, rules that can never fire, sources overdue for review, materials with thin
  coverage, packaging records that look malformed. With no overall score, because that
  number would have to be invented.
- **Keeps an account of what it actually said.** Each scan records the decision — the
  bin, the matching, the confidence, the rule, the source and its date — so history is
  not silently rewritten when rules change. It can then answer *would today's rules say
  the same?* and flag the scans a correction affected.
- **Notices when packaging changes.** Rescan something and it tells you if the producer
  changed the packaging since last time — and whether that moves a part to a different
  bin.
- **Knows where its own rules are thin.** Each city's rule book reports how many common
  materials have a rule of their own versus falling back to a broader one, and ranks the
  gaps by how much they cost.
- **Lets you correct it.** Packaging data is crowd-sourced and often thin or wrong, so
  when a record looks incomplete BinMate says so and lets you add the parts you can
  actually see. The correction updates the verdict and the history entry.
- **Handles things with no barcode.** Photograph it and an on-device classifier proposes
  the parts — labelled *likely*, *possible* or *long shot*, and flagged when the material
  was assumed rather than recognised. Nothing is pre-ticked. You confirm; the rules
  engine decides.
- **Finds your city — or admits it can't.** One location fix, matched against the
  bundled rulesets. If you are 1,800 km from the nearest one, it says so instead of
  quietly assigning you Berlin's rules.
- **Closes the loop.** Deposit bottles and drop-off items need a separate trip, so they
  collect into a **Take back** list you can tick off — grouped by destination, totalled
  per currency, using each city's own wording.
- **Works in reverse too.** A browsable rule book answers *"what goes in this bin?"* and
  a search understands synonyms — type `tetra` and you learn that in Kraków a drinks
  carton goes in the *yellow* bin, not with paper. Bins with no rules say so rather than
  looking complete.
- **A home screen widget.** What the bins mean in a city you pick, at a glance — kerbside
  bins only, because a deposit machine is a destination, not something standing in your
  kitchen. Keep one per city if you travel.
- **Answers from Siri.** *"Hey Siri, which bin in BinMate?"* — spoken, instant, without
  opening the app, because the rules are bundled and resolving them is a pure function.
- **Works with no network at all.** Every rule ships in the app.

## How I built it

Native iOS — SwiftUI, SwiftData, VisionKit. Packaging data from the Open Food Facts API.

The interesting engineering isn't classification, it's the **rules layer**. Cities are
plain JSON; adding one is a data change, not a code change:

```json
{
  "materials": ["en:pet-1-polyethylene-terephthalate"],
  "shapes": ["en:bottle"],
  "stream": "pfand",
  "instruction": "Take it back to any shop that sells drinks and get 25 cents.",
  "caution": "Do not crush it. The machine has to read the barcode and the shape."
}
```

Materials use the Open Food Facts taxonomy, which is a **tree**. Resolution walks the
ancestry nearest-first, so a city writes one rule for `en:plastic` and it automatically
covers every polymer beneath it — while a city that treats one polymer differently just
adds the specific rule, which wins.

That ordering is load-bearing. Berlin's `PET + bottle → deposit` rule must beat its
broader `plastic → yellow bin` rule, or the app tells you to bin 25 cents. So it's an
asserted test, not a hope.

**The objection I had to answer.** "Fine, but surely national rules would be close
enough?" So I added a second American city. San Francisco and New York are in the same
country and their bins contradict each other: in San Francisco the **green bin is
compost**, in New York the **green bin is paper**. Someone who moves between them and
keeps their habits is putting food waste into a paper stream. Compostable cups are
composted in one and landfilled in the other. Both facts are asserted in the test suite,
including that the green bin's *kind* genuinely differs.

**The design got its real test from Tokyo.** Japan doesn't sort by material the way
Europe does — it sorts substantially by *burnability*, and treats a PET bottle, its cap
and its label as three separate resource streams that you physically disassemble before
collection. I expected to need special cases. I needed none: Tokyo is one more JSON file,
and the existing shape-narrowing rules expressed the whole thing, including the same
material splitting in both directions (a PET *bottle* is a resource, a PET *tray* is
container packaging, loose PET is burned). That's when I believed the rules layer was the
right abstraction rather than just a tidy one.

I wrote two verification suites that run in seconds without a simulator — one that
exercises the engine against the real city JSON, and one that loads the **built `.app`
bundle** and validates every bundled resource.

## Challenges I ran into

**The bundle layout bug.** Xcode flattens resource folders — `Resources/Rules/*.json`
lands in the bundle *root*, not in a `Rules/` subdirectory. The loader looked only in the
subdirectory, so every ruleset would have silently failed to load and the app would have
had nothing to sort against. The bundle verification suite caught it before it ever ran.

**Crowd-sourced data is messy.** Open Food Facts is remarkable in coverage and
inconsistent in format: `number_of_units` arrives as `2`, `"2"` or `"2 units"`; materials
appear as `PET`, `en:PET`, `Aluminum`. Every field is optional, every number is parsed
leniently, and all identifiers normalise onto a canonical taxonomy entry.

**The database is thinner than the premise needs.** I wrote a suite that hits the live
Open Food Facts API, and it told me something uncomfortable: Coca-Cola comes back as
*one* component, and Nutella comes back as "bottle, plastic" — it's a **glass jar**.
Crowd-sourced data is uneven and sometimes simply wrong, which undercuts the whole
decomposition idea on live scans. Rather than hide that, BinMate flags single-component
records right on the verdict screen and lets you **correct the parts**, updating both the
verdict and the history entry. The person holding the object knows more than the database
does, so the app treats them as the authority.

**A threshold I had to measure instead of guess.** For barcode-less items I used
`VNClassifyImageRequest`, Apple's built-in image classifier — no model to train, no
dataset to licence, runs on device. I filtered it at 8% confidence, which sounds
conservative. Then I actually ran it and watched the *correct* label come back at
**1.7%**. With over a thousand classes the probability mass is spread so thin that any
intuitive threshold silently discards the right answer. Fixed cut-off out; Apple's
calibrated `hasMinimumPrecision(_:forRecall:)` in, with a fallback to the strongest raw
labels. The same measurement killed my confidence percentage in the UI — "2% match"
reads as broken — so it shows *likely / possible / long shot* instead.

**Data that vanished, and a diagnosis that was wrong.** Building the take-back list, my
development history disappeared. Everything compiled, every suite was green, and an empty
history screen looks exactly like a fresh install. Opening the store with `sqlite3`
showed the table rebuilt with zero rows, and I blamed a `UUID` attribute I had just added
to the model — a lightweight migration, I reasoned, cannot invent a distinct value for a
new required attribute.

Then I wrote the test to prove it, and the test refused to fail. Migrating a fixture cut
from the *old* schema into that exact new schema preserves every record. My explanation
was wrong, and I had already written it into a commit message.

So the guard now protects the property that matters rather than the mechanism I guessed
at: a build must be able to read history written by an earlier build, with every field
intact and the store still writable afterwards. The real cause remains unidentified, and
the code says so instead of carrying a confident story that my own test disproves. The
app also used to fall back to an in-memory store silently — that now shows up in
Settings, because a fallback nobody can see is worse than the crash it avoids.

**A constraint that turned into the better design.** I built the widget to follow the
city chosen in the app, which needs an App Group. Then `codesign -d --entitlements`
showed an empty dict on both unsigned and ad-hoc builds: App Group entitlements require a
provisioning profile, so the widget was silently showing whichever city happened to be
first. I could have documented that and moved on. Instead the widget now carries its own
city, configured by long-pressing it — no entitlement needed, works in every build, and
better anyway, because someone who travels can keep one widget per city.

**Two descriptions that weren't behaviour.** Reading back over the project I noticed the
widget's configuration text said "tap to scan something" while the widget had no tap
target, and the Shortcuts action said it opened the app "ready to scan a barcode" while
only launching it. Neither was broken exactly — they just quietly promised more than the
code did, which is the easiest kind of rough edge to ship. Both now open the scanner, by
different routes: the widget through a registered `binmate://scan` URL, because a widget
runs in its own process and can only hand back a URL; the Shortcuts action through a
request left in the app's own defaults, because an app-declared intent runs *inside* the
app and needs no App Group at all.

**The bug my own test watched and shrugged at.** Open Food Facts writes the recycling
code into the material identifier: `en:pp-5-polypropylene`, not `en:pp-polypropylene`.
The hand written tree knew only the uncoded spellings, so all seven standard plastics —
the commonest packaging materials there are — resolved to nothing and fell into residual
waste. A PET bottle in Berlin is worth 25 cents and the app said to bin it.

The live API suite had printed `en:pp-5-polypropylene` in its own output for days. It
treated "this material matched no rule" as a note rather than a failure, because
sometimes that is a legitimate gap in a city's rules. The distinction it was missing is
that an *unrecognised material* is a bug in BinMate, while an *unruled material* is a gap
in a city — so it now fails on the first and still only notes the second. Verified by
deleting one alias and watching it go red.

**Then the fix turned out to be the same mistake again.** I patched it by writing more
identifiers in the same shape — `en:pap-22-paper`, `en:alu-41-aluminium` — guessed by
pattern from the handful I had seen. So I downloaded the published taxonomy and compared,
and the comparison was unkind: none of those spellings exists, 16 of the app's 37
identifiers were invented, 31 alias keys could never match anything, and the app placed
**28 of the taxonomy's 310 material entries — 9%**.

The honest fix was to stop writing the tree. It is now generated from a vendored snapshot
of the published taxonomy, 310 of 310 entries place, and the audit that found all this is
a suite (`verify-taxonomy.sh`) that fails if any hand written identifier points at
something upstream does not contain. It immediately found three more: Tokyo's plastic
packaging rule was keyed to `en:cap`, a shape no scan can produce, so that rule had never
fired for a cap in its life.

The same check showed shapes form a hierarchy upstream — a screw cap is a bottle cap is a
cap — which the app had been treating as flat, so a city's rule about caps missed every
`en:screw-cap` in the data. Walking that hierarchy, nearest-first so exact rules still
win, moved **zero of the 950 regression cases**: proof it was a relabel and not a
behaviour change, which is the only way to make a refactor this size safe to ship.

**Contributed data is not in English.** A sample of one real category came back with 7% of
its packaging identifiers in another language — `es:Plástico`, `fr:PP 5 - Polypropylène`,
`es:Bandeja` — every one of them bound for residual waste. The taxonomy names its entries
in 34 languages, so the synonyms are generated from it too: 1,841 material and 1,243 shape
names, with anything ambiguous dropped rather than guessed. A Spanish plastic bottle now
lands in the same bin as an English one, asserted in three cities.

**Knowing when *not* to fall back.** Bundled sample products make the app usable offline,
but serving one when the database genuinely says "this barcode doesn't exist" would be a
lie. So fallback only triggers on failures to *reach* the service — a real "not found"
stays a real "not found", and every result is labelled with where it came from.

**Bin colours aren't designed for legibility.** They're chosen by municipalities, and
several (yellow, Weißglas grey) are unreadable behind white text. Icon contrast is picked
from each stream's relative luminance so every bin stays legible in both appearances.

**Writing for the ear, not the eye.** The Siri answers looked fine in code and sounded
wrong out loud. Berlin's came back as *"…that one is worth €0.25 back. Take it back to
any shop and get 25 cents"* — the same fact twice in one breath, which reads as a bug.
And the app was saying a deposit machine was somewhere you put things *in*. Both are now
driven by the data: the refund sentence is suppressed when a city's own instruction
already mentions money, and the preposition switches on the stream kind. The structural
one mattered more: for anything that is really several parts, the spoken answer ends by
admitting it. Siri confidently naming one bin for a yogurt pot would be the exact mistake
this whole app exists to correct.

## What I learned

That the hard part of this problem is not computer vision. It's that *correct* is a
property of a place, not of an object — and that a system which admits what it doesn't
know is more useful than one that always has an answer.

## What's next

- Core ML classifier for items with no barcode (the manual packaging picker is the
  complete flow today, and becomes the correction path)
- App Intents and Siri: *"which bin for a yogurt pot?"*
- Geocoded city selection
- Community ruleset contributions, with the app's own "no specific rule" gaps as the
  backlog

## Built with

`swift` `swiftui` `swiftdata` `visionkit` `ios` `open-food-facts` `core-ml`

---

# Demo video script (2:30)

The rubric weights **Completeness & Polish** at 25%. Show finished flows, never a
half-built screen. Record on a physical device so live scanning is real.

| Time | Shot | Say |
|---|---|---|
| 0:00–0:15 | Hold a yogurt pot. Pull the foil lid off, slide the cardboard sleeve off. Three pieces in your hand. | "This is one product. It's three pieces of waste, and they don't go in the same bin." |
| 0:15–0:35 | Scan the barcode. Verdict screen fills in: three parts, grouped by destination. | "BinMate breaks the packaging apart and sorts each piece by the rules of *your* city." |
| 0:35–1:10 | **The money shot.** Scan a PET bottle in Kraków — "squash it flat", yellow bin. Tap Berlin on the comparison strip. Screen re-sorts instantly: deposit return, +0.25 €, *"do not crush it."* | "Same bottle. Kraków says squash it flat. Berlin says do **not** crush it — and hands you 25 cents. Any app that gives one global answer is wrong in one of these cities." |
| 1:10–1:30 | Tap San Francisco, then Tokyo. On Tokyo, point at the instruction: *"take the cap **and the label** off."* | "Tokyo wants the bottle, the cap and the label in three different places. Japan doesn't even sort by material — it sorts by what burns. Supporting that took one more JSON file and no code." |
| 1:30–1:50 | Point at a match-quality chip reading *"No specific rule — default bin"*. | "And when there's no local rule, it says so instead of guessing. Cities are JSON — adding one is a data change, not a code change." |
| 1:50–2:10 | Turn on Airplane Mode. Scan again — works identically. Then the stats screen with reclaimable deposits. | "Every rule ships in the app, so it works with no signal. No account, no server — your history never leaves the phone." |
| 2:10–2:30 | Terminal: `./Tools/verify-rules.sh` → *All assertions passed.* | "The ordering that makes Berlin's deposit rule beat its general plastic rule is a test, not a hope." |

**Cut, don't show:** anything loading, any unfinished screen, the simulator's
"camera unavailable" state.
