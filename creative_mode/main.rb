# =============================================================================
# Creative Mode v0.7 — F2 creative-mode menu for Black Souls II
# (Module name AdminMenu retained internally for compatibility with existing
#  hooks; only the user-facing labels say "Creative Mode".)
# =============================================================================

module AdminMenu
  VERSION = "0.7.0".freeze
  TITLE   = "Creative Mode".freeze

  begin
    GetAsyncKeyState = Win32API.new("user32", "GetAsyncKeyState", "i", "i")
  rescue Exception
    GetAsyncKeyState = nil
  end

  VK = { f2: 0x71, shift: 0x10, ctrl: 0x11, alt: 0x12 }.freeze

  PARAM_NAMES = ["MaxHP", "MaxMP", "ATK", "DEF", "MAT", "MDF", "AGI", "LUK"].freeze

  # ----- toggles / persistent state -----
  @god_mode        = false
  @disable_battles = false
  @noclip          = false
  @speed_boost     = false
  @speed_amount    = 2
  @one_shot_mode   = false
  @always_crit     = false
  @always_run      = false
  @infinite_souls  = false
  @prev_keys       = {}
  @notes           = []
  @npc_index       = nil
  @covenant_index  = nil

  class << self
    attr_accessor :god_mode, :disable_battles, :noclip, :speed_boost,
                  :speed_amount, :one_shot_mode, :always_crit,
                  :always_run, :infinite_souls

    def clamp(v, lo, hi)
      v < lo ? lo : (v > hi ? hi : v)
    end

    def key_down?(vk)
      return false unless GetAsyncKeyState
      (GetAsyncKeyState.call(vk) & 0x8000) != 0
    end

    def key_pressed?(vk)
      now = key_down?(vk)
      was = @prev_keys[vk]
      @prev_keys[vk] = now
      now && !was
    end

    def update_global_keys
      @speed_boost = key_down?(VK[:shift])
    end

    def per_frame_tick
      if @infinite_souls && $game_party && $game_party.gold < 50_000_000
        $game_party.gain_gold(99_999_999 - $game_party.gold)
      end
      drain_switch_queue
    end

    # Queued switch flips — drained one per frame on Scene_Map so autorun
    # events with newly-met conditions fire individually instead of as a
    # 30+-event simultaneous cascade (which crashes BS2 hard).
    @pending_switches = []

    def queue_switches_on(ids)
      @pending_switches ||= []
      @pending_switches.concat(ids.uniq)
      note("Queued #{ids.size} switches -- flipping over ~#{ids.size} frames once you exit the menu.")
    end

    def drain_switch_queue
      @pending_switches ||= []
      return if @pending_switches.empty?
      return unless $game_switches
      sid = @pending_switches.shift
      begin
        $game_switches[sid] = true
      rescue Exception => e
        note("Switch #{sid} flip failed: #{e.class}: #{e.message}")
      end
    end

    def pending_switch_count
      @pending_switches ||= []
      @pending_switches.size
    end

    def note(msg)
      @notes.unshift(msg.to_s)
      @notes = @notes.first(10)
      ModLoader.log("[admin] #{msg}") rescue nil
    end

    def notes; @notes; end

    def categories
      [
        [:player,    "Player & Party"  ],
        [:items,     "Items"           ],
        [:skills,    "Teach Skills"    ],
        [:teleport,  "Teleport"        ],
        [:toggles,   "Toggles"         ],
        [:world,     "Misc"            ],
        [:close,     "Close Menu"      ],
      ]
    end

    # ---------- Lazy NPC index (scans every map for named events) ----------
    EVENT_SKIP_PATTERNS = [
      /\AEV\d+\z/,          # default unnamed events
      /\Asym(bol)?[_\d]/i,  # symbol enemies
      /\A敵|\Aシンボル|\Aenemy/i,
      /\A宝箱|\Achest|\Aitem|\Atreasure/i,
      /\A扉|\Adoor/i,
      /\A出入|\Atransfer|\A切替/i,
      /\A看板|\Asign|\Anote/i,
      /\Aテスト|\Atest|\Adebug/i,
      /\A\s*\z/,
    ].freeze

    # Treat an event as a "real, interactable NPC" only if it has at least one
    # page with trigger=0 (Action Button) AND that page contains a Show Text
    # (cmd 101) or Show Choices (cmd 102) command. That filters out symbols,
    # decorations, autorun setup events, region triggers, etc.
    def event_is_interactable?(ev)
      return false unless ev && ev.pages
      ev.pages.each do |page|
        next unless page
        next unless page.trigger == 0
        next unless page.list
        return true if page.list.any? { |cmd| cmd && (cmd.code == 101 || cmd.code == 102) }
      end
      false
    end

    def clean_event_name(raw)
      # Strip BS2 state-condition tags like <uninhibited>, <crouching>, <lewd>
      cleaned = raw.to_s.gsub(/<[^>]*>/, "").strip
      cleaned.empty? ? raw.to_s.strip : cleaned
    end

    # ---- Translation table for BS2 character / state names. ----
    # Extend at will: leftmost is the Japanese form, right is the English
    # display form. clean_event_name() looks up here BEFORE giving up.
    TRANSLATIONS = {
      # ----- Carroll cast -----
      "アリス"          => "Alice",
      "リトルアリス"    => "Little Alice",
      "白の女王"        => "White Queen",
      "ハートの女王"    => "Queen of Hearts",
      "赤の女王"        => "Red Queen",
      "白の王"          => "White King",
      "黒の王"          => "Black King",
      "ハートの王"      => "King of Hearts",
      "帽子屋"          => "Hatter",
      "三月ウサギ"      => "March Hare",
      "ヤマネ"          => "Dormouse",
      "チェシャ猫"      => "Cheshire Cat",
      "チェシャ"        => "Cheshire",
      "公爵夫人"        => "Duchess",
      "イモムシ"        => "Caterpillar",
      "グリフォン"      => "Gryphon",
      "ニセウミガメ"    => "Mock Turtle",
      "白ウサギ"        => "White Rabbit",
      "ハンプティ"      => "Humpty",
      "ダンプティ"      => "Dumpty",
      "ハンプティダンプティ" => "Humpty Dumpty",
      "リドル"          => "Liddell",
      "ドジソン"        => "Dodgson",
      "ジャバウォック"  => "Jabberwock",
      "ジャブジャブ"    => "Jubjub",
      "バンダースナッチ" => "Bandersnatch",
      # ----- Peter Pan / Neverland -----
      "ピーター"        => "Peter",
      "ピーターパン"    => "Peter Pan",
      "ティンカーベル"  => "Tinker Bell",
      "ウェンディ"      => "Wendy",
      "フック船長"      => "Captain Hook",
      "スミー"          => "Smee",
      # ----- Common BS2 NPC roles -----
      "兵卒"            => "Soldier",
      "兵士"            => "Soldier",
      "村人"            => "Villager",
      "商人"            => "Merchant",
      "店員"            => "Shopkeeper",
      "鍛冶屋"          => "Blacksmith",
      "司祭"            => "Priest",
      "修道女"          => "Nun",
      "騎士"            => "Knight",
      "医者"            => "Doctor",
      "看護"            => "Nurse",
      "看護師"          => "Nurse",
      "宿屋"            => "Innkeeper",
      "警備"            => "Guard",
      "警備兵"          => "Guard",
      "盗賊"            => "Thief",
      "魔女"            => "Witch",
      "妖精"            => "Fairy",
      "幽霊"            => "Ghost",
      "少女"            => "Girl",
      "少年"            => "Boy",
      "女"              => "Woman",
      "男"              => "Man",
      "女性"            => "Woman",
      "男性"            => "Man",
      "母親"            => "Mother",
      "父親"            => "Father",
      "子供"            => "Child",
      "老人"            => "Old man",
      "老婆"            => "Old woman",
      "茶"              => "Tea",
      "茶会"            => "Tea Party",
      # ----- State / condition tags (the <...> markers) -----
      "通常"            => "normal",
      "服従"            => "submissive",
      "寵愛"            => "favored",
      "堕落"            => "fallen",
      "狂気"            => "mad",
      "純愛"            => "pure",
      "疲弊"            => "exhausted",
      "発情"            => "aroused",
      "妊娠"            => "pregnant",
      "病気"            => "sick",
      "回想"            => "memory",
      "思い出"          => "memory",
    }.freeze

    # Try to translate a Japanese-flavored name into something readable.
    # Returns the original string if no token matches.
    def translate_name(s)
      return s if s.nil? || s.empty?
      out = s.dup
      # Longest-first key replacement so multi-char tokens win over short ones
      keys = TRANSLATIONS.keys.sort_by { |k| -k.length }
      keys.each do |k|
        out = out.gsub(k, TRANSLATIONS[k])
      end
      out.strip
    end

    def npc_index
      return @npc_index if @npc_index
      @npc_index = []
      return @npc_index unless $data_mapinfos
      seen = {}                                  # dedup (map_id, name) keys
      $data_mapinfos.each do |map_id, info|
        next unless info && info.name && !info.name.empty?
        path = sprintf("Data/Map%03d.rvdata2", map_id)
        map = (load_data(path) rescue nil)
        next unless map && map.events
        map.events.each do |_eid, ev|
          next unless ev && ev.name && !ev.name.strip.empty?
          raw = ev.name.strip
          next if EVENT_SKIP_PATTERNS.any? { |re| re =~ raw }
          next unless event_is_interactable?(ev)
          name = clean_event_name(raw)
          translated = translate_name(name)
          map_translated = translate_name(info.name)
          key = [map_id, translated]
          next if seen[key]
          seen[key] = true
          @npc_index << {
            :map_id        => map_id,
            :map_name      => map_translated,
            :event_name    => translated,     # what we show
            :event_name_jp => name,            # original
            :x             => ev.x,
            :y             => ev.y,
          }
        end
      end
      @npc_index.sort_by! { |e| [e[:map_name].to_s, e[:event_name].to_s] }
      note("NPC index: #{@npc_index.size} NPC(s)")
      @npc_index
    rescue Exception => e
      note("NPC scan failed: #{e.class}: #{e.message}")
      @npc_index = []
    end

    def covenant_index
      return @covenant_index if @covenant_index
      spirit_actor_ids = []
      if defined?(Spirits) && Spirits.respond_to?(:actor_id)
        (1..100).each do |sid|
          aid = (Spirits.actor_id(sid) rescue 0)
          spirit_actor_ids << aid if aid && aid > 0
        end
      end
      spirit_actor_ids.uniq!
      spirit_names = spirit_actor_ids.map { |aid|
        a = ($data_actors[aid] rescue nil)
        a && a.name.to_s.strip.empty? ? nil : (a && a.name)
      }.compact
      list = npc_index.select { |entry|
        nm = entry[:event_name].to_s
        spirit_names.any? { |sn| !sn.to_s.empty? && (nm == sn || nm.include?(sn)) }
      }
      @covenant_index = list
      note("Covenant locations found: #{list.size}")
      @covenant_index
    end

    # ---------- H-scene gallery: find recall/scene unlock switches by name ---
    # Narrow patterns only — generic words like "scene"/"memory"/"解放" match
    # hundreds of unrelated story switches and freeze the game when bulk-flipped.
    HSCENE_PATTERNS = ["回想", "思い出", "ぺろぺろ", "ｈシーン", "hシーン"].freeze
    HSCENE_HARD_CAP = 100  # if more matches than this, abort and report

    def find_hscene_switch_ids
      return [] unless $data_system && $data_system.switches
      ids = []
      $data_system.switches.each_with_index do |nm, idx|
        next if nm.nil? || nm.empty?
        if HSCENE_PATTERNS.any? { |p| nm.include?(p) }
          ids << idx
        end
      end
      ids.reject!(&:zero?)
      ids
    end

    def unlock_hscene_gallery
      ids = find_hscene_switch_ids
      if ids.size > HSCENE_HARD_CAP
        note("H-scene unlock ABORTED: #{ids.size} matches > cap #{HSCENE_HARD_CAP} (likely false positives). Use 'Force-set switches in range' instead.")
        return 0
      end
      if ids.empty?
        note("H-scene unlock: 0 matches in switch names. BS2 likely uses event-driven gallery -- try 'Force-set switches in range'.")
        return 0
      end
      queue_switches_on(ids)
      note("H-scene unlock: queued #{ids.size} switches.")
      ids.size
    end

    # ---- Cached, pre-filtered database arrays (computed once per game session)
    # These never change at runtime so it's safe to cache forever.
    def cached_items
      @cached_items ||= ($data_items || []).reject { |i|
        i.nil? || i.id == 0 || i.name.to_s.empty?
      }.select { |i| i.itype_id != 2 }
    end

    def cached_key_items
      @cached_key_items ||= ($data_items || []).reject { |i|
        i.nil? || i.id == 0 || i.name.to_s.empty?
      }.select { |i| i.itype_id == 2 }
    end

    def cached_weapons
      @cached_weapons ||= ($data_weapons || []).reject { |i|
        i.nil? || i.id == 0 || i.name.to_s.empty?
      }
    end

    def cached_armors
      @cached_armors ||= ($data_armors || []).reject { |i|
        i.nil? || i.id == 0 || i.name.to_s.empty?
      }
    end

    def cached_skills
      @cached_skills ||= ($data_skills || []).reject { |s|
        s.nil? || s.id == 0 || s.name.to_s.empty?
      }
    end

    def cached_addable_actors
      @cached_addable_actors ||= ($data_actors || []).reject { |da|
        da.nil? || da.id == 0 || da.name.to_s.strip.empty? ||
          (da.class_id rescue 0) == 0
      }
    end
  end
