# =============================================================================
# Ultra Quality v1.0 - F3 menu for fullscreen / window-scale / visual presets
#
# RGSS3 / VX Ace renders the game at a fixed 544x416. We can't change that
# from Ruby. What this mod does:
#   - Fullscreen toggle (Alt+Enter)
#   - Resize the host OS window 1x / 2x / 3x (still 544x416 internally,
#     scaled by the OS window manager)
#   - Cinematic / Vibrant / Soft / Off tone presets
#   - Brightness adjust
#   - Persistent settings (Mods/Ultra_Quality/settings.txt)
#
# Author: dazashu
# =============================================================================

module UltraQuality
  VERSION = "1.0.0".freeze
  TITLE   = "Ultra Quality".freeze

  # ---- Win32 bindings -------------------------------------------------------
  begin
    KEYBD_EVENT       = Win32API.new('user32', 'keybd_event', ['I','I','L','L'], 'V')
    GET_KEY_STATE     = Win32API.new('user32', 'GetAsyncKeyState', ['I'], 'I')
    FIND_WINDOW       = Win32API.new('user32', 'FindWindowA', ['P','P'], 'L')
    GET_WINDOW_RECT   = Win32API.new('user32', 'GetWindowRect', ['L','P'], 'I')
    SET_WINDOW_POS    = Win32API.new('user32', 'SetWindowPos', ['L','L','I','I','I','I','I'], 'I')
    GET_SYSTEM_METRICS = Win32API.new('user32', 'GetSystemMetrics', ['I'], 'I')
    GET_DESKTOP_WINDOW = Win32API.new('user32', 'GetDesktopWindow', [], 'L')
  rescue => e
    ModLoader.log("[UltraQuality] Win32API bindings failed: #{e.message}") rescue nil
  end

  VK_MENU         = 0x12   # Alt
  VK_RETURN       = 0x0D
  VK_F3           = 0x72
  KEYEVENTF_KEYUP = 0x0002
  SM_CXSCREEN     = 0
  SM_CYSCREEN     = 1
  SWP_NOZORDER    = 0x0004
  SWP_NOMOVE      = 0x0002
  SWP_SHOWWINDOW  = 0x0040

  # ---- State ----------------------------------------------------------------
  @scale       = 1            # 1, 2, 3
  @tone_preset = :off         # :off, :cinematic, :vibrant, :soft, :dark
  @brightness  = 255          # 0..255
  @fullscreen  = false        # tracked, not authoritative (user can Alt+Enter manually)

  class << self
    attr_accessor :scale, :tone_preset, :brightness, :fullscreen
  end

  TONE_PRESETS = {
    :off       => Tone.new(  0,   0,   0,   0),
    :cinematic => Tone.new(-15, -10,  10,  20),
    :vibrant   => Tone.new( 15,  10,   0, -20),
    :soft      => Tone.new( 10,  10,  10,  10),
    :dark      => Tone.new(-30, -25, -20,  10),
  }
  TONE_LABELS = {
    :off       => "Off (vanilla)",
    :cinematic => "Cinematic (cool, faded)",
    :vibrant   => "Vibrant (saturated)",
    :soft      => "Soft (warm wash)",
    :dark      => "Dark (atmospheric)",
  }

  # ---- Settings persistence -------------------------------------------------
  def self.settings_path
    return @settings_path if @settings_path
    base = (defined?(MOD_DIR) && MOD_DIR.is_a?(String)) ? MOD_DIR : nil
    base ||= File.expand_path("..", __FILE__) rescue Dir.pwd
    @settings_path = File.join(base, "settings.txt")
  end

  def self.load_settings
    return unless File.exist?(settings_path)
    File.foreach(settings_path) do |line|
      k, v = line.strip.split("=", 2)
      next unless k && v
      case k
      when "scale"       then @scale      = v.to_i.clamp(1, 3) rescue 1
      when "tone_preset" then @tone_preset = v.to_sym if TONE_PRESETS.key?(v.to_sym)
      when "brightness"  then @brightness = v.to_i.clamp(0, 255)
      when "fullscreen"  then @fullscreen = (v == "true")
      end
    end
    ModLoader.log("[UltraQuality] settings loaded: scale=#{@scale} tone=#{@tone_preset}") rescue nil
  rescue => e
    ModLoader.log("[UltraQuality] settings load error: #{e.message}") rescue nil
  end

  def self.save_settings
    File.open(settings_path, "w") do |f|
      f.puts "scale=#{@scale}"
      f.puts "tone_preset=#{@tone_preset}"
      f.puts "brightness=#{@brightness}"
      f.puts "fullscreen=#{@fullscreen}"
    end
  rescue => e
    ModLoader.log("[UltraQuality] settings save error: #{e.message}") rescue nil
  end

  # ---- Fullscreen (Alt+Enter sim) -------------------------------------------
  def self.toggle_fullscreen
    return unless defined?(KEYBD_EVENT)
    KEYBD_EVENT.call(VK_MENU,   0, 0, 0)
    KEYBD_EVENT.call(VK_RETURN, 0, 0, 0)
    KEYBD_EVENT.call(VK_RETURN, 0, KEYEVENTF_KEYUP, 0)
    KEYBD_EVENT.call(VK_MENU,   0, KEYEVENTF_KEYUP, 0)
    @fullscreen = !@fullscreen
    save_settings
  end

  # ---- Window scaling -------------------------------------------------------
  def self.find_game_window
    return @hwnd if @hwnd && @hwnd != 0
    return 0 unless defined?(FIND_WINDOW)
    h = FIND_WINDOW.call("RGSS Player", nil)
    h = FIND_WINDOW.call(nil, "Black Souls II") if h == 0
    h = FIND_WINDOW.call(nil, $data_system && $data_system.game_title.to_s) if h == 0 && $data_system
    @hwnd = h
    h
  end

  def self.set_window_scale(n)
    return unless defined?(SET_WINDOW_POS)
    n = n.to_i.clamp(1, 3)
    @scale = n
    hwnd = find_game_window
    return if hwnd == 0
    base_w = 544; base_h = 416
    # add a buffer for the title bar / borders (approx, varies per Windows version)
    border_w = 16
    border_h = 39
    new_w = base_w * n + border_w
    new_h = base_h * n + border_h
    SET_WINDOW_POS.call(hwnd, 0, 0, 0, new_w, new_h, SWP_NOMOVE | SWP_NOZORDER | SWP_SHOWWINDOW)
    save_settings
  end

  # ---- Visual presets -------------------------------------------------------
  def self.apply_tone_preset(key)
    @tone_preset = key
    apply_current_tone
    save_settings
  end

  def self.apply_current_tone
    tone = TONE_PRESETS[@tone_preset] || TONE_PRESETS[:off]
    if $game_map && $game_map.screen
      $game_map.screen.start_tone(tone.dup, 30)
    end
  end

  def self.set_brightness(b)
    @brightness = b.to_i.clamp(0, 255)
    Graphics.brightness = @brightness rescue nil
    save_settings
  end

  # ---- F3 hotkey poller (run from Scene_Base#update) ------------------------
  def self.poll_hotkey
    return false unless defined?(GET_KEY_STATE)
    state = GET_KEY_STATE.call(VK_F3)
    pressed = (state & 0x8000) != 0
    triggered = pressed && !@f3_was_down
    @f3_was_down = pressed
    triggered
  end

  # ---- Boot apply -----------------------------------------------------------
  def self.apply_on_boot
    Graphics.brightness = @brightness rescue nil
    set_window_scale(@scale) if @scale != 1
    apply_current_tone
  rescue => e
    ModLoader.log("[UltraQuality] apply_on_boot error: #{e.message}") rescue nil
  end
