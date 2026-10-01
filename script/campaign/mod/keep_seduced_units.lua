local seducer_force_cqi = 0
local is_seducer_human = false
local seduced_units = {}
local seduced_units_health_ratio_post_battle = {}
local active_battle_with_seduction = false -- neccessary variable for skipping UnitCreated events happening right after settlement capture but not related to seduction

function keep_seduced_units()
  set_log_level("ERROR")

  local function reset_seduce_state_variables()
    seducer_force_cqi = 0
    is_seducer_human = false
    seduced_units = {}
    seduced_units_health_ratio_post_battle = {}
    active_battle_with_seduction = false
    log("Seducing state variables cleared", "DEBUG")
  end

  local function custom_grant_unit_to_character(character, unit_key)
    local payload = cm:create_payload();
    payload:add_unit(character:military_force(), unit_key, 1, 0);
    cm:apply_payload(payload, character:faction());
  end

  local function get_force_cqi_in_battle_from_faction_name(faction_name)
    local pending_battle = cm:model():pending_battle()
    local attacker = pending_battle:attacker()
    local defender = pending_battle:defender()

    if not attacker:is_null_interface() and attacker:faction():name() == faction_name then
      return attacker:military_force():command_queue_index()
    end

    if not defender:is_null_interface() and defender:faction():name() == faction_name then
      return defender:military_force():command_queue_index()
    end

    log("ERROR: Cannot get force CQI in battle for faction " .. faction_name, "ERROR")
    return 0
  end

  local function compute_post_battle_unit_statuses()
  seduced_units_health_ratio_post_battle = {}

  for i = 1, #seduced_units do
    seduced_units_health_ratio_post_battle[i] = 1
  end

  return true
end

  local function check_post_battle_seduced_units()
    compute_post_battle_unit_statuses()
    local pending_battle = cm:model():pending_battle()

    local attacker_force_cqi = nil
    if not pending_battle:attacker():is_null_interface() then
      attacker_force_cqi = pending_battle:attacker():military_force():command_queue_index()
    end
    local defender_force_cqi = nil
    if not pending_battle:defender():is_null_interface() then
      defender_force_cqi = pending_battle:defender():military_force():command_queue_index()
    end

    local seducer_character = nil
    local victim_character = nil
    if pending_battle:attacker_won() and attacker_force_cqi == seducer_force_cqi then
      seducer_character = pending_battle:attacker()
      victim_character = pending_battle:defender()
    elseif pending_battle:defender_won() and defender_force_cqi == seducer_force_cqi then
      seducer_character = pending_battle:defender()
      victim_character = pending_battle:attacker()
    end

    if seducer_character then
      clone_seduced_units = table.clone(seduced_units)
      clone_seduced_units_health_ratio = table.clone(seduced_units_health_ratio_post_battle)
      for index, seduced_unit in ipairs(clone_seduced_units) do
        if clone_seduced_units_health_ratio[index] > 0 then
          log("Grant unit: " .. seduced_unit["key"] .. " to seducer force: " .. tostring(seducer_character), "DEBUG")
          custom_grant_unit_to_character(seducer_character, seduced_unit["key"])
          if victim_character and not victim_character:is_null_interface() then
            cm:remove_unit_from_character(cm:char_lookup_str(victim_character), seduced_unit["key"])
          end
        end
      end
    end

    core:get_tm():real_callback(reset_seduce_state_variables, 10)
  end

  core:add_listener(
    "KeepSeducedUnits_UnitSeduced",
    "FactionBribesUnit",
    function (context)
      attacker = cm:model():pending_battle():attacker()
      if not attacker then
        return false
      end
      defender = cm:model():pending_battle():defender()
      if not defender then
        return false
      end
      return attacker:faction():is_human() or defender:faction():is_human()
    end,
    function(context)
      table.insert(seduced_units, {key = context:ancillary():unit_key(), exp = context:ancillary():experience_level()})
      -- TODO: handle case where both factions are seducing
      is_seducer_human = context:faction():is_human()
      seducer_force_cqi = get_force_cqi_in_battle_from_faction_name(context:faction():name())
      active_battle_with_seduction = true
      log("New unit seduced: " .. context:ancillary():unit_key() .. " - " .. context:ancillary():faction():name(), "DEBUG")
      log("Seducer Force CQI: " .. tostring(seducer_force_cqi), "DEBUG")
    end,
    true
  )

  core:add_listener(
    "KeepSeducedUnits_BattleEnd",
    "PanelOpenedCampaign",
    function (context)
      return active_battle_with_seduction and context.string == "popup_battle_results"
    end,
    function(context)
      core:get_tm():callback(check_post_battle_seduced_units, 1)
    end,
    true
  )

  core:add_listener(
    "KeepSeducedUnits_BackToCampaignAfterBattle",
    "ScriptEventBattleSequenceCompleted",
    function(context)
      return active_battle_with_seduction
    end,
    function (context)
      log("Clear state variables from ScriptEventBattleSequenceCompleted", "DEBUG")
      reset_seduce_state_variables()
    end,
    true
  )

  core:add_listener(
    "KeepSeducedUnits_SeducedUnitAddedToForce",
    "UnitCreated",
    function (context)
      return active_battle_with_seduction
    end,
    function (context)
      local unit_added_to_force = context:unit()
      local seduced_unit_index = table.find_index_with_key(seduced_units, unit_added_to_force:unit_key(), "key")
      if seduced_unit_index == -1 then
        log("ERROR: Unit addded to force cannot be found in list of seduced units", "ERROR")
        return
      end
      cm:set_unit_hp_to_unary_of_maximum(unit_added_to_force, seduced_units_health_ratio_post_battle[seduced_unit_index])
      -- TODO: also take into consideration xp earned during this battle (take from UI?)
      cm:add_experience_to_unit(unit_added_to_force, seduced_units[seduced_unit_index]["exp"])
      table.remove(seduced_units, seduced_unit_index)
      table.remove(seduced_units_health_ratio_post_battle, seduced_unit_index)
    end,
    true
  )
end

cm:add_saving_game_callback(
  function(context)
      cm:save_named_value("ksu_seducer_force_cqi", seducer_force_cqi, context)
      cm:save_named_value("ksu_is_seducer_human", is_seducer_human, context)
      cm:save_named_value("ksu_seduced_units", seduced_units, context)
      cm:save_named_value("ksu_seduced_units_health_ratio_post_battle", seduced_units_health_ratio_post_battle, context)
      cm:save_named_value("ksu_active_battle_with_seduction", active_battle_with_seduction, context)
  end
)

cm:add_loading_game_callback(
  function(context)
      seducer_force_cqi = cm:load_named_value("ksu_seducer_force_cqi", seducer_force_cqi, context)
      is_seducer_human = cm:load_named_value("ksu_is_seducer_human", is_seducer_human, context)
      seduced_units = cm:load_named_value("ksu_seduced_units", seduced_units, context)
      seduced_units_health_ratio_post_battle = cm:load_named_value("ksu_seduced_units_health_ratio_post_battle", seduced_units_health_ratio_post_battle, context)
      active_battle_with_seduction = cm:load_named_value("ksu_active_battle_with_seduction", active_battle_with_seduction, context)
  end
)
