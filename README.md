# UnifiedBags335

A standalone single-bag UI for World of Warcraft **3.3.5a**, built to provide a Bagnon-style unified inventory experience without depending on Bagnon.

It supports Bags, Bank, Guild Bank, account inventory counts, and optional graphical Reagent Storage integration.

## Project Family

- **UnifiedBags335** — unified inventory UI (this repository)
- **BankReagentsUI** — client-side Reagent Storage/profession integration: https://github.com/Hisha/BankReagentsUI
- **mod-bank-reagents** — AzerothCore virtual Reagent Storage server module: https://github.com/Hisha/mod-bank-reagents

UnifiedBags335 works as a normal Bags/Bank/Guild Bank addon without the reagent projects. Install the other two when you want the complete Reagent Storage experience.

## Features

### Bags

- Single unified character inventory.
- Search.
- Character money display.
- Configurable columns, visible rows, and scale.
- Optional equipped-bag slot strip for swapping bags.
- Account-wide SavedVariables inventory cache and per-character tooltip counts.

### Bank

- Separate Bank window opens alongside Bags at a banker.
- Drag or right-click items between Bags and Bank.
- Optional bank-bag slot strip.
- Purchase unowned bank bag slots using Blizzard's normal confirmation flow.

### Reagent Storage

Requires both:

- https://github.com/Hisha/mod-bank-reagents
- https://github.com/Hisha/BankReagentsUI

Adds a **Reagent Storage** tab to the Bank window with search and item counts.

- Right-click: withdraw a normal stack.
- Left-drag: withdraw/move toward normal inventory.
- Shift-click: split/choose an amount.
- Auto-deposit can be enabled or disabled from UnifiedBags335 options while at a banker.

### Guild Bank

- Separate Guild Bank frame alongside Bags.
- Purchased guild-bank tabs with names and icons.
- Guild tab rename/icon editing.
- Guild money display.
- Deposit and permission-aware withdrawal controls.
- Native guild rank/tab permissions remain authoritative.
- Drag, right-click, and stack-split item movement.
- Guild leader tab-purchase support.
- Search and configurable columns.

## Installation

Clone or download this repository into:

```text
World of Warcraft/Interface/AddOns/UnifiedBags335/
```

Restart WoW or reload the UI.

UnifiedBags335 does **not** require Bagnon. If you currently use Bagnon, disable it while testing UnifiedBags335 so both addons do not attempt to own the same bag/bank UI.

## Complete Reagent Storage Setup

For the complete system, install all three projects:

1. AzerothCore server: https://github.com/Hisha/mod-bank-reagents
2. WoW client profession integration: https://github.com/Hisha/BankReagentsUI
3. WoW client unified inventory UI: this repository

The server module does not require either addon; stock 3.3.5 clients retain the banker gossip fallback.

## Design

UnifiedBags335 is presentation only. AzerothCore remains authoritative for inventory, bank, guild-bank, permissions, money, and Reagent Storage operations. No AzerothCore core patch is required.