end

# =============================================================================
# VirtualScroll — mixin that turns a Window_Selectable into a virtual list.
# Only the visible viewport is drawn into the bitmap; scrolling redraws.
# Avoids RGSS3's bitmap size limit (~8192 px tall) on lists with 1000+ items
# (NPC teleport, item picker, skill list, etc.) which otherwise either fail
# silently to allocate or render only the first ~290 items.
# =============================================================================
module VirtualScroll
  def page_row_max
    h = (height - standard_padding * 2)
    [h / item_height, 1].max
  end

  def contents_height
    item_height * (page_row_max + 1)
  end

  def top_row
    @vs_top_row ||= 0
    @vs_top_row
  end

  def top_row=(row)
    row = 0 if row < 0
    last = [(item_max + col_max - 1) / col_max - page_row_max, 0].max
    row = last if row > last
    if @vs_top_row != row
      @vs_top_row = row
      refresh_visible
    end
  end

  def bottom_row;          top_row + page_row_max - 1                          end
  def bottom_row=(row);    self.top_row = row - (page_row_max - 1)             end

  def item_rect(index)
    rect = Rect.new
    rect.width  = item_width
    rect.height = item_height
    rect.x = index % col_max * (rect.width + spacing)
    rect.y = (index / col_max - top_row) * item_height       # relative to viewport
    rect
  end

  def update_cursor
    if @cursor_all
      cursor_rect.set(0, 0, contents.width, page_row_max * item_height)
    elsif @index < 0 || item_max == 0
      cursor_rect.empty
    else
      ensure_cursor_visible
      cursor_rect.set(item_rect(@index))
    end
  end

  def ensure_cursor_visible
    row = @index / col_max
    self.top_row    = row if row < top_row
    self.bottom_row = row if row > bottom_row
  end

  def refresh
    # If we're mixed into a Window_Command subclass, the command list still
    # needs to be rebuilt before we can draw it. respond_to? guards keep this
    # mixin working unchanged for plain Window_Selectable subclasses too.
    clear_command_list if respond_to?(:clear_command_list, true)
    make_command_list  if respond_to?(:make_command_list,  true)
    create_contents
    refresh_visible
  end

  def refresh_visible
    return unless contents
    contents.clear
    return if item_max == 0
    start = top_row * col_max
    last  = [start + (page_row_max + 1) * col_max - 1, item_max - 1].min
    (start..last).each { |i| draw_item(i) }
  end

  def draw_all_items
    refresh_visible
  end