end

UltraQuality.load_settings

# =============================================================================
# Scene_UltraQuality - the F3 menu
# =============================================================================
class Scene_UltraQuality < Scene_MenuBase
  def start
    super
    create_command_window
    create_help_window
    update_help
  end

  def create_command_window
    @command_window = Window_UltraQualityCmd.new
    @command_window.set_handler(:fullscreen,    method(:on_fullscreen))
    @command_window.set_handler(:scale_1,       method(:on_scale_1))
    @command_window.set_handler(:scale_2,       method(:on_scale_2))
    @command_window.set_handler(:scale_3,       method(:on_scale_3))
    @command_window.set_handler(:tone_off,      method(:on_tone_off))
    @command_window.set_handler(:tone_cine,     method(:on_tone_cine))
    @command_window.set_handler(:tone_vibrant,  method(:on_tone_vibrant))
    @command_window.set_handler(:tone_soft,     method(:on_tone_soft))
    @command_window.set_handler(:tone_dark,     method(:on_tone_dark))
    @command_window.set_handler(:bright_up,     method(:on_bright_up))
    @command_window.set_handler(:bright_down,   method(:on_bright_down))
    @command_window.set_handler(:reset,         method(:on_reset))
    @command_window.set_handler(:cancel,        method(:return_scene))
  end

  def create_help_window
    @help_window = Window_Help.new(2)
    @help_window.x = 0
    @help_window.y = Graphics.height - @help_window.height
    @help_window.opacity = 220
  end

  def update
    super
    update_help if @command_window && @command_window.active
  end

  def update_help
    return unless @help_window && @command_window
    sym = @command_window.current_symbol
    msg = case sym
          when :fullscreen
            "Toggle Alt+Enter fullscreen. Currently: #{UltraQuality.fullscreen ? 'ON' : 'off'}"
          when :scale_1, :scale_2, :scale_3
            n = sym.to_s[-1].to_i
            "Resize host window to #{n}x. Game still renders 544x416 internally; OS scales the window."
          when :tone_off, :tone_cine, :tone_vibrant, :tone_soft, :tone_dark
            "Screen tone preset. Applies on the map."
          when :bright_up    then "Brightness +. Currently: #{UltraQuality.brightness}/255"
          when :bright_down  then "Brightness -. Currently: #{UltraQuality.brightness}/255"
          when :reset        then "Reset everything to vanilla."
          else                    "Ultra Quality v#{UltraQuality::VERSION}. ESC to close."
          end
    @help_window.set_text(msg)
  end

  def refresh_after_action
    @command_window.refresh
    @command_window.activate
    update_help
  end

  # ---- Handlers ----
  def on_fullscreen
    UltraQuality.toggle_fullscreen
    refresh_after_action
  end

  def on_scale_1; UltraQuality.set_window_scale(1); refresh_after_action; end
  def on_scale_2; UltraQuality.set_window_scale(2); refresh_after_action; end
  def on_scale_3; UltraQuality.set_window_scale(3); refresh_after_action; end

  def on_tone_off;     UltraQuality.apply_tone_preset(:off);       refresh_after_action; end
  def on_tone_cine;    UltraQuality.apply_tone_preset(:cinematic); refresh_after_action; end
  def on_tone_vibrant; UltraQuality.apply_tone_preset(:vibrant);   refresh_after_action; end
  def on_tone_soft;    UltraQuality.apply_tone_preset(:soft);      refresh_after_action; end
  def on_tone_dark;    UltraQuality.apply_tone_preset(:dark);      refresh_after_action; end

  def on_bright_up
    UltraQuality.set_brightness(UltraQuality.brightness + 16)
    refresh_after_action
  end
  def on_bright_down
    UltraQuality.set_brightness(UltraQuality.brightness - 16)
    refresh_after_action
  end

  def on_reset
    UltraQuality.set_window_scale(1)
    UltraQuality.apply_tone_preset(:off)
    UltraQuality.set_brightness(255)
    refresh_after_action
  end
