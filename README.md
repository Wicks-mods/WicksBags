<p align="center"><img src="images/wick-thumb-bags.png" alt="Wick's Bags"></p>

# Wick's Bags

> Categorized bags and bank for World of Warcraft: Forever. Auto-categorize, search, one-click sort, alt inventory and tooltips, custom rules.

Part of the **[Wick suite](https://github.com/Wicksmods/WickSuite)**: precision addons built around a single fel-green-on-deep-purple aesthetic. This branch (`forever`) is the Forever build on [WickCore](https://github.com/Wicksmods/WickCore). The TBC Anniversary build lives on `main`.

<!-- wick:suite-table:start -->
| Addon | GitHub | CurseForge |
|---|---|---|
| **WickCore** | [repo](https://github.com/Wicksmods/WickCore) | [CurseForge](https://www.curseforge.com/wow/addons/wickcore) |
| **Wick's Comforts** | [repo](https://github.com/Wicksmods/WicksComforts) | [CurseForge](https://www.curseforge.com/wow/addons/wicks-comforts) |
| **Wick's Beasts and Things** | [repo](https://github.com/Wicksmods/WicksBeastsAndThings) | [CurseForge](https://www.curseforge.com/wow/addons/wicks-beasts-and-things) |
| **Wick's Stances and Things** | [repo](https://github.com/Wicksmods/WicksStancesAndThings) | [CurseForge](https://www.curseforge.com/wow/addons/wicks-stances-and-things) |
| **Wick's Seals and Things** | [repo](https://github.com/Wicksmods/WicksSealsAndThings) | [CurseForge](https://www.curseforge.com/wow/addons/wicks-seals-and-things) |
| **Wick's Conjures and Things** | [repo](https://github.com/Wicksmods/WicksConjuresAndThings) | [CurseForge](https://www.curseforge.com/wow/addons/wicks-conjures-and-things) |
| **Wick's Poisons and Things** | [repo](https://github.com/Wicksmods/WicksPoisonsAndThings) | [CurseForge](https://www.curseforge.com/wow/addons/wicks-poisons-and-things) |
| **Wick's Demons and Things** | [repo](https://github.com/Wicksmods/WicksDemonsAndThings) | [CurseForge](https://www.curseforge.com/wow/addons/wicks-demons-and-things) |
| **Wick's Bags** | [repo](https://github.com/Wicksmods/WicksBags) | [CurseForge](https://www.curseforge.com/wow/addons/wicks-bags) |
| **Wick's Trade Hall** | [repo](https://github.com/Wicksmods/WicksTradeHall) | [CurseForge](https://www.curseforge.com/wow/addons/trade-hall) |
| **Wick's Gear** | [repo](https://github.com/Wicksmods/WicksGear) | [CurseForge](https://www.curseforge.com/wow/addons/wicks-gear) |
| **Wick's UI** | [repo](https://github.com/Wicksmods/WicksUIForever) | [CurseForge](https://www.curseforge.com/wow/addons/wicks-ui) |

**Community:** [Discord](https://discord.gg/GWGTMhYBZY)
<!-- wick:suite-table:end -->

## Features

- **One window** for bags, and one for the bank, replacing the bag clutter view.
- **Auto-categorize** by item type: Equipment, Potion, Elixir, Flask, Food, Cloth, Leather, Herb, Enchanting, Quest, Recipe, Key, Junk and more, grouped under parent headers.
- **Custom rules** by item, by class and subclass, or by name pattern, plus your own categories.
- **Live search** across bags and bank.
- **One-click sort** for bags and bank, then the categories lay back out.
- **Bank tabs.** Forever's bank is purchasable tabs; the panel shows them as one categorized view, with a filter per tab and the next tab's price on the buy button.
- **Alt inventory viewer** with snapshots of every character's bags and bank, and **alt counts in item tooltips** so you know which character has the mats.
- **Watched currencies** in the bottom bar.
- **Quality borders, item level, new-item highlights, cooldown spirals, use-on-click.**
- **Profiles** keyed by character, spec, class or game mode, with export and import strings, through WickCore.
- **Wick chrome.** Void background, fel-green L-bracket corners, two-tone "Wick's" title.

## Install

Requires **[WickCore](https://github.com/Wicksmods/WickCore)**.

- **Manual:** download the latest ZIP from [Releases](https://github.com/Wicksmods/WicksBags/releases) and extract the `WicksBags` folder into the Forever client's `Interface\AddOns\` (the beta installs to `World of Warcraft\_classic_beta_\`). Do the same for `WickCore`.

## Usage

```
/wbags
```

Toggles the main panel. Bind a key in *Esc, Key Bindings, AddOns, Wick's Bags* if you prefer. The Wick minimap button and the "Wick's Mods" entry in Options also open it.

| Command | Effect |
|---|---|
| `/wbags` | Toggle the panel |
| `/wbags options` | Open the options window |
| `/wbags alts` | Open the alt inventory viewer |
| `/wbags sort` | One-click sort |
| `/wbags show` / `hide` | Show or hide |
| `/wbags reset` | Reset position to center |
| `/wbags autoopen on|off` | Auto-open at mailbox, vendor, bank |

`/wicksbags` and `/wb` are aliases.

## Compatibility

- World of Warcraft: Forever, 1.60.x, Interface 16001. Requires WickCore.
- The same code runs on TBC Anniversary through WickCore's dialect shim, but the supported TBC build is the `main` branch.

## License

MIT for code (see [LICENSE](LICENSE)). Brand chrome and the "Wick's" wordmark are trademarked, see [TRADEMARK.md](https://github.com/Wicksmods/WickSuite/blob/main/TRADEMARK.md) in the Wick Suite repo.