end

# =============================================================================
# Window_AdminNumberInput — modal numeric input
# =============================================================================
class Window_AdminNumberInput < Window_Base
  def initialize
    super(0, 0, 520, fitting_height(4))
    self.x = (Graphics.width - width) / 2
    self.y = (Graphics.height - height) / 2
    self.z = 200
    self.openness = 0
    self.back_opacity = 255       # fully opaque background
    self.opacity      = 255       # fully opaque frame
    @value = 0; @min_val = 0; @max_val = 9_999_999
    @digits = 7; @cursor = 0; @prompt = ""
    @ok_block = nil; @cn_block = nil
  end

  def setup(prompt, opts = {})
    @prompt   = prompt.to_s
    @min_val  = opts[:min]    || 0
    @max_val  = opts[:max]    || 9_999_999
    @digits   = opts[:digits] || 7
    @value    = AdminMenu.clamp(opts[:initial].to_i, @min_val, @max_val)
    @cursor   = 0
    @ok_block = opts[:on_ok]
    @cn_block = opts[:on_cancel]
    refresh; open; self.active = true
  end

  def refresh
    contents.clear
    contents.font.size = 22
    contents.draw_text(0, 0, contents.width, line_height, @prompt, 1)
    digits_str = @value.to_s.rjust(@digits, "0")
    digit_w = 32
    base_x = (contents.width - @digits * digit_w) / 2
    y = line_height + 8
    @digits.times do |i|
      x = base_x + i * digit_w
      if i == @cursor
        contents.fill_rect(x - 2, y, digit_w, line_height, Color.new(255, 255, 100, 80))
      end
      contents.draw_text(x, y, digit_w, line_height, digits_str[i, 1], 1)
    end
    contents.font.size = 16
    contents.draw_text(0, line_height * 3, contents.width, line_height,
      "Up/Down: +-1   Left/Right: digit   PgUp/PgDn: x10/÷10   Enter: OK   Esc: cancel", 1)
    contents.font.size = 22
  end

  def update
    super
    return unless self.active && self.open?
    if Input.repeat?(:UP)
      adjust(+1)
    elsif Input.repeat?(:DOWN)
      adjust(-1)
    elsif Input.trigger?(:LEFT)
      Sound.play_cursor; @cursor = (@cursor - 1) % @digits; refresh
    elsif Input.trigger?(:RIGHT)
      Sound.play_cursor; @cursor = (@cursor + 1) % @digits; refresh
    elsif Input.trigger?(:L)
      Sound.play_cursor; @value = AdminMenu.clamp(@value * 10, @min_val, @max_val); refresh
    elsif Input.trigger?(:R)
      Sound.play_cursor; @value = AdminMenu.clamp(@value / 10, @min_val, @max_val); refresh
    elsif Input.trigger?(:C)
      Sound.play_ok
      val = @value; block = @ok_block
      finish; block.call(val) if block
    elsif Input.trigger?(:B)
      Sound.play_cancel
      block = @cn_block
      finish; block.call if block
    end
  end

  def adjust(direction)
    place = 10 ** (@digits - @cursor - 1)
    new_val = AdminMenu.clamp(@value + direction * place, @min_val, @max_val)
    if new_val != @value
      Sound.play_cursor; @value = new_val; refresh
    end
  end

  def finish; self.active = false; close; end
