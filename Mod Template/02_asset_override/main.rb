# =============================================================================
# Template: asset override
# -----------------------------------------------------------------------------
# Replace any image or audio file from the original game.
#
# How it works:
#   The mod loader scans every <mod>/assets/ folder at startup and registers
#   the files inside as overrides. When the game asks for, say,
#   Graphics/Faces/Actor1, the loader's hooks redirect the read to your
#   <mod>/assets/Graphics/Faces/Actor1.png instead.
#
# Folder structure for asset overrides:
#
#   Mods/<your_mod>/
#     main.rb                              <- this file (can be empty/just log)
#     assets/
#       Graphics/
#         Faces/<filename>.png             <- replaces a face graphic
#         Characters/<filename>.png        <- replaces a sprite sheet
#         Pictures/<filename>.png          <- replaces a CG / picture
#         System/<filename>.png            <- replaces system UI (window skin etc.)
#         Battlebacks1/<filename>.png      <- battle background floor
#         Parallaxes/<filename>.png        <- map parallax
#       Audio/
#         BGM/<filename>.ogg               <- replaces a music track
#         BGS/<filename>.ogg               <- background sound
#         ME/<filename>.ogg                <- music effect (victory etc.)
#         SE/<filename>.ogg                <- sound effect
#       Data/
#         <name>.rvdata2                   <- replaces a data table (advanced)
#
# To find the original filename of an asset, look in
# mod_loader/docs/recon/all/Graphics/ or .../Audio/ which has the full
# decrypted archive sorted by type.
#
# main.rb can be empty for a pure asset mod, but you can also do extra Ruby
# work here -- the assets/ folder works regardless of what main.rb contains.
# =============================================================================

ModLoader.log("[02_asset_override] template active") rescue nil
