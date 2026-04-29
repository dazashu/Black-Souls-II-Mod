================================================================
 BS_ModLoader -- Mod Templates
================================================================

These folders are starting points for building your own mods.
Copy any of them into BLACK SOULS II/Mods/<your_name>/ and edit.

  01_simple_ruby/      Tiny alias_method monkey-patch (Ruby 101).
  02_asset_override/   Replace any image / audio / data file by
                       dropping it into the mod's assets/ folder.
  03_data_tweak/       Mutate $data_items / $data_weapons / etc.
                       at runtime (no save corruption).
  04_custom_scene/     Add a brand-new in-game screen with its own
                       Window_Command. Demo opens with F3.
  05_scene_hook/       Hook Scene_Map's lifecycle to draw overlays
                       (player coordinates HUD).

For class names and method signatures the live game actually uses,
see  mod_loader/docs/recon/DOCUMENTATION.md  and the per-script
sources in  mod_loader/docs/recon/scripts/ .

For asset filenames (graphics, audio), see
  mod_loader/docs/recon/all/Graphics/  and  BLACK SOULS II/Audio/
================================================================