end

# =============================================================================
# Window_AdminHelp — top banner
# =============================================================================
class Window_AdminHelp < Window_Base
  def initialize
    super(0, 0, Graphics.width, fitting_height(2))
    refresh
  end

  def refresh
    contents.clear
    contents.font.size = 18
    line1 = "#{AdminMenu::TITLE} v#{AdminMenu::VERSION}    Arrows / Enter / Esc / F2 to close"
    flags = []
    flags << "GOD"      if AdminMenu.god_mode
    flags << "NoBattle" if AdminMenu.disable_battles
    flags << "Noclip"   if AdminMenu.noclip
    flags << "1Shot"    if AdminMenu.one_shot_mode
    flags << "Crit"     if AdminMenu.always_crit
    flags << "Run"      if AdminMenu.always_run
    flags << "InfSouls" if AdminMenu.infinite_souls
    flags << "Speed#{AdminMenu.speed_amount}" if AdminMenu.speed_boost
    line2 = "Active: " + (flags.empty? ? "(none)" : flags.join(" / "))
    contents.draw_text(0, line_height * 0, contents.width, line_height, line1)
    contents.draw_text(0, line_height * 1, contents.width, line_height, line2)
  end
end

# =============================================================================
# Window_AdminCmd — left category list
# =============================================================================
class Window_AdminCmd < Window_Command
  def initialize(x, y, height)
    @win_h = height
    super(x, y)
  end
  def window_width; 240 end
  def window_height; @win_h end
  def make_command_list
    AdminMenu.categories.each { |sym, name| add_command(name, sym) }
  end
end

# =============================================================================
# Window_AdminSub — right action list
# =============================================================================
class Window_AdminSub < Window_Command
  # NOTE: deliberately NOT mixing in VirtualScroll. The mixin's refresh
  # interferes with how Window_Command tracks @list state and was causing
  # the toggle-click freeze. Sub_window only ever holds short lists (8-50
  # entries), well within the standard renderer's bitmap limit, so we
  # don't need virtualization here.
  attr_reader :actions
  def initialize(x, y, width, height)
    @win_w = width; @win_h = height
    @actions = []
    super(x, y)
    deactivate
    unselect
  end
  def window_width; @win_w end
  def window_height; @win_h end
  def make_command_list
    @actions.each do |entry|
      label, payload = entry[0], entry[1]
      # nil payload = informational/header row -> disabled (buzzer on Enter)
      add_command(label, :admin_action, !payload.nil?)
    end
  end
  def set_actions(new_actions)
    new_actions ||= []
    begin
      @actions = new_actions
      unselect                       # clear cursor before refresh
      self.oy = 0                    # reset scroll for the new list
      refresh                        # standard Window_Command refresh path
      if @actions.any?
        i = @actions.index { |e| e && !e[1].nil? } || 0
        select(i)
      end
    rescue Exception => e
      AdminMenu.note("set_actions FAIL: #{e.class}: #{e.message}") rescue nil
      @actions = []
      begin
        unselect
        self.oy = 0
        refresh
      rescue
      end
    end
  end
  def current_action; @actions[index] end
end

# =============================================================================
# Window_AdminItemCategory — top of items pane
# =============================================================================
class Window_AdminItemCategory < Window_HorzCommand
  attr_accessor :on_change
  def initialize(x, y, width)
    @win_w = width
    super(x, y)
    @last_index = -1
  end
  def window_width; @win_w end
  def col_max; 4 end
  def make_command_list
    add_command("Items",     :items)
    add_command("Key Items", :key_items)
    add_command("Weapons",   :weapons)
    add_command("Armors",    :armors)
  end
  def update
    super
    if @last_index != index
      @last_index = index
      @on_change.call if @on_change
    end
  end
end

# =============================================================================
# Window_AdminItemList — selectable list with icons + count
# =============================================================================
class Window_AdminItemList < Window_Selectable
  include VirtualScroll
  def initialize(x, y, w, h)
    @data = []
    super(x, y, w, h)
    refresh
  end
  def col_max; 1 end
  def item_max; @data.size end
  def line_height; 28 end
  def current_item; @data[index] end

  def set_data(items)
    items ||= []
    @data = items
    @vs_top_row = 0
    refresh
    select(0) if @data.any?
  end

  def draw_item(idx)
    item = @data[idx]
    return unless item
    rect = item_rect_for_text(idx)
    draw_icon(item.icon_index, rect.x, rect.y - 2)
    contents.draw_text(rect.x + 28, rect.y, rect.width - 28 - 90, line_height, item.name.to_s)
    count = $game_party.item_number(item) rescue 0
    contents.draw_text(rect.x + rect.width - 90, rect.y, 88, line_height, "owned: #{count}", 2)
  end
end

