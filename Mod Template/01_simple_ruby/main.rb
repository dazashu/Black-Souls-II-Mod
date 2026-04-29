# =============================================================================
# Template: simple Ruby mod
# -----------------------------------------------------------------------------
# The most common pattern: monkey-patch an existing game class. Use
# alias_method to keep the original behaviour and add your own on top.
#
# What this template does: makes the player gain 5 souls per step on the map.
# =============================================================================

class Game_Player
  # `alias_method :_orig_increase_steps, :increase_steps`  saves a reference
  # to the original method under a new name. Then we redefine increase_steps,
  # call the original, then add our extra logic.
  alias_method :_my_orig_increase_steps, :increase_steps
  def increase_steps
    _my_orig_increase_steps
    if $game_party
      $game_party.gain_gold(5) rescue nil
    end
  end
end

# ModLoader.log writes to Mods/_loader.log and the in-game console.
ModLoader.log("[01_simple_ruby] hooked Game_Player#increase_steps") rescue nil