end

# =============================================================================
# Window_UltraQualityCmd - the menu list (Window_Command, F1-style)
# =============================================================================
class Window_UltraQualityCmd < Window_Command
  def initialize
    super((Graphics.width - window_width) / 2, 60)
  end

  def window_width;  360; end
  def visible_line_number; 13; end

  def make_command_list
    fs    = UltraQuality.fullscreen ? "ON " : "off"
    scale = UltraQuality.scale
    tp    = UltraQuality.tone_preset
    br    = UltraQuality.brightness

    add_command("Fullscreen toggle (Alt+Enter)  [#{fs}]", :fullscreen)
    add_command("Window scale: 1x  #{scale==1 ? '<' : ' '}",  :scale_1)
    add_command("Window scale: 2x  #{scale==2 ? '<' : ' '}",  :scale_2)
    add_command("Window scale: 3x  #{scale==3 ? '<' : ' '}",  :scale_3)
    add_command("Tone: Off          #{tp==:off       ? '<' : ' '}", :tone_off)
    add_command("Tone: Cinematic    #{tp==:cinematic ? '<' : ' '}", :tone_cine)
    add_command("Tone: Vibrant      #{tp==:vibrant   ? '<' : ' '}", :tone_vibrant)
    add_command("Tone: Soft         #{tp==:soft      ? '<' : ' '}", :tone_soft)
    add_command("Tone: Dark         #{tp==:dark      ? '<' : ' '}", :tone_dark)
    add_command("Brightness +       [#{br}/255]",                    :bright_up)
    add_command("Brightness -       [#{br}/255]",                    :bright_down)
    add_command("Reset to defaults",                                 :reset)
    add_command("Close",                                             :cancel)
  end
end

# =============================================================================
# Hotkey: F3 opens the menu from any scene
# =============================================================================
class Scene_Base
  alias_method :_uq_orig_update, :update unless method_defined?(:_uq_orig_update)

  def update
    _uq_orig_update
    if UltraQuality.poll_hotkey
      # only trigger when not already inside it, and not in a "modal" scene
      unless SceneManager.scene.is_a?(Scene_UltraQuality)
        SceneManager.call(Scene_UltraQuality) rescue nil
      end
    end
  rescue => e
    ModLoader.log("[UltraQuality] hotkey error: #{e.message}") rescue nil
  end
end

# Re-apply tone whenever a map starts (since tone is per-screen, per-map)
class Scene_Map
  alias_method :_uq_orig_start, :start unless method_defined?(:_uq_orig_start)
  def start
    _uq_orig_start
    UltraQuality.apply_current_tone rescue nil
  end
end

# Apply window-scale once at boot
DataManager.run_once = false unless DataManager.respond_to?(:run_once)
class << DataManager
  alias_method :_uq_orig_load_normal_database, :load_normal_database rescue nil
  def load_normal_database
    _uq_orig_load_normal_database if respond_to?(:_uq_orig_load_normal_database)
    @uq_booted ||= false
    unless @uq_booted
      UltraQuality.apply_on_boot rescue nil
      @uq_booted = true
    end
  end
end

ModLoader.log("[Ultra_Quality] loaded v#{UltraQuality::VERSION}") rescue nil