# =============================================================================
# Window_AdminSkillList — selectable skills with icons + already-known marker
# =============================================================================
class Window_AdminSkillList < Window_Selectable
  include VirtualScroll
  attr_accessor :target_actor
  def initialize(x, y, w, h)
    @data = []
    @target_actor = nil
    super(x, y, w, h)
    refresh
  end
  def col_max; 1 end
  def item_max; @data.size end
  def line_height; 28 end
  def current_skill; @data[index] end

  def set_data(skills)
    skills ||= []
    @data = skills
    @vs_top_row = 0
    refresh
    select(0) if @data.any?
  end

  def draw_item(idx)
    sk = @data[idx]
    return unless sk
    rect = item_rect_for_text(idx)
    draw_icon(sk.icon_index, rect.x, rect.y - 2)
    contents.draw_text(rect.x + 28, rect.y, rect.width - 28 - 110, line_height, sk.name.to_s)
    if @target_actor && @target_actor.skills.include?(sk)
      change_color(text_color(3))   # yellow-green
      contents.draw_text(rect.x + rect.width - 110, rect.y, 108, line_height, "[learned]", 2)
      change_color(normal_color)
    end
  end
end

# =============================================================================
# Scene_AdminMenu
# =============================================================================
class Scene_AdminMenu < Scene_MenuBase
  def start
    super
    create_help_window
    create_command_window
    create_sub_window
    create_item_windows
    create_skill_windows
    create_number_window
    # Don't pre-populate any category — keep the right pane empty until the
    # user actually picks one. Eliminates the scene-open lag spike.
    show_sub_pane
    @command_window.activate
  end

  # ---------- Window setup ----------
  def create_help_window
    @help_window = Window_AdminHelp.new
  end

  def create_command_window
    y      = @help_window.height
    height = Graphics.height - y
    @command_window = Window_AdminCmd.new(0, y, height)
    AdminMenu.categories.each do |sym, _|
      @command_window.set_handler(sym, method(:"command_#{sym}"))
    end
    @command_window.set_handler(:cancel, method(:return_scene))
  end

  def create_sub_window
    x      = @command_window.width
    y      = @help_window.height
    width  = Graphics.width - x
    height = Graphics.height - y
    @sub_window = Window_AdminSub.new(x, y, width, height)
    @sub_window.set_handler(:admin_action, method(:on_sub_ok))
    @sub_window.set_handler(:cancel,       method(:on_sub_cancel))
  end

  def create_item_windows
    x = @command_window.width
    y = @help_window.height
    w = Graphics.width - x
    @item_cat_window = Window_AdminItemCategory.new(x, y, w)
    [:items, :key_items, :weapons, :armors].each do |s|
      @item_cat_window.set_handler(s, method(:on_item_cat))
    end
    @item_cat_window.set_handler(:cancel, method(:on_item_cat_cancel))
    @item_cat_window.on_change = method(:refresh_item_list_for_current_cat)

    list_y = y + @item_cat_window.height
    list_h = Graphics.height - list_y
    @item_list_window = Window_AdminItemList.new(x, list_y, w, list_h)
    @item_list_window.deactivate
    @item_cat_window.visible = false
    @item_list_window.visible = false
  end

  def create_skill_windows
    x = @command_window.width
    y = @help_window.height
    w = Graphics.width - x
    h = Graphics.height - y
    @skill_actor_window = Window_AdminSub.new(x, y, w, h)
    @skill_actor_window.set_handler(:admin_action, method(:on_skill_actor_pick))
    @skill_actor_window.set_handler(:cancel,       method(:on_skill_actor_cancel))
    @skill_actor_window.visible = false

    @skill_list_window = Window_AdminSkillList.new(x, y, w, h)
    @skill_list_window.set_handler(:ok,     method(:on_skill_pick))
    @skill_list_window.set_handler(:cancel, method(:on_skill_list_cancel))
    @skill_list_window.visible = false
  end

  def create_number_window
    @backdrop = Sprite.new
    @backdrop.bitmap = Bitmap.new(Graphics.width, Graphics.height)
    @backdrop.bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(0, 0, 0, 180))
    @backdrop.z = 199
    @backdrop.visible = false
    @number_window = Window_AdminNumberInput.new
  end

  def show_backdrop
    @backdrop.visible = true if @backdrop
  end

  def hide_backdrop
    @backdrop.visible = false if @backdrop
  end

  def terminate
    super
    if @backdrop
      @backdrop.bitmap.dispose if @backdrop.bitmap
      @backdrop.dispose
      @backdrop = nil
    end
  end

  # Explicit flag — DON'T rely on @number_window.openness or .active. The
  # window's openness comes back > 0 even before any prompt is opened (BS2's
  # Window machinery, probably), causing false positives that left sub_window
  # deactivated forever and made the menu look frozen.
  def modal_open?
    @modal_active == true
  end

  # ---------- Pane visibility ----------
  def hide_all_right_panes
    [@sub_window, @item_cat_window, @item_list_window,
     @skill_actor_window, @skill_list_window].each do |w|
      next unless w
      w.visible = false
      w.deactivate
    end
  end

  def show_sub_pane
    hide_all_right_panes
    @sub_window.visible = true
  end

  def show_item_pane
    hide_all_right_panes
    @item_cat_window.visible  = true
    @item_list_window.visible = true
    @item_cat_window.activate
    @item_cat_window.select(0)
    refresh_item_list_for_current_cat
  end

  def show_skill_actor_pane
    hide_all_right_panes
    @skill_actor_window.visible = true
    @skill_actor_window.set_actions(build_skill_actor_list)
    @skill_actor_window.activate
    @skill_actor_window.select(0)
  end

  def show_skill_list_pane(actor)
    hide_all_right_panes
    @skill_list_window.target_actor = actor
    @skill_list_window.set_data(AdminMenu.cached_skills)
    @skill_list_window.visible = true
    @skill_list_window.activate
    @skill_list_window.select(0)
  end

  # ---------- Category dispatch ----------
  def command_close;    return_scene end
  def command_player;   enter_sub(:player)   end
  def command_teleport; enter_sub(:teleport) end
  def command_toggles;  enter_sub(:toggles)  end
  def command_world;    enter_sub(:world)    end
  def command_items;    show_item_pane       end
  def command_skills;   show_skill_actor_pane end

  def enter_sub(cat)
    populate_for(cat)
    show_sub_pane
    @sub_window.activate
    @sub_window.select(0)
    @current_category = cat
  end

  def populate_for(cat)
    @current_category = cat
    @action_cache ||= {}
    actions = @action_cache[cat]
    unless actions
      actions =
        case cat
        when :player    then build_player_actions
        when :teleport  then build_teleport_actions
        when :toggles   then build_toggle_actions
        when :world     then build_world_actions
        else []
        end
      @action_cache[cat] = actions
    end
    @sub_window.set_actions(actions)
  end

  def invalidate_action_cache(cat = nil)
    @action_cache ||= {}
    cat ? @action_cache.delete(cat) : @action_cache.clear
  end

  # Restored: the synchronous version that worked for the ON click.
  # Runs inside process_ok's call chain while sub_window is already
  # deactivated by process_ok itself, which is the state BS2's window
  # machinery tolerates.
  def refresh_after_action
    invalidate_action_cache(@current_category)
    populate_for(@current_category) if @current_category
    @help_window.refresh if @help_window
  rescue Exception => e
    AdminMenu.note("refresh_after_action: #{e.class}: #{e.message}") rescue nil
  end

  def on_sub_ok
    entry = @sub_window.current_action
    begin
      if entry
        label, action = entry
        action.call if action.respond_to?(:call)
      end
    rescue Exception => e
      lbl = entry ? entry[0] : "?"
      AdminMenu.note("ERR(#{lbl}): #{e.class}: #{e.message}")
      (e.backtrace || []).first(4).each { |bt| AdminMenu.note("  #{bt}") }
    end
    @sub_window.activate unless modal_open?
  end

  def on_sub_cancel
    @sub_window.deactivate
    @sub_window.unselect
    @sub_window.set_actions([])         # leave the right pane empty
    @command_window.activate
  end

  # ---------- Item-pane callbacks ----------
  def on_item_cat
    refresh_item_list_for_current_cat
    @item_cat_window.deactivate
    @item_list_window.activate
    @item_list_window.select(0)
    @item_list_window.set_handler(:ok,     method(:on_item_pick))
    @item_list_window.set_handler(:cancel, method(:on_item_list_cancel))
  end

  def on_item_cat_cancel
    @item_cat_window.deactivate
    show_sub_pane
    @sub_window.set_actions([])
    @command_window.activate
  end

  def refresh_item_list_for_current_cat
    sym = @item_cat_window.current_symbol
    list =
      case sym
      when :items     then AdminMenu.cached_items
      when :key_items then AdminMenu.cached_key_items
      when :weapons   then AdminMenu.cached_weapons
      when :armors    then AdminMenu.cached_armors
      else []
      end
    @item_list_window.set_data(list)
  end

  def on_item_pick
    item = @item_list_window.current_item
    return unless item
    current = $game_party.item_number(item) rescue 0
    @item_list_window.deactivate
    show_backdrop
    @modal_active = true
    @number_window.setup(
      "Set quantity of: #{item.name}",
      :initial => current, :min => 0, :max => 99, :digits => 2,
      :on_ok     => proc { |val|
        @modal_active = false
        hide_backdrop
        diff = val - ($game_party.item_number(item) rescue 0)
        if diff > 0
          $game_party.gain_item(item, diff)
        elsif diff < 0
          $game_party.lose_item(item, -diff)
        end
        AdminMenu.note("#{item.name} -> x#{val}")
        refresh_item_list_for_current_cat
        @item_list_window.activate
      },
      :on_cancel => proc {
        @modal_active = false
        hide_backdrop
        @item_list_window.activate
      }
    )
  end

  def on_item_list_cancel
    @item_list_window.deactivate
    @item_list_window.unselect
    @item_cat_window.activate
  end

  # ---------- Skills-pane callbacks ----------
  def on_skill_actor_pick
    entry = @skill_actor_window.current_action
    return unless entry
    actor = entry[1]
    return unless actor.is_a?(Game_Actor)
    show_skill_list_pane(actor)
  end

  def on_skill_actor_cancel
    @skill_actor_window.deactivate
    show_sub_pane
    @sub_window.set_actions([])
    @command_window.activate
  end

  def on_skill_pick
    sk = @skill_list_window.current_skill
    actor = @skill_list_window.target_actor
    return unless sk && actor
    if actor.skills.include?(sk)
      actor.forget_skill(sk.id) rescue nil
      AdminMenu.note("#{actor.name} forgot #{sk.name}")
    else
      actor.learn_skill(sk.id) rescue nil
      AdminMenu.note("#{actor.name} learned #{sk.name}")
    end
    @skill_list_window.refresh
    @skill_list_window.activate
  end

  def on_skill_list_cancel
    @skill_list_window.deactivate
    @skill_list_window.unselect
    show_skill_actor_pane
  end

  def build_skill_actor_list
    list = []
    list << ["(pick an actor; Enter on a skill toggles learn/forget)", nil]
    $game_party.members.each do |actor|
      list << ["#{actor.name} (Lv #{actor.level}, #{actor.skills.size} skills)", actor]
    end
    list
  end

  # ---------- Number prompt helper ----------
  def prompt_number(prompt, return_to, opts = {}, &on_value)
    return_to.deactivate
    show_backdrop
    @modal_active = true
    @number_window.setup(prompt, opts.merge(
      :on_ok     => proc { |val|
        @modal_active = false
        hide_backdrop
        on_value.call(val) if on_value
        populate_for(@current_category) if return_to == @sub_window
        @help_window.refresh
        return_to.activate
      },
      :on_cancel => proc {
        @modal_active = false
        hide_backdrop
        return_to.activate
      },
    ))
  end

  # =====================================================================
  # Action builders
  # =====================================================================

  def build_player_actions
    list = []
    list << ["[party] Set Souls (now #{$game_party ? $game_party.gold : 0})", proc {
      prompt_number("Set Souls", @sub_window,
        :initial => ($game_party ? $game_party.gold : 0),
        :min => 0, :max => 99_999_999, :digits => 8) { |v|
        diff = v - $game_party.gold
        if diff > 0
          $game_party.gain_gold(diff)
        elsif diff < 0
          $game_party.lose_gold(-diff)
        end
        AdminMenu.note("Souls -> #{$game_party.gold}")
      }
    }]
    list << ["[party] +1,000,000 Souls", proc {
      $game_party.gain_gold(1_000_000)
      AdminMenu.note("Souls -> #{$game_party.gold}")
      refresh_after_action
    }]
    list << ["[party] Heal everyone", proc {
      $game_party.members.each(&:recover_all)
      AdminMenu.note("Party fully healed")
    }]
    list << ["[party] Cure status effects (everyone)", proc {
      $game_party.members.each { |m| m.clear_states rescue nil }
      AdminMenu.note("All status cured")
    }]
    $game_party.members.each do |actor|
      a = actor
      list << ["#{a.name}: set Level (now Lv #{a.level})", proc {
        prompt_number("Set level for #{a.name}", @sub_window,
          :initial => a.level, :min => 1, :max => 999, :digits => 3) { |v|
          target = AdminMenu.clamp(v, 1, [a.max_level, 999].max)
          begin
            a.change_level(target, false)
            AdminMenu.note("#{a.name} -> Lv #{a.level}")
          rescue Exception => e
            AdminMenu.note("level fail: #{e.message}")
          end
        }
      }]

      AdminMenu::PARAM_NAMES.each_with_index do |pname, pid|
        cur = (a.param(pid) rescue 0)
        list << ["#{a.name}: set #{pname} (now #{cur})", proc {
          prompt_number("Set #{pname} for #{a.name}", @sub_window,
            :initial => cur, :min => 0, :max => 9999, :digits => 4) { |v|
            begin
              now = a.param(pid)
              diff = v - now
              a.add_param(pid, diff)
              a.recover_all if pid <= 1
              AdminMenu.note("#{a.name}.#{pname} -> #{a.param(pid)}")
            rescue Exception => e
              AdminMenu.note("stat fail: #{e.message}")
            end
          }
        }]
      end

      list << ["#{a.name}: heal", proc { a.recover_all rescue nil; AdminMenu.note("Healed #{a.name}") }]
      list << ["#{a.name}: cure status effects", proc { a.clear_states rescue nil; AdminMenu.note("Cured #{a.name}") }]

      if $game_party.members.size > 1
        list << ["#{a.name}: REMOVE from party", proc {
          $game_party.remove_actor(a.id) rescue nil
          AdminMenu.note("Removed #{a.name}")
          refresh_after_action
        }]
      end
    end

    # Note: "Add actor to party" was removed — BS2's status display windows
    # (Window_KisekiStatus etc.) crash with FloatDomainError on actors that
    # aren't fully initialized for the current game state. The crash happens
    # AFTER add_actor returns (when BS2's UI tries to redraw), so begin/rescue
    # in the action proc can't save it.
    list
  end

  # ONE flat list — Maps section, then NPCs section, with disabled section
  # headers. No submode/back-button machinery (which was crashing in BS2's
  # customized Window_Command). Esc on the sub_window exits to the main menu.
  # Flat list of BS2's bonfire map locations only. NPC/character teleport
  # was removed (Japanese names couldn't be reliably translated).
  def build_teleport_actions
    list = []
    list << ["======  MAP LOCATIONS  (Esc to exit)  ======", nil]
    if defined?(KURE::ShortMove::MOVE_LIST)
      KURE::ShortMove::MOVE_LIST.each_with_index do |entry, i|
        next unless entry.is_a?(Array) && entry.size >= 2
        nm = entry[0].is_a?(Array) ? entry[0][0].to_s : entry[0].to_s
        target = entry[1]
        next unless target.is_a?(Array) && target.size >= 4
        map_id, x, y, dir = target
        list << ["[#{i}] #{nm}", proc {
          begin
            $game_player.reserve_transfer(map_id, x, y, dir)
            SceneManager.return
            AdminMenu.note("-> #{nm}")
          rescue Exception => e
            AdminMenu.note("Teleport fail: #{e.class}: #{e.message}")
          end
        }]
      end
    end
    list
  end

  def build_toggle_actions
    # Toggle procs flip the flag + log + trigger refresh_after_action so the
    # [ON]/[off] marker updates live. Now safe because the modal_open? check
    # is fixed (was previously a false positive that left sub_window dead).
    [
      ["God Mode               [#{AdminMenu.god_mode        ? 'ON ' : 'off'}]", proc { AdminMenu.god_mode        = !AdminMenu.god_mode;        AdminMenu.note("God: #{AdminMenu.god_mode}");                refresh_after_action }],
      ["Disable Battles        [#{AdminMenu.disable_battles ? 'ON ' : 'off'}]", proc { AdminMenu.disable_battles = !AdminMenu.disable_battles; AdminMenu.note("DisableBattles: #{AdminMenu.disable_battles}"); refresh_after_action }],
      ["Noclip (walk thru)     [#{AdminMenu.noclip          ? 'ON ' : 'off'}]", proc {
        AdminMenu.noclip = !AdminMenu.noclip
        $game_player.instance_variable_set(:@through, AdminMenu.noclip) if $game_player
        AdminMenu.note("Noclip: #{AdminMenu.noclip}")
        refresh_after_action
      }],
      ["One-Shot Mode          [#{AdminMenu.one_shot_mode   ? 'ON ' : 'off'}]", proc { AdminMenu.one_shot_mode   = !AdminMenu.one_shot_mode;   AdminMenu.note("OneShot: #{AdminMenu.one_shot_mode}");      refresh_after_action }],
      ["Always Crit            [#{AdminMenu.always_crit     ? 'ON ' : 'off'}]", proc { AdminMenu.always_crit     = !AdminMenu.always_crit;     AdminMenu.note("AlwaysCrit: #{AdminMenu.always_crit}");     refresh_after_action }],
      ["Always Run             [#{AdminMenu.always_run      ? 'ON ' : 'off'}]", proc { AdminMenu.always_run      = !AdminMenu.always_run;      AdminMenu.note("AlwaysRun: #{AdminMenu.always_run}");       refresh_after_action }],
      ["Infinite Souls         [#{AdminMenu.infinite_souls  ? 'ON ' : 'off'}]", proc { AdminMenu.infinite_souls  = !AdminMenu.infinite_souls;  AdminMenu.note("InfSouls: #{AdminMenu.infinite_souls}");    refresh_after_action }],
      ["Speed Boost amount (now +#{AdminMenu.speed_amount})", proc {
        prompt_number("Speed boost (0..6)", @sub_window,
          :initial => AdminMenu.speed_amount, :min => 0, :max => 6, :digits => 1) { |v|
          AdminMenu.speed_amount = v
          AdminMenu.note("Speed boost = +#{v}")
        }
      }],
    ]
  end

  def build_world_actions
    list = []
    list << ["Teleport to Reminiscence Room (回想部屋)", proc {
      begin
        target_id = nil
        ($data_mapinfos || {}).each do |mid, info|
          next unless info && info.name
          n = info.name
          if n.include?("回想部屋") || n.include?("回想") ||
             n.downcase.include?("reminisc") || n.downcase.include?("recall")
            target_id = mid
            break
          end
        end
        if target_id
          $game_player.reserve_transfer(target_id, 10, 10, 2)
          SceneManager.return
          AdminMenu.note("-> Reminiscence Room (Map #{target_id}). If stuck, enable Noclip.")
        else
          AdminMenu.note("Reminiscence Room not found in $data_mapinfos")
        end
      rescue Exception => e
        AdminMenu.note("Teleport fail: #{e.class}: #{e.message}")
      end
    }]
    list << ["Open BS2 bonfire travel", proc {
      if defined?(Scene_ShortMove)
        SceneManager.call(Scene_ShortMove)
      else
        AdminMenu.note("Scene_ShortMove not defined")
      end
    }]
    list
  end

  # Scene_Base#update_basic already calls .update on every Window-typed ivar
  # (including @number_window via update_all_windows), so we don't override it.
