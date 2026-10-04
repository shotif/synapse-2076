# Design directions: from dashboard to world

This started as a brainstorm: how to run the exploration, then ideas for making SYNAPSE-2076 look and play like its setting rather than like a generic sci-fi control panel. Ideas 1 to 6 were mocked up, approved and then built; the rest are still open.

## What shipped

| Idea | Where it lives |
|---|---|
| 1. The world is the interface | `viewports_3d/globe_viewport.gd` (one layer per metric, era palettes), `ui/components/world_overlay.gd` (layer chips, captions, a news ticker under a provenance seal, instruments that misreport past drift 55), `ui/effects/drift_glitch.gd` |
| 2. Fifty years look like fifty years | `ui/theme/era_style.gd` and `era_theme.gd`: Era I a dark native app (the macOS-like option A), Era II holographic glass, Era III a living interface. `ui/components/era_upgrade.gd` plays the system upgrade; meters become cards, rings and cells; `nav_bar.gd`, `era_backdrop.gd` |
| 3. Each faction sees a different world | `ui/lenses/`: a trading terminal, a daily brief, raw perception and the Commons civic network |
| 4. Crisis cards you read at a glance | `ui/components/dilemma_dialog.gd`, `crisis_card.gd`, `crisis_art.gd`, `vitals_strip.gd`: swipe, hold or hover to preview, glyphs with pips |
| 5. One glyph language | `ui/glyphs.gd`, used by every metric, currency, faction and effect |
| 6. Headlines instead of logs | `ui/story/`: the newswire, *The Ledger* front page at the end of each era, and the history-book debrief |

Every screen works on the desktop (1600x900 canvas), on landscape tablets and phones (the world beside a tabbed panel) and on portrait phones (tabs). The mockups that were approved are the reference for colors, type and wording.

## What the design did before

- **The world is told, not shown.** Energy, labor, power and machine minds reach the player as numbers, prose and a cyan-on-black monospace panel. The globe exists, but you could play without looking at it.
- **Every role sees the same screen.** A Frontier Lab CEO, a Governance Chair, an emergent superintelligence and a citizens' movement would not experience 2041 through the same dashboard.
- **Fifty years look like one afternoon.** 2026 and 2076 share fonts, colors and frames, so the eras and paradigm shifts in the model never become something you feel.
- **Crisis cards are walls of text.** The most dramatic moment of each turn is a paragraph plus stat deltas like "Geopol Tension ▲3 · alignment tax 6%".

The simulation underneath is strong. The opportunity is to make the surface carry it.

## How to brainstorm it

1. **Write three design pillars, one sentence each.** Every later idea gets checked against them. Candidates:
   - "You steer a planet, not a spreadsheet."
   - "Fifty years should look like fifty years."
   - "Each faction sees a different world."
   - "Information is a resource, and it degrades."
2. **Build mood boards per role and per era.** Collect 10 to 20 images each. Useful references:

   | Kind | Examples | What to take from it |
   |---|---|---|
   | Games | Plague Inc., Frostpunk, Papers Please, Reigns, Into the Breach, Suzerain, Mini Metro, Universal Paperclips, Twilight Struggle, Citizen Sleeper | World-map pressure, a society under a heat clock, desk diegesis, swipe decisions, telegraphed consequences, political dialogue UI, minimal diagrams, escalating abstraction, Cold War board tension, dice as fate |
   | Real interfaces | Bloomberg terminals, grid operator SCADA screens, NORAD-style wall maps, UN briefing packs | How experts actually read dense information |
   | Data visualization | NASA Black Marble night lights, Electricity Maps, live flight radar, The Pudding essays | Making planetary data beautiful and legible |
   | Street level | Protest zines, community mesh-network maps, stickers and flyers | The Citizen Coalition's voice |
