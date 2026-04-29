# =============================================================================
# Template: hook into existing scenes
# -----------------------------------------------------------------------------
# Tap into Scene_Map / Scene_Battle / Scene_Menu lifecycle events to draw
# overlays, intercept input, or react to scene transitions.
#
# What this template does: shows player coordinates as a small overlay in
# the top-left of the map screen.
# =============================================================================

class Scene_Map
  alias_method :_my_orig_start,    :start
  alias_method :_my_orig_update,   :update
  alias_method :_my_orig_terminate, :terminate

  def start
    _my_orig_start
    create_coord_overlay
  end

  def update
    _my_orig_update
    refresh_coord_overlay
  end

  def terminate
    _my_orig_terminate
    if @_my_coord_sprite
      @_my_coord_sprite.bitmap.dispose if @_my_coord_sprite.bitmap
      @_my_coord_sprite.dispose
      @_my_coord_sprite = nil
    end
  end

  def create_coord_overlay
    @_my_coord_sprite = Sprite.new
    @_my_coord_sprite.bitmap = Bitmap.new(220, 28)
    @_my_coord_sprite.bitmap.font.size = 18
    @_my_coord_sprite.bitmap.font.bold = true
    @_my_coord_sprite.x = 8
    @_my_coord_sprite.y = 8
    @_my_coord_sprite.z = 9999
  end

  def refresh_coord_overlay
    return unless @_my_coord_sprite && @_my_coord_sprite.bitmap && $game_player
    bmp = @_my_coord_sprite.bitmap
    bmp.clear
    bmp.draw_text(0, 0, bmp.width, bmp.height,
      "Map #{$game_map.map_id}  (#{$game_player.x},#{$game_player.y})")
  end
end

ModLoader.log("[05_scene_hook] coord overlay installed") rescue nil