end

# =============================================================================
# Hooks
# =============================================================================

# F2 hotkey on Scene_Map opens admin menu
begin
  class Scene_Map
    alias_method :_admin_orig_update, :update
    def update
      _admin_orig_update
      AdminMenu.update_global_keys
      AdminMenu.per_frame_tick
      if AdminMenu.key_pressed?(AdminMenu::VK[:f2])
        SceneManager.call(Scene_AdminMenu)
      end
    end
  end
rescue => e
  ModLoader.log("[admin] Scene_Map.update hook failed: #{e.message}") rescue nil
end

# Disable battles — two-layer hook.
#
# Layer 1: Game_Interpreter#command_301 (Battle Processing in events). Vanilla
# does BattleManager.setup -> SceneManager.call(Scene_Battle) -> Fiber.yield.
# Just blocking SceneManager.call leaves the Fiber yielding forever, freezing
# the game. So we short-circuit command_301 entirely and mark the branch
# result as "victory" (0) so subsequent event conditional branches still work.
begin
  class Game_Interpreter
    if method_defined?(:command_301) || private_method_defined?(:command_301)
      alias_method :_admin_orig_command_301, :command_301
      def command_301
        if AdminMenu.disable_battles
          @branch ||= {}
          @branch[@indent] = 0          # win-branch result, no Fiber.yield
          return
        end
        _admin_orig_command_301
      end
    end
  end