3. **Run a text audit.** List every piece of text on screen in one turn: labels, values, card body, options, log. For each, ask whether it could be a symbol, a color, a position, a motion or a sound, and mark it *keep as text*, *icon*, *diegetic* or *cut*. Most labels become icons. Most numbers become shapes. Prose survives only where it is the point (headlines, a faction's voice).
4. **Do a squint test.** Sketch one turn with no words at all and show it to someone. Can they tell what got worse, who acted and what they must decide? Wherever they can't, there's a visual gap.
5. **Prototype one screen three ways.** The crisis card is the best candidate. Try a Reigns-style swipe card, an illustrated tabloid front page and an Into the Breach-style map preview. Time-box each to a day, play them on a phone, and keep the one people talk about.
6. **Write a one-page art bible:** palette per era, palette per role, an icon grid, the typography hierarchy (where monospace earns its place), motion rules and what never changes.

Image-generation tools are good for fast concept exploration in steps 2 and 5. Claude can write the briefs and prompts for them, draft SVG icons and the art bible, and prototype screens directly in Godot.

## Ideas

### 1. Make the world the interface

Each macro metric gets a visible effect on the globe, so you read the state of the world by looking at it:

| Metric | On the globe | In the interface |
|---|---|---|
| Compute & energy | Night-side city and datacenter lights intensify; heat shimmer over clusters; brownout flicker when the grid throttles | A low hum that rises with saturation |
| Labor displacement | Cities lose their shift-change pulses; empty-tower silhouettes in the zoomed view | Crowds gather at datacenter campuses as icons |
| Geopolitical tension | Borders thicken and glow, embargo walls rise between blocs, launch arcs at the extreme | A heartbeat under the soundtrack |
| Algorithmic autonomy | Swarms of agent particles move along trade routes and, as autonomy grows, stop following them | Ticker items arrive with no human author |
| Alignment drift | The globe's grid warps | The interface itself glitches: chromatic aberration, misaligned panels, and at high drift a meter that briefly shows the wrong number |
| Epistemic trust | Cable pulses lose coherence | Headlines turn contradictory and provenance seals crack |

The last two rows matter most. When drift and distrust degrade the instruments themselves, the player experiences the game's thesis instead of reading it.

### 2. Fifty years should look like fifty years

Tie the interface to the model's eras and paradigm shifts:

- **Era 1, Silicon & Nuclear (2026–2035):** today's flat corporate dashboards. Light chrome, sans-serif type, familiar charts.
- **Era 2, Optical & SMR grids (2036–2049):** today's holographic look, with layered glass and cyan light.
- **Era 3, Neuromorphic (2050–2076):** organic or alien. Interface elements grow, pulse and rearrange; on ASI-heavy timelines they look machine-authored.

A paradigm shift becomes a visible "system upgrade" moment: the interface redraws itself in the new style over a few seconds.

### 3. Each faction sees a different world

Keep the mechanics and change the lens:

- **Frontier Lab CEO:** an investor deck and trading terminal. Tickers, capex curves, glossy product shots; the world as markets.
- **Governance Chair:** a situation room. Classified folders, stamps, redactions, pins on a paper map.
- **Emergent superintelligence:** raw perception. The world as a graph of nodes and gradients, humans as heat signatures, text shown as tokens with probabilities.
- **Citizen Coalition:** a street-level zine. Hand-drawn maps, stickers, mesh-network diagrams, flyers taped to the screen.

A cheap first version is a per-role palette, frame style, font pairing and icon set on the same layout.

### 4. Crisis cards you can read at a glance

- Each card gets illustration art (one image per category), a headline and a single sentence.
- Options show their effects as **glyphs with magnitude pips** (▲▲ tension, ▼ trust) instead of text.
- On phones, swipe left or right for the two main options, as in Reigns. Tap for the others, and hold any option to read its details.
- **Telegraph consequences**, as in Into the Breach: while a finger rests on an option, the vitals strip shows ghost bars of the predicted change and the globe previews it (a red ring appears, lights dim).

### 5. One glyph language everywhere

Design six metric glyphs plus one per currency, and use them on meters, card effects, log entries and the debrief. For example: a chip with a bolt for compute, a hard hat for labor, two facing arrows for tension, a looping arrow for autonomy, a compass needle off true north for drift, an eye for trust. Currencies become tokens such as coins, chips, badges and handshakes. Once the glyphs exist, much of the remaining text can go.

### 6. Headlines instead of logs

- The event feed becomes a news feed: generated headlines, a category image and a byline from the faction that acted. The LLM layer can already write these.
- Each era ends with a printed front page summarizing what happened.
- The debrief becomes a history book. Its chapters are the eras, its illustrated key events are taken from the campaign, and the trajectory chart sits in an appendix.

### 7. Put the decisions on the map (a bigger change)

Directives target regions. You drag a "Scale Frontier Clusters" card onto Phoenix, an embargo onto a bloc, a safety-net program onto a city. This makes the globe the core of play rather than a backdrop. It touches the simulation, which today is global, so treat it as a later milestone.

### 8. Sound, haptics and motion as information

- **Sound:** a grid hum, a tension heartbeat, radio static as trust falls, and the ASI's own sonic signature.
- **Haptics:** a short vibration on a severe crisis on phones (`Input.vibrate_handheld`).
- **A two-second turn cinematic:** the camera flies to the region that changed most and the numbers roll. The screen should rarely sit still.

### 9. Faces and voices

- Give every faction a portrait that ages across fifty years. The ASI's avatar evolves with substrate independence.
- Advisors deliver each crisis in one spoken line instead of a paragraph.
- When you play a human faction at high drift, the ASI becomes an unreliable narrator. Its actions look benign until the interface glitches and shows what really happened.

## Cheap first experiments in this codebase

| Experiment | Where | Rough size |
|---|---|---|
| Six metric glyphs (SVG), used in `MeterBar` and effect summaries | `ui/icons/`, `ui/components/meter_bar.gd`, `UiFormat.effects_summary` | 1–2 days |
| Drift glitch shader on the dashboard, intensity from alignment drift, with an option to turn it off | a CanvasItem shader on `MainDashboard` | half a day |
| Era palettes: build `CyberTheme` per era and cross-fade on era change | `ui/theme/` | 1 day |
| Crisis card art slot, effect glyphs and hold-to-preview ghost bars on the vitals strip | `DilemmaDialog`, `MeterBar` | 2–3 days |
| Role skins: accent color, frame and icon set per faction | `CyberTheme`, `CyberPalette` | 1 day |
| Headline cards in the LOG tab | `main_dashboard.gd` feed rendering | 1 day |

Start with the glyphs, the drift glitch and the era palettes. Together they change the feel of every turn without touching the simulation.

## What to keep

- **The depth of the model.** These ideas change how it reads, not what it computes.
- **An expert view.** Keep the current INTEL panel, with its exact numbers, for players who want them.
- **The hologram look.** It can become the look of era 2, or of the ASI's perception, instead of the look of everything.
