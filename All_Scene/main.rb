# =============================================================================
# All H-Scene v1.2 - Display every scene as unlocked in the Reminiscence Room
#
# How it works:
#   At first read, we load every Reminiscence-Room map (any map whose name
#   contains "回想") from disk and walk every event's page conditions to
#   harvest the EXACT switch IDs the gallery uses for gating. We then
#   monkey-patch Game_Switches#[] so reads of those switches return true.
#
#   We never WRITE switches. The underlying state stays at whatever the
#   game has it -> no false->true transition -> no autorun cascade -> no
#   crash. The Reminiscence Room's events read $game_switches[id] when
#   evaluating which event page to display, see "true" for our IDs, and
#   pick page 1 (visible character + dialog).
#
# v1.2 changelog:
#   - Replaced name-pattern matching ("回想", etc.) with direct map-data
#     parsing. BS2's gallery switches are named "<character>:<scene_type>"
#     (e.g. "公爵夫人：奉仕"), no "回想" substring -> patterns missed them.
#     Harvesting from the actual map data is exact.
#
# Author: dazashu
# =============================================================================

module AllHScene
  VERSION = "1.2.0".freeze

  # ---- Reminiscence map ID lookup -------------------------------------------
  # Cached only after we've successfully read $data_mapinfos.
  def self.reminiscence_map_ids
    return @rem_map_ids if @rem_map_ids
    return {} unless $data_mapinfos
    ids = {}
    $data_mapinfos.each do |mid, info|
      next unless info && info.name
      ids[mid] = true if info.name.include?("回想")
    end
    @rem_map_ids = ids
    ModLoader.log("[All_H_Scene] reminiscence map IDs: #{ids.keys.inspect}") rescue nil
    ids
  end

  # ---- Harvest switch IDs straight from map data ----------------------------
  # Walks every event's page conditions on every Reminiscence map and
  # collects the switch1_id / switch2_id whenever switch_valid is true.
  # That gives us the exact list the gallery uses (e.g. #722 ノーデ：奉仕,
  # #741 公爵夫人：奉仕, etc.).
  def self.harvest_switch_ids
    return @harvested if @harvested
    rem = reminiscence_map_ids
    return {} if rem.empty?
    ids = {}
    rem.each_key do |map_id|
      data = nil
      begin
        data = load_data(sprintf("Data/Map%03d.rvdata2", map_id))
      rescue => e
        ModLoader.log("[All_H_Scene] couldn't load Map#{map_id}: #{e.message}") rescue nil
      end
      next unless data && data.events
      data.events.each_value do |ev|
        next unless ev && ev.pages
        ev.pages.each do |page|
          next unless page && page.condition
          c = page.condition
          if c.switch1_valid && c.switch1_id && c.switch1_id > 0
            ids[c.switch1_id] = true
          end
          if c.switch2_valid && c.switch2_id && c.switch2_id > 0
            ids[c.switch2_id] = true
          end
        end
      end
    end
    @harvested = ids
    ModLoader.log("[All_H_Scene] harvested #{ids.size} gallery switch IDs from #{rem.size} reminiscence map(s)") rescue nil
    ids
  end

  def self.gallery_switch?(id)
    return false unless id
    harvest_switch_ids[id] == true
  end

  # ---- Diagnostic: dump the current map -------------------------------------
  def self.mod_dir
    @mod_dir ||= File.expand_path("..", __FILE__)
  end

  def self.dump_path
    File.join(mod_dir, "last_map_dump.txt")
  end

  def self.dump_current_map
    return unless $game_map
    map_id = $game_map.map_id
    name = ($data_mapinfos && $data_mapinfos[map_id] && $data_mapinfos[map_id].name) || "?"

    File.open(dump_path, "w") do |f|
      f.puts "=== All_H_Scene map dump (v#{VERSION}) ==="
      f.puts "Map ID:                       #{map_id}"
      f.puts "Map name:                     #{name}"
      f.puts "Reminiscence map IDs:         #{reminiscence_map_ids.keys.inspect}"
      f.puts "Harvested switch count:       #{harvest_switch_ids.size}"
      f.puts "Harvested switch IDs (first 80): #{harvest_switch_ids.keys.first(80).inspect}"
      f.puts ""
      f.puts "=== Events (#{$game_map.events.size}) ==="
      $game_map.events.each do |eid, ge|
        next unless ge
        ev = ge.instance_variable_get(:@event)
        next unless ev && ev.pages
        active = ge.instance_variable_get(:@page)
        ev.pages.each_with_index do |pg, pidx|
          next unless pg
          c = pg.condition
          bits = []
          if c
            bits << "sw1=##{c.switch1_id}" if c.switch1_valid
            bits << "sw2=##{c.switch2_id}" if c.switch2_valid
            bits << "var##{c.variable_id}>=#{c.variable_value}" if c.variable_valid
            bits << "self_sw=#{c.self_switch_ch}" if c.self_switch_valid
            bits << "item=##{c.item_id}" if c.item_valid
            bits << "actor=##{c.actor_id}" if c.actor_valid
          end
          act = (pg == active) ? " <-- ACTIVE" : ""
          f.puts "  [#{eid}] #{ev.name.inspect} page#{pidx}: #{bits.empty? ? '(none)' : bits.join(', ')}#{act}"
        end
      end
    end
    ModLoader.log("[All_H_Scene] dumped #{dump_path}") rescue nil
  rescue => e
    ModLoader.log("[All_H_Scene] dump error: #{e.class}: #{e.message}") rescue nil
  end

  def self.in_reminiscence_map?(map_id)
    reminiscence_map_ids[map_id] == true
  end
end

# =============================================================================
# Hook 1: gallery switches always READ as true
# =============================================================================
class Game_Switches
  unless method_defined?(:_ahs_orig_get)
    alias_method :_ahs_orig_get, :[]
    def [](switch_id)
      return true if AllHScene.gallery_switch?(switch_id)
      _ahs_orig_get(switch_id)
    end
  end
end

# =============================================================================
# Hook 2: refresh map events on transfer so they pick up our override
#          + dump diagnostic when entering a Reminiscence map
# =============================================================================
class Scene_Map
  unless method_defined?(:_ahs_orig_post_transfer)
    alias_method :_ahs_orig_post_transfer, :post_transfer
    def post_transfer
      _ahs_orig_post_transfer
      begin
        if $game_map && AllHScene.in_reminiscence_map?($game_map.map_id)
          # Pre-warm caches now that $data_mapinfos is definitely loaded.
          AllHScene.harvest_switch_ids
          # Force every event to re-evaluate its active page using our hook.
          $game_map.refresh
          # Diagnostic dump (overwrites Mods/All_H_Scene/last_map_dump.txt).
          AllHScene.dump_current_map
        end
      rescue => e
        ModLoader.log("[All_H_Scene] post_transfer hook error: #{e.message}") rescue nil
      end
    end
  end
end

ModLoader.log("[All_H_Scene] loaded v#{AllHScene::VERSION}") rescue nil