rescue => e
  ModLoader.log("[admin] command_301 hook failed: #{e.message}") rescue nil
end

# Layer 2: SceneManager.call -- catches code that triggers a battle directly
# (script calls, custom symbol-enemy logic) bypassing the event interpreter.
begin
  class << SceneManager
    alias_method :_admin_orig_call, :call
    def call(scene_class)
      if AdminMenu.disable_battles && scene_class == Scene_Battle
        ModLoader.log("[admin] Scene_Battle blocked") rescue nil
        return
      end
      _admin_orig_call(scene_class)
    end
  end
rescue => e
  ModLoader.log("[admin] SceneManager.call hook failed: #{e.message}") rescue nil
end

# God / one-shot
begin
  class Game_Battler
    alias_method :_admin_orig_execute_damage, :execute_damage
    def execute_damage(user)
      _admin_orig_execute_damage(user)
      if AdminMenu.god_mode && (respond_to?(:actor?) ? actor? : false)
        @hp = mhp; @mp = mmp
      end
      if AdminMenu.one_shot_mode && user && user.respond_to?(:actor?) && user.actor? &&
         self.respond_to?(:enemy?) && self.enemy?
        @hp = 0
      end
    end
  end
rescue => e
  ModLoader.log("[admin] execute_damage hook failed: #{e.message}") rescue nil
