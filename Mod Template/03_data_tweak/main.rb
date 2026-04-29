# =============================================================================
# Template: data table tweak
# -----------------------------------------------------------------------------
# Modify the database arrays at runtime: items, weapons, armors, skills,
# enemies, classes, states, actors. The change applies for the rest of the
# session and goes away when the game closes (clean -- no save corruption).
#
# Useful $data_* arrays (all 1-indexed, position 0 is nil):
#   $data_items     - RPG::Item        (consumables, key items)
#   $data_weapons   - RPG::Weapon
#   $data_armors    - RPG::Armor
#   $data_skills    - RPG::Skill
#   $data_enemies   - RPG::Enemy
#   $data_classes   - RPG::Class
#   $data_states    - RPG::State
#   $data_actors    - RPG::Actor
#   $data_troops    - RPG::Troop
#
# Each entry has fields like .name, .description, .icon_index, .price, etc.
#
# What this template does: makes every consumable item heal full HP and cost 1g.
# =============================================================================

if $data_items
  ($data_items || []).each do |item|
    next unless item && item.id != 0
    next unless item.itype_id == 1   # 1 = Regular item, 2 = Key item
    item.price = 1
    # Replace effects with "Recover All HP"
    # Effect codes (RPG::UsableItem::Effect):
    #   11 = HP recover, 12 = MP recover, 13 = TP gain
    # value1 is a fraction (0..1.0), value2 is a flat amount
    item.effects = [RPG::UsableItem::Effect.new(11, 0, 1.0, 0)]
  end
  ModLoader.log("[03_data_tweak] juiced #{($data_items || []).count { |i| i && i.itype_id == 1 }} consumables") rescue nil
end
