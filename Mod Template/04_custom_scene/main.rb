# =============================================================================
# Template: custom Scene with a Window
# -----------------------------------------------------------------------------
# Add a brand new screen to the game. This template creates a tiny "Hello"
# scene with a single button. Open it with F3 from the map.
#
# Pattern:
#   - Subclass Scene_MenuBase (or Scene_Base)
#   - Create your Window subclasses
#   - Use SceneManager.call(YourScene) / SceneManager.return to enter/exit
#
# For the F3 hotkey we poll Win32 GetAsyncKeyState because the vanilla Input
# module doesn't include F-keys.
# =============================================================================

class Window_HelloHello < Window_Command
  def window_width;  280 end
  def make_command_list
    add_command("Hello, mod world", :hello)
    add_command("Close",            :cancel)
  end
end

class Scene_HelloHello < Scene_MenuBase
  def start
    super
    @window = Window_HelloHello.new
    @window.x = (Graphics.width  - @window.width)  / 2
    @window.y = (Graphics.height - @window.height) / 2
    @window.set_handler(:hello,  method(:on_hello))
    @window.set_handler(:cancel, method(:return_scene))
    @window.activate
    @window.select(0)
  end

  def on_hello
    ModLoader.log("[04_custom_scene] hello pressed") rescue nil
    @window.activate
  end
end

# F3 hotkey on the map
begin
  GetAsyncKeyState = Win32API.new("user32", "GetAsyncKeyState", "i", "i")
  @prev_f3_down = false

  class Scene_Map
    alias_method :_my_orig_update, :update
    def update
      _my_orig_update
      down = (Win32API.new("user32","GetAsyncKeyState","i","i").call(0x72) & 0x8000) != 0
      if down && !($my_prev_f3_down ||= false)
        SceneManager.call(Scene_HelloHello)
      end
      $my_prev_f3_down = down
    end
  end
rescue => e
  ModLoader.log("[04_custom_scene] hotkey hook failed: #{e.message}") rescue nil
end

ModLoader.log("[04_custom_scene] ready -- press F3 on the map") rescue nil