end

# Always crit
begin
  class Game_Action
    if method_defined?(:item_cri)
      alias_method :_admin_orig_item_cri, :item_cri
      def item_cri(target)
        return 1.0 if AdminMenu.always_crit && subject && (subject.actor? rescue false)
        _admin_orig_item_cri(target)
      end
    end
  end
rescue => e
  ModLoader.log("[admin] item_cri hook failed: #{e.message}") rescue nil
end

# Noclip is now driven directly via $game_player.through in the toggle proc
# itself -- no alias_method on passable? (which conflicted with BS2's own
# region-passing / symbol-enemy passable? overrides and was triggering the
# toggle freeze). Nothing to install here.

# Always run
begin
  class Game_Player
    if method_defined?(:dash?)
      alias_method :_admin_orig_dash, :dash?
      def dash?
        return true if AdminMenu.always_run
        _admin_orig_dash
      end
    end
  end
rescue => e
  ModLoader.log("[admin] dash? hook failed: #{e.message}") rescue nil
end

# Speed boost
begin
  class Game_CharacterBase
    alias_method :_admin_orig_real_move_speed, :real_move_speed
    def real_move_speed
      base = _admin_orig_real_move_speed
      if AdminMenu.speed_boost && self.is_a?(Game_Player)
        base + AdminMenu.speed_amount.to_i
      else
        base
      end
    end
  end
rescue => e
  ModLoader.log("[admin] real_move_speed hook failed: #{e.message}") rescue nil
end

ModLoader.log("[creative_mode] v#{AdminMenu::VERSION} ready - press F2 on the map") rescue nil
