# Black Souls II - Mods

Bundled mods for the [Black Souls II Mod Loader](https://github.com/dazashu/Black-Souls-II-Mod-Loader).

Drop any of these folders into `BLACK SOULS II/Mods/` after the loader is installed.

📖 **[Full documentation site →](https://dazashu.github.io/Black-Souls-II-docs/)**

## Companion repos

- 🔧 [Black-Souls-II-Mod-Loader](https://github.com/dazashu/Black-Souls-II-Mod-Loader) - runtime mod loader (install this first)
- 📦 [Black-Souls-II-Asset-Extractor](https://github.com/dazashu/Black-Souls-II-Asset-Extractor) - extract / repack `Game.rgss3a`
- 📚 [Black-Souls-II-docs](https://github.com/dazashu/Black-Souls-II-docs) - documentation site source

---

## What's in here

### `Ultra_Quality/`

Press **F3** in-game to open. Display / visual quality menu:

- Fullscreen toggle (Alt+Enter)
- Window scale 1x / 2x / 3x (resizes the OS window)
- Tone presets: Cinematic / Vibrant / Soft / Dark / Off
- Brightness adjust
- Settings persist across launches via `Ultra_Quality/settings.txt`

### `creative_mode/`

A full in-game admin / creative menu. Press **F2** in-game to open it. Features:

- Per-actor stat / level editor
- Item picker (Items / Key Items / Weapons / Armors with icons + counts)
- Skill teaching
- Bonfire-map teleport
- Toggles: god mode, disable battles, no-clip, one-shot, always-crit, always-run, infinite souls, speed boost
- Misc: teleport to the Reminiscence Room, open BS2's bonfire travel scene

### `Mod Template/`

Five starter templates, each demonstrating one common modding pattern:

| Folder | Pattern |
|---|---|
| `01_simple_ruby/` | Basic `alias_method` monkey-patch |
| `02_asset_override/` | Replace any image / audio / data via `assets/` |
| `03_data_tweak/` | Runtime mutation of `$data_items`, `$data_weapons`, ... |
| `04_custom_scene/` | Add a new in-game screen with its own `Window` |
| `05_scene_hook/` | Hook `Scene_Map`'s lifecycle for overlays |

Copy any template into `BLACK SOULS II/Mods/<your_mod_name>/` and edit `main.rb`.

---

## Installation

1. Install the [Mod Loader](https://github.com/dazashu/Black-Souls-II-Mod-Loader) first.
2. Download creative_mode.zip from the releases.
3. Unzip the file.
4. Place it in your mods folder that the Mod Loader generated in the game files. It should look like `BLACK SOULS II/Mods/creative_mode`
5. Launch the game.

Each mod is self-contained - drop in the folder, that's it.

---

## Writing your own mod

A mod is a folder containing `main.rb` (plain Ruby 1.9 with full RGSS3 access). Optionally a `manifest.txt` for metadata, and an `assets/` subfolder for graphic / audio / data overrides:

```
my_first_mod/
├── main.rb
├── manifest.txt              (optional)
└── assets/                   (optional)
    └── Graphics/
        └── Faces/Custom.png  ← replaces Faces/Custom.png at runtime
```

Minimal example:

```ruby
# my_first_mod/main.rb
class Game_Actor
  alias_method :_orig_setup, :setup
  def setup(actor_id)
    _orig_setup(actor_id)
    @name = "Custom Name"
  end
end
ModLoader.log("[my_first_mod] hooked Game_Actor.setup") rescue nil
```

For the full API, hooks, and asset-override conventions, see the [docs site](https://dazashu.github.io/Black-Souls-II-docs/).

---

## License

MIT.
