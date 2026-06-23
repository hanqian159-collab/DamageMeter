local DM = {
    visible = false,
    panel = nil,
    text = nil,
    tooltipPanel = nil,
    tooltipText = nil,
    canvas = nil,
    stats = {},
    statusById = {},
    buffOwners = {},
    buffObjectOwners = {},
    buffStacks = {},
    scriptContextStack = {},
    linkToStat = {},
    detailRows = {},
    detailBounds = {},
    textNameCache = nil,
    textKindCache = nil,
    modDir = nil,
    lastHitSnapshot = nil,
    damageSnapshotStack = {},
    changeHpSnapshot = nil,
    addBuffSnapshot = nil,
    statusAddBuffSnapshot = nil,
    changeHpHitTargets = {},
    roundIndex = 1,
    fightIndex = 0,
    fightSignature = nil,
    fightEnemySet = {},
    justResetFight = false,
    hoverStatId = nil,
    friendSlots = {},
    nextFriendSlot = 1,
    rowBarParent = nil,
    rowBars = {},
    rowBarData = {},
    lastUiFrame = -1,
    lastKeyFrame = -1,
    lastClickFrame = -1,
    lastRoundResetFrame = -1,
    roundStartHandled = false,
    hotkeyName = "F8",
    detailPopupPanel = nil,
    detailPopupText = nil,
    detailPopupStatId = nil,
    detailPopupDragging = false,
    detailPopupDragOffset = nil,
    lastExecutor = nil,
}

_G.DamageMeter = DM

local function current_frame()
    local frame = -1
    pcall(function() frame = CS.UnityEngine.Time.frameCount end)
    return frame
end

local function normalize_hotkey_name(name)
    name = tostring(name or "F8")
    name = string.gsub(name, "%s+", "")
    name = string.gsub(name, "%-", "")
    name = string.gsub(name, "_", "")
    if name == "" then return "F8" end
    return string.upper(name)
end

local function hotkey_input_property(name)
    local key = normalize_hotkey_name(name)
    local lower = string.lower(key)
    if string.match(lower, "^f%d+$") then return lower .. "Key" end
    if string.match(lower, "^[a-z]$") then return lower .. "Key" end
    if string.match(lower, "^%d$") then return "digit" .. lower .. "Key" end
    local aliases = {
        SPACE = "spaceKey",
        TAB = "tabKey",
        ENTER = "enterKey",
        ESC = "escapeKey",
        ESCAPE = "escapeKey",
        BACKQUOTE = "backquoteKey",
        MINUS = "minusKey",
        EQUALS = "equalsKey",
        LEFTBRACKET = "leftBracketKey",
        RIGHTBRACKET = "rightBracketKey",
        SEMICOLON = "semicolonKey",
        QUOTE = "quoteKey",
        COMMA = "commaKey",
        PERIOD = "periodKey",
        SLASH = "slashKey",
        BACKSLASH = "backslashKey"
    }
    return aliases[key]
end

local function hotkey_keycode_name(name)
    local key = normalize_hotkey_name(name)
    if string.match(key, "^F%d+$") then return key end
    if string.match(key, "^[A-Z]$") then return key end
    if string.match(key, "^%d$") then return "Alpha" .. key end
    local aliases = {
        SPACE = "Space",
        TAB = "Tab",
        ENTER = "Return",
        ESC = "Escape",
        ESCAPE = "Escape",
        BACKQUOTE = "BackQuote",
        MINUS = "Minus",
        EQUALS = "Equals",
        LEFTBRACKET = "LeftBracket",
        RIGHTBRACKET = "RightBracket",
        SEMICOLON = "Semicolon",
        QUOTE = "Quote",
        COMMA = "Comma",
        PERIOD = "Period",
        SLASH = "Slash",
        BACKSLASH = "Backslash"
    }
    return aliases[key]
end

local function key_was_pressed(name)
    local pressed = false
    local prop = hotkey_input_property(name)
    if prop ~= nil then
        pcall(function()
            local keyboard = CS.UnityEngine.InputSystem.Keyboard.current
            local key = keyboard ~= nil and keyboard[prop] or nil
            if key ~= nil then pressed = key.wasPressedThisFrame end
        end)
    end
    if pressed then return true end
    local keyCodeName = hotkey_keycode_name(name)
    if keyCodeName ~= nil then
        pcall(function()
            local code = CS.UnityEngine.KeyCode[keyCodeName]
            if code ~= nil then pressed = CS.UnityEngine.Input.GetKeyDown(code) end
        end)
    end
    if pressed then return true end
    if prop == nil and keyCodeName == nil then
        pcall(function() pressed = CS.UnityEngine.Input.GetKeyDown(CS.UnityEngine.KeyCode.F8) end)
    end
    return pressed
end

local function mouse_position()
    local mousePos = nil
    local ok = pcall(function()
        local mouse = CS.UnityEngine.InputSystem.Mouse.current
        if mouse ~= nil then mousePos = mouse.position:ReadValue() end
    end)
    if not ok or mousePos == nil then
        pcall(function() mousePos = CS.UnityEngine.Input.mousePosition end)
    end
    return mousePos
end

local function mouse_pressed(index)
    index = tonumber(index) or 0
    local pressed = false
    pcall(function()
        local mouse = CS.UnityEngine.InputSystem.Mouse.current
        local button = nil
        if mouse ~= nil and index == 0 then button = mouse.leftButton end
        if mouse ~= nil and index == 1 then button = mouse.rightButton end
        if button ~= nil then pressed = button.wasPressedThisFrame end
    end)
    if pressed then return true end
    pcall(function() pressed = CS.UnityEngine.Input.GetMouseButtonDown(index) end)
    return pressed
end

local function mouse_down(index)
    index = tonumber(index) or 0
    local down = false
    pcall(function()
        local mouse = CS.UnityEngine.InputSystem.Mouse.current
        local button = nil
        if mouse ~= nil and index == 0 then button = mouse.leftButton end
        if mouse ~= nil and index == 1 then button = mouse.rightButton end
        if button ~= nil then down = button.isPressed end
    end)
    if down then return true end
    pcall(function() down = CS.UnityEngine.Input.GetMouseButton(index) end)
    return down
end

local function load_hotkey_config()
    local key = nil
    pcall(function()
        local modsPath = CS.Globals.ModsPath
        local dir = DM.modDir
        if dir == nil or tostring(dir) == "" or not CS.System.IO.Directory.Exists(tostring(dir)) then
            if modsPath ~= nil and tostring(modsPath) ~= "" then
                dir = CS.System.IO.Path.Combine(tostring(modsPath), "DamageMeter")
            end
        end
        if dir == nil or tostring(dir) == "" then return end
        local path = CS.System.IO.Path.Combine(tostring(dir), "ModConfig.json")
        if not CS.System.IO.File.Exists(path) then return end
        local json = tostring(CS.System.IO.File.ReadAllText(path, CS.System.Text.Encoding.UTF8))
        key = string.match(json, '"Hotkey"%s*:%s*"([^"]+)"')
    end)
    DM.hotkeyName = normalize_hotkey_name(key or DM.hotkeyName or "F8")
end
local function log(msg)
    pcall(function()
        CS.UnityEngine.Debug.Log("[DamageMeter] " .. tostring(msg))
    end)
end

local function safe_prop(obj, prop)
    if obj == nil then return nil end
    local ok, value = pcall(function() return obj[prop] end)
    if ok then return value end
    ok, value = pcall(function() return obj:get_Item(prop) end)
    if ok then return value end
    return nil
end

local function dict_get(dict, key)
    if dict == nil then return nil end
    local ok, value = pcall(function() return dict:get_Item(key) end)
    if ok then return value end
    ok, value = pcall(function() return dict[key] end)
    if ok then return value end
    return nil
end

local function foreach_collection(collection, fn)
    if collection == nil then return end
    local count = nil
    pcall(function() count = collection.Count end)
    if count ~= nil then
        for i = 0, count - 1 do
            local item = nil
            local ok = pcall(function() item = collection:get_Item(i) end)
            if not ok then pcall(function() item = collection[i] end) end
            if item ~= nil then fn(item) end
        end
        return
    end
    local len = nil
    pcall(function() len = collection.Length end)
    if len ~= nil then
        for i = 0, len - 1 do
            local item = nil
            pcall(function() item = collection[i] end)
            if item ~= nil then fn(item) end
        end
    end
end

local function status_id(status)
    local id = safe_prop(status, "InstanceId") or safe_prop(status, "Id")
    if id == nil then return nil end
    id = tostring(id)
    if id == "" then return nil end
    return id
end

local function is_enemy_id(id)
    id = tostring(id or "")
    return string.sub(id, 1, 1) == "e"
end

local function placeholder_status_name(name, fallbackId)
    local text = tostring(name or "")
    local fallback = tostring(fallbackId or "")
    if text == "" or text == "Unknown" or text == "unknown" then return true end
    if fallback ~= "" and text == fallback then return true end
    if string.match(text, "^e%d+$") ~= nil then return true end
    if string.match(text, "^%d+$") ~= nil and string.len(text) >= 4 then return true end
    if string.match(text, "^StatusManager") ~= nil then return true end
    if string.match(text, "^FightPlayer") ~= nil then return true end
    return false
end

local function valid_status_name(name, fallbackId)
    return not placeholder_status_name(name, fallbackId)
end

local function status_name(status, fallbackId)
    local direct = safe_prop(status, "Name") or safe_prop(status, "name")
    if direct ~= nil and valid_status_name(direct, fallbackId) then return tostring(direct) end

    local cfg = safe_prop(status, "dataConfig") or safe_prop(status, "DataConfig")
    local data = cfg ~= nil and safe_prop(cfg, "data") or nil
    local name = dict_get(data, "Name") or dict_get(data, "TextId")
    if name ~= nil and valid_status_name(name, fallbackId) then return tostring(name) end

    local go = safe_prop(status, "gameObject")
    name = safe_prop(go, "name")
    if name ~= nil and valid_status_name(name, fallbackId) then return tostring(name) end

    return tostring(fallbackId or "Unknown")
end

local function status_is_dead(status)
    if status == nil then return false end
    local hp = safe_prop(status, "CurHp")
    if hp ~= nil and tonumber(hp) ~= nil and tonumber(hp) <= 0 then return true end
    local flags = { "IsDead", "isDead", "Dead", "dead" }
    for _, prop in ipairs(flags) do
        local value = safe_prop(status, prop)
        if value == true or tostring(value) == "True" or tostring(value) == "true" then return true end
    end
    local states = { "State", "state", "StatusState", "statusState" }
    for _, prop in ipairs(states) do
        local value = safe_prop(status, prop)
        if value ~= nil then
            local text = tostring(value)
            if string.find(text, "Dead") ~= nil then return true end
        end
    end
    return false
end

local function remember_status(status)
    local id = status_id(status)
    if id == nil then return nil end
    DM.statusById[id] = status
    local stat = DM.stats[id]
    local freshName = status_name(status, id)
    if stat == nil then
        stat = {
            id = id,
            name = freshName,
            friend = not is_enemy_id(id),
            current = 0,
            battle = 0,
            global = 0,
            details = {},
            dead = status_is_dead(status)
        }
        DM.stats[id] = stat
    else
        if valid_status_name(freshName, id) or placeholder_status_name(stat.name, id) then
            stat.name = freshName
        end
        stat.friend = not is_enemy_id(id)
    end
    stat.dead = status_is_dead(status)
    stat.onField = true
    return stat
end

local function invalid_source_id(id)
    if id == nil then return true end
    id = string.lower(tostring(id))
    return id == "" or id == "0" or id == "null" or id == "nil" or id == "none"
end

local function fight_status_by_id(id)
    if invalid_source_id(id) then return nil end
    id = tostring(id)
    local status = DM.statusById[id]
    if status ~= nil then return status end
    pcall(function()
        local fight = CS.FightManager.Instance
        local statuses = fight ~= nil and fight.statuses or nil
        if statuses ~= nil then
            local value = nil
            local ok = pcall(function() value = statuses:get_Item(id) end)
            if not ok then
                pcall(function() value = statuses[id] end)
            end
            if value ~= nil then status = value end
        end
    end)
    if status ~= nil then remember_status(status) end
    return status
end

local function current_action_role_id()
    local roleId = nil
    pcall(function()
        local fight = CS.FightManager.Instance
        if fight == nil then return end
        roleId = safe_prop(fight, "NetworkNowActionRole") or safe_prop(fight, "NowActionRole")
    end)
    if invalid_source_id(roleId) then return nil end
    return tostring(roleId)
end

local function resolve_source_fallback(sourceStatus, sourceId)
    if not invalid_source_id(sourceId) then
        sourceId = tostring(sourceId)
        local status = fight_status_by_id(sourceId)
        if status ~= nil then sourceStatus = status end
        return sourceStatus, sourceId
    end
    local actionId = current_action_role_id()
    if actionId == nil then
        if sourceStatus ~= nil then
            local stat = remember_status(sourceStatus)
            if stat ~= nil then return sourceStatus, stat.id end
        end
        return sourceStatus, nil
    end
    local actionStatus = fight_status_by_id(actionId)
    return actionStatus or sourceStatus, actionId
end

local function remember_id(id)
    if invalid_source_id(id) then return nil end
    id = tostring(id)
    local status = DM.statusById[id]
    if status ~= nil then return remember_status(status) end
    local stat = DM.stats[id]
    if stat == nil then
        stat = {
            id = id,
            name = id,
            friend = not is_enemy_id(id),
            current = 0,
            battle = 0,
            global = 0,
            details = {},
            dead = false
        }
        DM.stats[id] = stat
    end
    return stat
end

local function status_snapshot(status)
    if status == nil then return nil end
    remember_status(status)
    return {
        status = status,
        id = status_id(status),
        hp = tonumber(safe_prop(status, "CurHp")) or 0,
        defend = tonumber(safe_prop(status, "Defend")) or 0
    }
end

local function data_config_from(value)
    if value == nil then return nil end
    local cfg = safe_prop(value, "dataConfig") or safe_prop(value, "DataConfig")
    if cfg ~= nil then return cfg end
    local buffConfig = safe_prop(value, "buffConfig")
    if buffConfig ~= nil then
        cfg = safe_prop(buffConfig, "dataConfig") or safe_prop(buffConfig, "DataConfig")
        if cfg ~= nil then return cfg end
    end
    if safe_prop(value, "data") ~= nil or safe_prop(value, "Vars") ~= nil then
        return value
    end
    return nil
end

local function data_config_id(cfg)
    if cfg == nil then return nil end
    local id = safe_prop(cfg, "Id") or safe_prop(cfg, "DataId")
    if id == nil then id = dict_get(safe_prop(cfg, "data"), "Id") end
    if id == nil then id = dict_get(safe_prop(cfg, "Vars"), "Id") end
    if id == nil then return nil end
    id = tostring(id)
    if id == "" then return nil end
    return id
end

local function executor_data_id(exe)
    return data_config_id(data_config_from(exe))
end

local function buff_id_from_value(value)
    if value == nil then return nil end
    if type(value) == "string" or type(value) == "number" then
        local text = tostring(value)
        if text ~= "" then return text end
    end
    local id = data_config_id(data_config_from(value))
    if id ~= nil then return id end
    id = safe_prop(value, "BuffId") or safe_prop(value, "Id") or safe_prop(value, "DataId")
    if id == nil then
        local cfg = safe_prop(value, "buffConfig")
        id = safe_prop(cfg, "BuffId") or safe_prop(cfg, "Id") or data_config_id(data_config_from(cfg))
    end
    if id == nil then return nil end
    id = tostring(id)
    if id == "" then return nil end
    return id
end

local function localize_dict_value(data, key)
    if data == nil or key == nil then return nil end
    local value = nil
    pcall(function() value = data:Localize(key) end)
    if value == nil then pcall(function() value = CS.LocalizeEx.Localize(data, key) end) end
    if value ~= nil then
        value = tostring(value)
        if value ~= "" then
            return value
        end
    end
    value = dict_get(data, key)
    if value ~= nil and tostring(value) ~= "" then return tostring(value) end
    value = dict_get(data, key .. "_zh-Hant")
    if value ~= nil and tostring(value) ~= "" then return tostring(value) end
    value = dict_get(data, key .. "_en")
    if value ~= nil and tostring(value) ~= "" then return tostring(value) end
    return nil
end

local function csv_split_line(line)
    local result, field, i, inQuote = {}, {}, 1, false
    line = tostring(line or "")
    while i <= #line do
        local ch = string.sub(line, i, i)
        if ch == '"' then
            local nextCh = string.sub(line, i + 1, i + 1)
            if inQuote and nextCh == '"' then
                table.insert(field, '"')
                i = i + 1
            else
                inQuote = not inQuote
            end
        elseif ch == "," and not inQuote then
            table.insert(result, table.concat(field))
            field = {}
        else
            table.insert(field, ch)
        end
        i = i + 1
    end
    table.insert(result, table.concat(field))
    return result
end

local function kind_from_text_folder(folder)
    folder = tostring(folder or "")
    if folder == "Card" or folder == "PartnerCard" then return "卡牌" end
    if folder == "EnemyCard" or folder == "Career" then return "技能" end
    if folder == "Buff" then return "BUFF" end
    if folder == "Relic" then return "遗物" end
    if folder == "Blessing" or folder == "Bless" or folder == "EnemyBless" then return "祝福" end
    if folder == "EnchTag" or folder == "Enchtag" or folder == "Ench" then return "火漆" end
    return "来源"
end

end

local function register_text_name(id, name, kind, modName, fileStem)
    if id == nil or id == "" or name == nil or name == "" then return end
    DM.textNameCache[id] = name
    DM.textKindCache[id] = kind
    if fileStem ~= nil and fileStem ~= "" then
        DM.textNameCache[fileStem .. "_" .. id] = name
        DM.textKindCache[fileStem .. "_" .. id] = kind
    end
    if modName ~= nil and modName ~= "" and fileStem ~= nil and fileStem ~= "" then
        DM.textNameCache[modName .. "_" .. fileStem .. "_" .. id] = name
        DM.textKindCache[modName .. "_" .. fileStem .. "_" .. id] = kind
    end
end

local function parse_text_csv(path, modName, folder, fileStem)
    local ok, text = pcall(function()
        return CS.System.IO.File.ReadAllText(path, CS.System.Text.Encoding.UTF8)
    end)
    if not ok or text == nil then
        ok, text = pcall(function() return CS.System.IO.File.ReadAllText(path) end)
    end
    if not ok or text == nil then return end

    text = tostring(text):gsub("\r\n", "\n"):gsub("\r", "\n")
    local header = nil
    local nameIndex, idIndex = nil, nil
    local rowIndex = 0
    for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
        rowIndex = rowIndex + 1
        if rowIndex == 1 then
            header = csv_split_line(line)
            for i, col in ipairs(header) do
                if col == "Id" then idIndex = i end
                if col == "Name" then nameIndex = i end
            end
        elseif rowIndex > 2 and idIndex ~= nil and nameIndex ~= nil and line ~= "" then
            local cols = csv_split_line(line)
            local id = cols[idIndex]
            local name = cols[nameIndex]
            if id ~= nil and id ~= "" and name ~= nil and name ~= "" then
                register_text_name(id, name, kind_from_text_folder(folder), modName, fileStem)
            end
        end
    end
end

local function ensure_text_name_cache()
    if DM.textNameCache ~= nil then return end
    DM.textNameCache = {}
    DM.textKindCache = {}

    pcall(function()
        local modsPath = nil
        pcall(function() modsPath = CS.Globals.ModsPath end)
        if modsPath == nil or tostring(modsPath) == "" then
            local parent = DM.modDir ~= nil and CS.System.IO.Directory.GetParent(DM.modDir) or nil
            if parent ~= nil then modsPath = parent.FullName end
        end
        if modsPath == nil or not CS.System.IO.Directory.Exists(modsPath) then return end

        local modDirs = CS.System.IO.Directory.GetDirectories(modsPath)
        foreach_collection(modDirs, function(modDir)
            local modName = tostring(CS.System.IO.Path.GetFileName(modDir))
            local textRoot = CS.System.IO.Path.Combine(modDir, "Text")
            if not CS.System.IO.Directory.Exists(textRoot) then return end
            local folders = CS.System.IO.Directory.GetDirectories(textRoot)
            foreach_collection(folders, function(folderPath)
                local folder = tostring(CS.System.IO.Path.GetFileName(folderPath))
                local files = CS.System.IO.Directory.GetFiles(folderPath, "*.csv")
                foreach_collection(files, function(filePath)
                    local fileStem = tostring(CS.System.IO.Path.GetFileNameWithoutExtension(filePath))
                    parse_text_csv(filePath, modName, folder, fileStem)
                end)
            end)
        end)
    end)
end

local function name_from_row(row)
    return localize_dict_value(row, "Name") or localize_dict_value(row, "Action1") or localize_dict_value(row, "Title") or dict_get(row, "TextId")
end

local function data_from_global_id(id)
    local data = nil
    pcall(function() data = CS.Globals.GetDataBydId(id) end)
    if data == nil then return nil end
    local directName = name_from_row(data)
    if directName ~= nil then return data end
    local cfg = data_config_from(data)
    if cfg ~= nil and safe_prop(cfg, "data") ~= nil then return safe_prop(cfg, "data") end
    return cfg or data
end

local function data_from_type(typeName, id)
    local row = nil
    pcall(function()
        local gcm = CS.Singleton(CS.GameConfigManager).Instance
        if gcm ~= nil and CS.DataType ~= nil and CS.DataType[typeName] ~= nil then
            row = gcm:GetOne(CS.DataType[typeName], id)
        end
    end)
    return row
end

local function preferred_data_for_id(id)
    local text = tostring(id or "")
    local lower = string.lower(text)
    if string.find(lower, "buff") ~= nil then
        return data_from_type("Buff", text) or data_from_global_id(text)
    end
    if string.find(lower, "card") ~= nil then
        return data_from_type("Card", text) or data_from_type("PartnerCard", text) or data_from_type("EnemyCard", text) or data_from_global_id(text)
    end
    if string.find(lower, "career") ~= nil then
        return data_from_type("Career", text) or data_from_global_id(text)
    end
    if string.find(lower, "relic") ~= nil then
        return data_from_type("Relic", text) or data_from_global_id(text)
    end
    if string.find(lower, "blessing") ~= nil or string.find(lower, "bless") ~= nil then
        return data_from_type("Blessing", text) or data_from_type("Bless", text) or data_from_global_id(text)
    end
    if string.find(lower, "enchtag") ~= nil or string.find(lower, "ench") ~= nil then
        return data_from_type("EnchTag", text) or data_from_global_id(text)
    end
    return data_from_global_id(text)
        or data_from_type("Card", text)
        or data_from_type("PartnerCard", text)
        or data_from_type("EnemyCard", text)
        or data_from_type("Career", text)
        or data_from_type("Buff", text)
        or data_from_type("Relic", text)
        or data_from_type("Blessing", text)
        or data_from_type("Bless", text)
        or data_from_type("EnchTag", text)
end

local function lookup_data_name(id)
    if id == nil or tostring(id) == "" then return "未知来源" end
    local text = tostring(id)
    local data = preferred_data_for_id(text)
    local name = name_from_row(data)
    if name ~= nil and tostring(name) ~= "" then return tostring(name) end
    ensure_text_name_cache()
    name = DM.textNameCache[text] or DM.textNameCache[string.gsub(text, "^%*", "")]
    if name ~= nil and tostring(name) ~= "" then return tostring(name) end
    return text
end

local function source_kind(id)
    local text = tostring(id or "")
    local lower = string.lower(text)
    if text == "" then return "来源" end
    ensure_text_name_cache()
    local cachedKind = DM.textKindCache[text] or DM.textKindCache[string.gsub(text, "^%*", "")]
    if cachedKind ~= nil then return cachedKind end
    if string.find(lower, "buff") ~= nil then return "BUFF" end
    if string.find(lower, "card") ~= nil then return "卡牌" end
    if string.find(lower, "skill") ~= nil or string.find(lower, "career") ~= nil then return "技能" end
    if string.find(lower, "relic") ~= nil then return "遗物" end
    if string.find(lower, "blessing") ~= nil or string.find(lower, "bless") ~= nil then return "祝福" end
    if string.find(lower, "enchtag") ~= nil or string.find(lower, "ench") ~= nil then return "火漆" end
    return "来源"
end

local function source_label(id, forcedKind)
    local kind = forcedKind or source_kind(id)
    return kind .. ": " .. lookup_data_name(id)
end

local function buff_level(status, buffId)
    if status == nil or buffId == nil then return nil end
    local buff = nil
    local ok = pcall(function() buff = status:GetBuff(buffId) end)
    if not ok or buff == nil then return nil end
    local cfg = safe_prop(buff, "buffConfig")
    local level = cfg ~= nil and safe_prop(cfg, "Level") or nil
    return tonumber(level) or 0
end

local function buff_owner_key(targetId, buffId)
    if targetId == nil or buffId == nil then return nil end
    local id = buff_id_from_value(buffId) or tostring(buffId)
    if id == "" then return nil end
    return tostring(targetId) .. "|" .. id
end

local function bind_buff_instance_owner(targetStatus, buffId, sourceId)
    if targetStatus == nil or buffId == nil or sourceId == nil then return end
    local buff = nil
    pcall(function() buff = targetStatus:GetBuff(buffId) end)
    if buff == nil then return end
    DM.buffObjectOwners[tostring(buff)] = sourceId
    local cfg = safe_prop(buff, "buffConfig")
    if cfg ~= nil then DM.buffObjectOwners[tostring(cfg)] = sourceId end
    local dataCfg = data_config_from(buff)
    if dataCfg ~= nil then DM.buffObjectOwners[tostring(dataCfg)] = sourceId end
end

local function set_buff_owner(targetStatus, buffId, sourceStatus, explicitSourceId)
    local targetId = status_id(targetStatus)
    local sourceId = explicitSourceId or status_id(sourceStatus)
    local key = buff_owner_key(targetId, buffId)
    if key == nil or sourceId == nil then return end
    remember_status(targetStatus)
    if sourceStatus ~= nil then remember_status(sourceStatus) else remember_id(sourceId) end
    DM.buffOwners[key] = sourceId
    bind_buff_instance_owner(targetStatus, buffId, sourceId)
end

local function add_buff_stack_owner(targetStatus, buffId, sourceStatus, explicitSourceId, stacks)
    stacks = tonumber(stacks) or 0
    if stacks <= 0 then return end
    local targetId = status_id(targetStatus)
    local sourceId = explicitSourceId or status_id(sourceStatus)
    local key = buff_owner_key(targetId, buffId)
    if key == nil or sourceId == nil then return end
    set_buff_owner(targetStatus, buffId, sourceStatus, sourceId)
    DM.buffStacks[key] = DM.buffStacks[key] or {}
    DM.buffStacks[key][sourceId] = (DM.buffStacks[key][sourceId] or 0) + stacks
end

local function buff_owner_id(targetStatus, buffId)
    local key = buff_owner_key(status_id(targetStatus), buffId)
    if key ~= nil and DM.buffOwners[key] ~= nil then return DM.buffOwners[key] end
    if buffId ~= nil then
        local id = DM.buffObjectOwners[tostring(buffId)]
        if id ~= nil then return id end
    end
    local realId = buff_id_from_value(buffId)
    if targetStatus ~= nil and realId ~= nil then
        local buff = nil
        pcall(function() buff = targetStatus:GetBuff(realId) end)
        if buff ~= nil then
            local id = DM.buffObjectOwners[tostring(buff)]
            if id ~= nil then return id end
            local cfg = safe_prop(buff, "buffConfig")
            if cfg ~= nil then
                id = DM.buffObjectOwners[tostring(cfg)]
                if id ~= nil then return id end
            end
        end
    end
    return nil
end

local function buff_stack_owners(targetStatus, buffId)
    local key = buff_owner_key(status_id(targetStatus), buffId)
    if key == nil then return nil, 0 end
    local stacks = DM.buffStacks[key]
    if stacks == nil then return nil, 0 end
    local total = 0
    for _, count in pairs(stacks) do
        total = total + (tonumber(count) or 0)
    end
    if total <= 0 then return nil, 0 end
    local current = buff_level(targetStatus, buff_id_from_value(buffId) or buffId)
    if current ~= nil and current > 0 and current < total then
        local scale = current / total
        local newTotal = 0
        for ownerId, count in pairs(stacks) do
            local adjusted = (tonumber(count) or 0) * scale
            stacks[ownerId] = adjusted
            newTotal = newTotal + adjusted
        end
        total = newTotal
    elseif current ~= nil and current <= 0 then
        DM.buffStacks[key] = nil
        return nil, 0
    end
    return stacks, total
end

local function current_script_context()
    local stack = DM.scriptContextStack or {}
    return stack[#stack]
end

local function source_context_from_executor(exe)
    local dataId = executor_data_id(exe)
    local source = safe_prop(exe, "Self") or safe_prop(exe, "status")
    local sourceId = status_id(source)
    local ownerId = buff_owner_id(source, dataId)
    if ownerId ~= nil then
        sourceId = ownerId
        source = fight_status_by_id(ownerId) or source
    end
    source, sourceId = resolve_source_fallback(source, sourceId)
    if source ~= nil then remember_status(source) end
    if sourceId ~= nil then remember_id(sourceId) end
    return {
        exe = exe,
        source = source,
        sourceId = sourceId,
        dataId = dataId
    }
end

local function push_script_context(exe)
    local ctx = source_context_from_executor(exe)
    DM.scriptContextStack = DM.scriptContextStack or {}
    table.insert(DM.scriptContextStack, ctx)
end

local function pop_script_context()
    local stack = DM.scriptContextStack or {}
    if #stack > 0 then table.remove(stack) end
end

local function snapshot_loss(snapshot)
    if snapshot == nil or snapshot.status == nil then return 0 end
    local hp = tonumber(safe_prop(snapshot.status, "CurHp")) or snapshot.hp or 0
    local defend = tonumber(safe_prop(snapshot.status, "Defend")) or snapshot.defend or 0
    local hpLoss = math.max(0, (snapshot.hp or 0) - hp)
    local shieldLoss = math.max(0, (snapshot.defend or 0) - defend)
    return hpLoss + shieldLoss
end

local function add_damage(sourceStatus, sourceId, amount, targetStatus, detailLabel)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return end
    if targetStatus ~= nil then remember_status(targetStatus) end

    sourceStatus, sourceId = resolve_source_fallback(sourceStatus, sourceId)

    local stat = nil
    if sourceStatus ~= nil then stat = remember_status(sourceStatus) end
    if stat == nil then stat = remember_id(sourceId) end
    if stat == nil then return end

    stat.current = (stat.current or 0) + amount
    stat.battle = (stat.battle or 0) + amount
    if stat.friend then
        stat.global = (stat.global or 0) + amount
    end
    stat.details = stat.details or {}
    detailLabel = detailLabel or "未知来源"
    stat.details[detailLabel] = (stat.details[detailLabel] or 0) + amount
end

end

local function add_damage_split_by_buff(targetStatus, buffId, amount, fallbackSource, fallbackSourceId, detailLabel)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return end
    local stacks, total = buff_stack_owners(targetStatus, buffId)
    if stacks == nil or total <= 0 then
        add_damage(fallbackSource, fallbackSourceId, amount, targetStatus, detailLabel)
        return
    end

    local parts = {}
    for ownerId, count in pairs(stacks) do
        local weight = tonumber(count) or 0
        if weight > 0 then
            table.insert(parts, { ownerId = ownerId, weight = weight })
        end
    end
    table.sort(parts, function(a, b) return tostring(a.ownerId) < tostring(b.ownerId) end)

    local used = 0
    for i, part in ipairs(parts) do
        local share = 0
        if i == #parts then
            share = amount - used
        else
            share = math.min(amount - used, math.floor(amount * part.weight / total + 0.5))
            used = used + share
        end
        if share > 0 then
            add_damage(DM.statusById[part.ownerId], part.ownerId, share, targetStatus, detailLabel)
        end
    end
end

local function all_known_statuses()
    for _, stat in pairs(DM.stats) do
        stat.onField = false
    end
    local seen = {}
    local result = {}
    local function add(status)
        local id = status_id(status)
        if id ~= nil and not seen[id] then
            seen[id] = true
            remember_status(status)
            table.insert(result, status)
        end
    end

    pcall(function()
        local fp = CS.FightPlayer.Instance
        if fp ~= nil then add(fp.Status) end
    end)
    pcall(function()
        local enemies = CS.EnemyManager.Instance.enemyList
        foreach_collection(enemies, function(enemy)
            add(safe_prop(enemy, "Status") or safe_prop(enemy, "status"))
        end)
    end)
    pcall(function()
        local all = CS.UnityEngine.Resources.FindObjectsOfTypeAll(typeof(CS.StatusManager))
        foreach_collection(all, add)
    end)
    for _, status in pairs(DM.statusById) do add(status) end
    return result
end

local function escape_rich_text(s)
    s = tostring(s or "")
    s = string.gsub(s, "&", "&amp;")
    s = string.gsub(s, "<", "&lt;")
    s = string.gsub(s, ">", "&gt;")
    return s
end

local function pct(part, total)
    part = tonumber(part) or 0
    total = tonumber(total) or 0
    if total <= 0 then return "0.0%" end
    return string.format("%.1f%%", part * 100 / total)
end

local function short_name(name, maxChars)
    name = escape_rich_text(name or "")
    maxChars = maxChars or 8
    if utf8 ~= nil and utf8.len ~= nil and utf8.offset ~= nil then
        local ok, len = pcall(function() return utf8.len(name) end)
        if ok and len ~= nil and len > maxChars then
            local cut = utf8.offset(name, maxChars + 1)
            if cut ~= nil then return string.sub(name, 1, cut - 1) end
        end
        return name
    end
    if string.len(name) > maxChars * 3 then
        return string.sub(name, 1, maxChars * 3)
    end
    return name
end

local function stat_value_pct(value, total)
    return tostring(value or 0) .. "(" .. pct(value or 0, total) .. ")"
end

local function row_sort(a, b)
    if (a.battle or 0) ~= (b.battle or 0) then return (a.battle or 0) > (b.battle or 0) end
    if (a.current or 0) ~= (b.current or 0) then return (a.current or 0) > (b.current or 0) end
    if (a.friend and not b.friend) then return true end
    if (b.friend and not a.friend) then return false end
    return tostring(a.name) < tostring(b.name)
end

local function friend_slot(stat)
    if stat == nil or not stat.friend then return nil end
    local slot = DM.friendSlots[stat.id]
    if slot ~= nil then return slot end
    if DM.nextFriendSlot > 4 then return nil end
    slot = DM.nextFriendSlot
    DM.friendSlots[stat.id] = slot
    DM.nextFriendSlot = DM.nextFriendSlot + 1
    return slot
end

local function build_lines()
    all_known_statuses()
    local totalCurrent, totalBattle, totalGlobal, totalFriendBattle = 0, 0, 0, 0
    for _, stat in pairs(DM.stats) do
        totalCurrent = totalCurrent + (stat.current or 0)
        totalBattle = totalBattle + (stat.battle or 0)
        if stat.friend then
            totalGlobal = totalGlobal + (stat.global or 0)
            totalFriendBattle = totalFriendBattle + (stat.battle or 0)
        end
    end

    local rows = {}
    for _, stat in pairs(DM.stats) do
        if stat.onField or (stat.current or 0) > 0 or (stat.battle or 0) > 0 then
            table.insert(rows, stat)
        end
    end
    table.sort(rows, function(a, b)
        if (a.friend and not b.friend) then return true end
        if (b.friend and not a.friend) then return false end
        if (a.battle or 0) ~= (b.battle or 0) then return (a.battle or 0) > (b.battle or 0) end
        return tostring(a.name) < tostring(b.name)
    end)

    local linesOut = {}
    table.insert(linesOut, "<b>输出统计</b>  <size=15><color=#C9D1D9>" .. tostring(DM.hotkeyName or "F8") .. " 显示/隐藏 | 第" .. tostring(DM.roundIndex) .. "回合</color></size>")
    table.insert(linesOut, "<size=15><color=#9AA4B2>阵营                本回合                 本场战斗                 本局累计</color></size>")

    local maxRows = 14
    for i, stat in ipairs(rows) do
        if i > maxRows then break end
        local marker = stat.friend and "<color=#7EE787>友</color>" or "<color=#FF7B72>敌</color>"
        local name = escape_rich_text(stat.name)
        if string.len(name) > 18 then name = string.sub(name, 1, 18) end
        local globalText = "-"
        if stat.friend then
            globalText = tostring(stat.global or 0) .. " (" .. pct(stat.global or 0, totalGlobal) .. ")"
        end
        table.insert(linesOut, string.format(
            "%s %-18s  %5d (%s)   %6d (%s)   %s",
            marker,
            name,
            stat.current or 0,
            pct(stat.current or 0, totalCurrent),
            stat.battle or 0,
            pct(stat.battle or 0, totalBattle),
            globalText
        ))
    end
    if #rows == 0 then
        table.insert(linesOut, "<color=#9AA4B2>等待战斗伤害数据……</color>")
    end
    return table.concat(linesOut, "\n")
end

local function build_compact_lines()
    all_known_statuses()
    local totalCurrent, totalBattle, totalGlobal, totalFriendBattle = 0, 0, 0, 0
    for _, stat in pairs(DM.stats) do
        totalCurrent = totalCurrent + (stat.current or 0)
        totalBattle = totalBattle + (stat.battle or 0)
        if stat.friend then
            totalGlobal = totalGlobal + (stat.global or 0)
            totalFriendBattle = totalFriendBattle + (stat.battle or 0)
        end
    end

    local rows = {}
    local friendRows = {}
    for _, stat in pairs(DM.stats) do
        if stat.onField or (stat.current or 0) > 0 or (stat.battle or 0) > 0 then
            table.insert(rows, stat)
            if stat.friend then table.insert(friendRows, stat) end
        end
    end
    table.sort(rows, row_sort)
    table.sort(friendRows, row_sort)

    local linesOut = {}
    DM.linkToStat = {}
    DM.detailRows = {}
    DM.detailBounds = {}
    DM.rowBarData = {}
    table.insert(linesOut, "<b>输出统计</b>  <size=12><color=#C9D1D9>" .. tostring(DM.hotkeyName or "F8") .. " 显示/隐藏 | 第" .. tostring(DM.roundIndex) .. "回合</color></size>")
    table.insert(linesOut, "<size=12><color=#9AA4B2><pos=0>阵营<pos=24>名字<pos=104>本回合<pos=184>本场<pos=264>本局<pos=392>详情</color></size>")

    local maxRows = 5
    for i, stat in ipairs(rows) do
        if i > maxRows then break end
        local marker = stat.friend and "<color=#7EE787>友</color>" or "<color=#FF7B72>敌</color>"
        local slot = friend_slot(stat)
        if slot ~= nil then marker = "<color=#7EE787>" .. tostring(slot) .. "P</color>" end
        if stat.friend then
            local ratio = 0
            if #friendRows == 1 then
                ratio = 1
            elseif totalFriendBattle > 0 then
                ratio = (tonumber(stat.battle) or 0) / totalFriendBattle
            end
            table.insert(DM.rowBarData, { row = i, slot = slot, ratio = ratio })
        end
        local name = short_name(stat.name, stat.dead and 6 or 9)
        if stat.dead then name = name .. " <color=#FF7B72>(倒)</color>" end
        local globalText = "-"
        if stat.friend then
            globalText = stat_value_pct(stat.global or 0, totalGlobal)
        end
        local linkId = "dm" .. tostring(i)
        DM.linkToStat[linkId] = stat.id
        DM.detailRows[i] = stat.id
        table.insert(linesOut, string.format(
            "%s <pos=24>%s<pos=104>%s<pos=184>%s<pos=264>%s<pos=392><link=\"%s\"><color=#FFD166>查看</color></link>",
            marker,
            name,
            stat_value_pct(stat.current or 0, totalCurrent),
            stat_value_pct(stat.battle or 0, totalBattle),
            globalText,
            linkId
        ))
    end
    if #rows > maxRows then
        table.insert(linesOut, "<size=13><color=#9AA4B2>还有 " .. tostring(#rows - maxRows) .. " 个单位未显示</color></size>")
    elseif #rows == 0 then
        table.insert(linesOut, "<color=#9AA4B2>等待战斗伤害数据……</color>")
    end
    return table.concat(linesOut, "\n")
end

local ensure_fight_identity
local hide_tooltip
local hide_detail_popup
local update_detail_bounds
local stat_detail_text
local resize_detail_panel
local clamp
local screen_size

local function row_bar_color(slot)
    local colors = {
        [1] = { 0.494, 0.906, 0.529, 0.24 },
        [2] = { 0.431, 0.745, 1.000, 0.24 },
        [3] = { 0.862, 0.588, 1.000, 0.24 },
        [4] = { 1.000, 0.820, 0.400, 0.24 }
    }
    local c = colors[slot] or { 0.790, 0.820, 0.850, 0.22 }
    return CS.UnityEngine.Color(c[1], c[2], c[3], c[4])
end

local function ensure_row_bar(index)
    if DM.rowBarParent == nil then return nil end
    DM.rowBars = DM.rowBars or {}
    local bar = DM.rowBars[index]
    if bar ~= nil then return bar end

    local obj = CS.UnityEngine.GameObject("DamageMeterRowBar" .. tostring(index))
    obj.transform:SetParent(DM.rowBarParent.transform, false)
    local image = obj:AddComponent(typeof(CS.UnityEngine.UI.Image))
    image.raycastTarget = false
    local rt = obj:GetComponent(typeof(CS.UnityEngine.RectTransform))
    rt.anchorMin = CS.UnityEngine.Vector2(0, 1)
    rt.anchorMax = CS.UnityEngine.Vector2(0, 1)
    rt.pivot = CS.UnityEngine.Vector2(0, 1)
    bar = { obj = obj, image = image, rt = rt }
    DM.rowBars[index] = bar
    return bar
end

local function hide_row_bars()
    for _, bar in ipairs(DM.rowBars or {}) do
        if bar.obj ~= nil then pcall(function() bar.obj:SetActive(false) end) end
    end
end

local function row_text_bounds(rowIndex)
    if DM.text == nil or DM.text.textInfo == nil or DM.rowBarParent == nil then return nil end
    local textInfo = DM.text.textInfo
    local charInfo = textInfo.characterInfo
    local charCount = tonumber(safe_prop(textInfo, "characterCount")) or 0
    if charInfo == nil or charCount <= 0 then return nil end

    local textTr = DM.text.transform
    local barTr = DM.rowBarParent.transform
    local targetLine = rowIndex + 1
    local minX, minY, maxX, maxY = 999999, 999999, -999999, -999999
    for i = 0, charCount - 1 do
        local ci = nil
        local ok = pcall(function() ci = charInfo[i] end)
        if not ok or ci == nil then pcall(function() ci = charInfo:get_Item(i) end) end
        if ci ~= nil then
            local lineNumber = tonumber(safe_prop(ci, "lineNumber")) or -1
            local visible = true
            pcall(function() visible = ci.isVisible end)
            if visible and lineNumber == targetLine then
                local bl = safe_prop(ci, "bottomLeft")
                local trc = safe_prop(ci, "topRight")
                if bl ~= nil and trc ~= nil and textTr ~= nil and barTr ~= nil then
                    local p1 = barTr:InverseTransformPoint(textTr:TransformPoint(bl))
                    local p2 = barTr:InverseTransformPoint(textTr:TransformPoint(trc))
                    minX = math.min(minX, tonumber(p1.x) or minX, tonumber(p2.x) or minX)
                    minY = math.min(minY, tonumber(p1.y) or minY, tonumber(p2.y) or minY)
                    maxX = math.max(maxX, tonumber(p1.x) or maxX, tonumber(p2.x) or maxX)
                    maxY = math.max(maxY, tonumber(p1.y) or maxY, tonumber(p2.y) or maxY)
                end
            end
        end
    end

    if maxX <= minX or maxY <= minY then return nil end
    return {
        x = math.max(0, minX - 1),
        y = maxY + 1,
        width = math.max(1, maxX - minX + 2),
        height = math.max(1, maxY - minY + 2)
    }
end

local function update_row_bars()
    if not DM.visible or DM.rowBarParent == nil then
        hide_row_bars()
        return
    end

    hide_row_bars()
    local rowData = DM.rowBarData or {}
    for i, data in ipairs(rowData) do
        local ratio = tonumber(data.ratio) or 0
        if ratio < 0 then ratio = 0 end
        if ratio > 1 then ratio = 1 end
        local bounds = row_text_bounds(data.row)
        local width = bounds ~= nil and math.max(0, bounds.width * ratio) or 0
        local bar = ensure_row_bar(i)
        if bar ~= nil and bounds ~= nil and width > 0 then
            pcall(function()
                bar.image.color = row_bar_color(data.slot)
                bar.rt.anchoredPosition = CS.UnityEngine.Vector2(bounds.x, bounds.y)
                bar.rt.sizeDelta = CS.UnityEngine.Vector2(width, bounds.height)
                bar.obj:SetActive(true)
            end)
        end
    end
end
local function init_ui()
    if DM.text ~= nil and DM.panel ~= nil then return end
    pcall(function()
        local allTexts = CS.UnityEngine.Resources.FindObjectsOfTypeAll(typeof(CS.TMPro.TextMeshProUGUI))
        local font, mat = nil, nil
        if allTexts ~= nil and allTexts.Length ~= nil and allTexts.Length > 0 then
            font = allTexts[0].font
            mat = allTexts[0].fontSharedMaterial
        end

        local canvasObj = CS.UnityEngine.GameObject("DamageMeterCanvas")
        local canvas = canvasObj:AddComponent(typeof(CS.UnityEngine.Canvas))
        canvas.renderMode = CS.UnityEngine.RenderMode.ScreenSpaceOverlay
        canvas.sortingOrder = 32000
        pcall(function() canvasObj:AddComponent(typeof(CS.UnityEngine.UI.CanvasScaler)) end)
        pcall(function() canvasObj:AddComponent(typeof(CS.UnityEngine.UI.GraphicRaycaster)) end)

        local panel = CS.UnityEngine.GameObject("DamageMeterPanel")
        panel.transform:SetParent(canvasObj.transform, false)
        local image = panel:AddComponent(typeof(CS.UnityEngine.UI.Image))
        image.color = CS.UnityEngine.Color(0.04, 0.045, 0.055, 0.88)
        local rt = panel:GetComponent(typeof(CS.UnityEngine.RectTransform))
        rt.anchorMin = CS.UnityEngine.Vector2(0, 1)
        rt.anchorMax = CS.UnityEngine.Vector2(0, 1)
        rt.pivot = CS.UnityEngine.Vector2(0, 1)
        rt.anchoredPosition = CS.UnityEngine.Vector2(16, -388)
        rt.sizeDelta = CS.UnityEngine.Vector2(520, 170)

        local barParent = CS.UnityEngine.GameObject("DamageMeterRowBars")
        barParent.transform:SetParent(panel.transform, false)
        pcall(function() barParent:AddComponent(typeof(CS.UnityEngine.RectTransform)) end)
        local brt = barParent:GetComponent(typeof(CS.UnityEngine.RectTransform))
        brt.anchorMin = CS.UnityEngine.Vector2(0, 0)
        brt.anchorMax = CS.UnityEngine.Vector2(1, 1)
        brt.pivot = CS.UnityEngine.Vector2(0, 1)
        brt.offsetMin = CS.UnityEngine.Vector2(10, 8)
        brt.offsetMax = CS.UnityEngine.Vector2(-10, -8)

        local textObj = CS.UnityEngine.GameObject("DamageMeterText")
        textObj.transform:SetParent(panel.transform, false)
        local text = textObj:AddComponent(typeof(CS.TMPro.TextMeshProUGUI))
        if font ~= nil then
            text.font = font
            text.fontSharedMaterial = mat
        end
        text.fontSize = 12
        text.richText = true
        text.raycastTarget = false
        text.alignment = CS.TMPro.TextAlignmentOptions.TopLeft
        text.enableWordWrapping = false
        local trt = textObj:GetComponent(typeof(CS.UnityEngine.RectTransform))
        trt.anchorMin = CS.UnityEngine.Vector2(0, 0)
        trt.anchorMax = CS.UnityEngine.Vector2(1, 1)
        trt.pivot = CS.UnityEngine.Vector2(0, 1)
        trt.offsetMin = CS.UnityEngine.Vector2(10, 8)
        trt.offsetMax = CS.UnityEngine.Vector2(-10, -8)

        local tipPanel = CS.UnityEngine.GameObject("DamageMeterTooltip")
        tipPanel.transform:SetParent(canvasObj.transform, false)
        local tipImage = tipPanel:AddComponent(typeof(CS.UnityEngine.UI.Image))
        tipImage.color = CS.UnityEngine.Color(0.02, 0.022, 0.028, 0.94)
        local tipRt = tipPanel:GetComponent(typeof(CS.UnityEngine.RectTransform))
        tipRt.anchorMin = CS.UnityEngine.Vector2(0, 0)
        tipRt.anchorMax = CS.UnityEngine.Vector2(0, 0)
        tipRt.pivot = CS.UnityEngine.Vector2(0, 1)
        tipRt.sizeDelta = CS.UnityEngine.Vector2(360, 190)

        local tipTextObj = CS.UnityEngine.GameObject("DamageMeterTooltipText")
        tipTextObj.transform:SetParent(tipPanel.transform, false)
        local tipText = tipTextObj:AddComponent(typeof(CS.TMPro.TextMeshProUGUI))
        if font ~= nil then
            tipText.font = font
            tipText.fontSharedMaterial = mat
        end
        tipText.fontSize = 14
        tipText.richText = true
        tipText.raycastTarget = false
        tipText.alignment = CS.TMPro.TextAlignmentOptions.TopLeft
        tipText.enableWordWrapping = false
        local tipTextRt = tipTextObj:GetComponent(typeof(CS.UnityEngine.RectTransform))
        tipTextRt.anchorMin = CS.UnityEngine.Vector2(0, 0)
        tipTextRt.anchorMax = CS.UnityEngine.Vector2(1, 1)
        tipTextRt.offsetMin = CS.UnityEngine.Vector2(10, 8)
        tipTextRt.offsetMax = CS.UnityEngine.Vector2(-10, -8)
        tipPanel:SetActive(false)

        local popupPanel = CS.UnityEngine.GameObject("DamageMeterDetailPopup")
        popupPanel.transform:SetParent(canvasObj.transform, false)
        local popupImage = popupPanel:AddComponent(typeof(CS.UnityEngine.UI.Image))
        popupImage.color = CS.UnityEngine.Color(0.02, 0.022, 0.028, 0.96)
        local popupRt = popupPanel:GetComponent(typeof(CS.UnityEngine.RectTransform))
        popupRt.anchorMin = CS.UnityEngine.Vector2(0, 0)
        popupRt.anchorMax = CS.UnityEngine.Vector2(0, 0)
        popupRt.pivot = CS.UnityEngine.Vector2(0, 1)
        popupRt.sizeDelta = CS.UnityEngine.Vector2(420, 230)
        popupRt.anchoredPosition = CS.UnityEngine.Vector2(560, 520)

        local popupTextObj = CS.UnityEngine.GameObject("DamageMeterDetailPopupText")
        popupTextObj.transform:SetParent(popupPanel.transform, false)
        local popupText = popupTextObj:AddComponent(typeof(CS.TMPro.TextMeshProUGUI))
        if font ~= nil then
            popupText.font = font
            popupText.fontSharedMaterial = mat
        end
        popupText.fontSize = 14
        popupText.richText = true
        popupText.raycastTarget = false
        popupText.alignment = CS.TMPro.TextAlignmentOptions.TopLeft
        popupText.enableWordWrapping = false
        local popupTextRt = popupTextObj:GetComponent(typeof(CS.UnityEngine.RectTransform))
        popupTextRt.anchorMin = CS.UnityEngine.Vector2(0, 0)
        popupTextRt.anchorMax = CS.UnityEngine.Vector2(1, 1)
        popupTextRt.offsetMin = CS.UnityEngine.Vector2(12, 10)
        popupTextRt.offsetMax = CS.UnityEngine.Vector2(-12, -10)
        popupPanel:SetActive(false)

        CS.UnityEngine.Object.DontDestroyOnLoad(canvasObj)
        DM.canvas = canvasObj
        DM.panel = panel
        DM.rowBarParent = barParent
        DM.text = text
        DM.tooltipPanel = tipPanel
        DM.tooltipText = tipText
        DM.detailPopupPanel = popupPanel
        DM.detailPopupText = popupText
    end)
end

local function refresh_ui()
    init_ui()
    if ensure_fight_identity ~= nil then
        pcall(ensure_fight_identity, "refresh")
    end
    local shouldShow = DM.visible and is_fight_active()
    if DM.panel ~= nil then
        DM.panel:SetActive(shouldShow)
    end
    if not shouldShow and hide_tooltip ~= nil then
        hide_tooltip()
        if hide_detail_popup ~= nil then hide_detail_popup() end
        hide_row_bars()
    end
    if shouldShow and DM.text ~= nil then
        DM.text.text = build_compact_lines()
        pcall(function() DM.text:ForceMeshUpdate() end)
        pcall(update_row_bars)
        pcall(function()
            if update_detail_bounds ~= nil then update_detail_bounds() end
        end)
        if DM.detailPopupPanel ~= nil and DM.detailPopupText ~= nil and DM.detailPopupStatId ~= nil then
            local stat = DM.stats[DM.detailPopupStatId]
            if stat ~= nil then
                local detailText, detailLines = stat_detail_text(stat)
                DM.detailPopupText.text = detailText
                resize_detail_panel(DM.detailPopupPanel, detailLines, 420, 230)
                pcall(function() DM.detailPopupText:ForceMeshUpdate() end)
            end
        end
    end
end

resize_detail_panel = function(panel, lineCount, width, minHeight)
    if panel == nil then return end
    local rt = panel:GetComponent(typeof(CS.UnityEngine.RectTransform))
    if rt == nil then return end
    local screenW, screenH = screen_size()
    local lineH = 17
    local padding = 28
    local h = math.max(minHeight or 190, padding + (tonumber(lineCount) or 1) * lineH)
    h = math.min(h, math.max(120, screenH - 24))
    rt.sizeDelta = CS.UnityEngine.Vector2(width or 420, h)
end
stat_detail_text = function(stat)
    if stat == nil then return "没有可显示的详情", 1 end
    local total = tonumber(stat.battle) or 0
    local rows = {}
    for label, value in pairs(stat.details or {}) do
        local amount = tonumber(value) or 0
        if amount > 0 then
            table.insert(rows, { label = label, amount = amount })
        end
    end
    table.sort(rows, function(a, b)
        if a.amount ~= b.amount then return a.amount > b.amount end
        return tostring(a.label) < tostring(b.label)
    end)

    local name = escape_rich_text(stat.name or stat.id or "未知单位")
    if stat.dead then name = name .. " <color=#FF7B72>(倒)</color>" end
    local lines = {}
    table.insert(lines, "<b>" .. name .. "</b>")
    table.insert(lines, "<color=#9AA4B2>本场总伤害：" .. tostring(total) .. "</color>")
    table.insert(lines, "<color=#9AA4B2><pos=0>来源<pos=260>伤害<pos=330>占比</color>")
    if #rows == 0 then
        table.insert(lines, "<pos=0>当前还没有记录到来源明细")
    else
        for _, row in ipairs(rows) do
            table.insert(lines, string.format(
                "<pos=0>%s<pos=260><color=#FFD166>%d</color><pos=330>%s",
                short_name(row.label, 18),
                row.amount,
                pct(row.amount, total)
            ))
        end
    end
    return table.concat(lines, "\n"), #lines
end

hide_tooltip = function()
    DM.hoverStatId = nil
    if DM.tooltipPanel ~= nil then
        pcall(function() DM.tooltipPanel:SetActive(false) end)
    end
end

hide_detail_popup = function()
    DM.detailPopupStatId = nil
    DM.detailPopupDragging = false
    DM.detailPopupDragOffset = nil
    if DM.detailPopupPanel ~= nil then
        pcall(function() DM.detailPopupPanel:SetActive(false) end)
    end
end

local function popup_rect()
    if DM.detailPopupPanel == nil then return nil end
    local rt = DM.detailPopupPanel:GetComponent(typeof(CS.UnityEngine.RectTransform))
    if rt == nil then return nil end
    local pos = rt.anchoredPosition
    local size = rt.sizeDelta
    local x = tonumber(pos.x) or 0
    local top = tonumber(pos.y) or 0
    local w = tonumber(size.x) or 420
    local h = tonumber(size.y) or 230
    return { x = x, yTop = top, w = w, h = h }
end

local function point_in_popup(mousePos, headerOnly)
    local rect = popup_rect()
    if rect == nil or mousePos == nil then return false end
    local x = tonumber(mousePos.x) or 0
    local y = tonumber(mousePos.y) or 0
    local bottom = rect.yTop - rect.h
    local headerBottom = rect.yTop - 34
    if x < rect.x or x > rect.x + rect.w then return false end
    if headerOnly then return y <= rect.yTop and y >= headerBottom end
    return y <= rect.yTop and y >= bottom
end

local function show_detail_popup(stat, mousePos)
    if stat == nil or DM.detailPopupPanel == nil or DM.detailPopupText == nil then return end
    DM.detailPopupStatId = stat.id
    local detailText, detailLines = stat_detail_text(stat)
    DM.detailPopupText.text = detailText
    resize_detail_panel(DM.detailPopupPanel, detailLines, 420, 230)
    pcall(function() DM.detailPopupText:ForceMeshUpdate() end)
    local rt = DM.detailPopupPanel:GetComponent(typeof(CS.UnityEngine.RectTransform))
    if rt ~= nil and mousePos ~= nil then
        local screenW, screenH = screen_size()
        local size = rt.sizeDelta
        local w = tonumber(size.x) or 420
        local h = tonumber(size.y) or 230
        local x = clamp((tonumber(mousePos.x) or 0) + 22, 8, math.max(8, screenW - w - 8))
        local y = clamp((tonumber(mousePos.y) or 0) + h * 0.5, h + 8, math.max(h + 8, screenH - 8))
        rt.anchoredPosition = CS.UnityEngine.Vector2(x, y)
    end
    pcall(function() DM.detailPopupPanel:SetActive(true) end)
end

local function update_detail_popup_drag()
    if DM.detailPopupPanel == nil then return end
    local active = false
    pcall(function() active = DM.detailPopupPanel.activeSelf end)
    if not active then
        DM.detailPopupDragging = false
        DM.detailPopupDragOffset = nil
        return
    end
    local mousePos = mouse_position()
    if mousePos == nil then return end
    if mouse_pressed(0) and point_in_popup(mousePos, true) then
        local rt = DM.detailPopupPanel:GetComponent(typeof(CS.UnityEngine.RectTransform))
        if rt ~= nil then
            local pos = rt.anchoredPosition
            DM.detailPopupDragging = true
            DM.detailPopupDragOffset = CS.UnityEngine.Vector2((tonumber(pos.x) or 0) - (tonumber(mousePos.x) or 0), (tonumber(pos.y) or 0) - (tonumber(mousePos.y) or 0))
        end
    end
    if not mouse_down(0) then
        DM.detailPopupDragging = false
        DM.detailPopupDragOffset = nil
        return
    end
    if DM.detailPopupDragging and DM.detailPopupDragOffset ~= nil then
        local rt = DM.detailPopupPanel:GetComponent(typeof(CS.UnityEngine.RectTransform))
        if rt ~= nil then
            local screenW, screenH = screen_size()
            local size = rt.sizeDelta
            local w = tonumber(size.x) or 420
            local h = tonumber(size.y) or 230
            local x = clamp((tonumber(mousePos.x) or 0) + (tonumber(DM.detailPopupDragOffset.x) or 0), 8, math.max(8, screenW - w - 8))
            local y = clamp((tonumber(mousePos.y) or 0) + (tonumber(DM.detailPopupDragOffset.y) or 0), h + 8, math.max(h + 8, screenH - 8))
            rt.anchoredPosition = CS.UnityEngine.Vector2(x, y)
        end
    end
end

clamp = function(value, minValue, maxValue)
    value = tonumber(value) or minValue
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

screen_size = function()
    local screenW, screenH = 1920, 1080
    pcall(function()
        screenW = tonumber(CS.UnityEngine.Screen.width) or screenW
        screenH = tonumber(CS.UnityEngine.Screen.height) or screenH
    end)
    return screenW, screenH
end

local function world_to_screen(pos)
    local screen = nil
    local ok = pcall(function()
        screen = CS.UnityEngine.RectTransformUtility.WorldToScreenPoint(nil, pos)
    end)
    if ok and screen ~= nil then return screen end
    return pos
end

local function link_id_from_index(index)
    if index == nil or index < 0 or DM.text == nil or DM.text.textInfo == nil then return nil end
    local linkInfo = DM.text.textInfo.linkInfo
    if linkInfo == nil then return nil end
    local info = nil
    local ok = pcall(function() info = linkInfo[index] end)
    if not ok or info == nil then
        pcall(function() info = linkInfo:get_Item(index) end)
    end
    if info == nil then return nil end
    local id = nil
    ok = pcall(function() id = info:GetLinkID() end)
    if ok and id ~= nil then return tostring(id) end
    id = safe_prop(info, "linkId") or safe_prop(info, "LinkId")
    if id ~= nil then return tostring(id) end
    return nil
end

update_detail_bounds = function()
    DM.detailBounds = {}
    if DM.text == nil or DM.text.textInfo == nil then return end

    local textInfo = DM.text.textInfo
    local linkCount = tonumber(safe_prop(textInfo, "linkCount")) or 0
    local linkInfo = textInfo.linkInfo
    local charInfo = textInfo.characterInfo
    if linkInfo == nil or charInfo == nil or linkCount <= 0 then return end

    local tr = DM.text.transform
    for i = 0, linkCount - 1 do
        local info = nil
        local ok = pcall(function() info = linkInfo[i] end)
        if not ok or info == nil then pcall(function() info = linkInfo:get_Item(i) end) end
        if info ~= nil then
            local linkId = link_id_from_index(i)
            local statId = linkId ~= nil and DM.linkToStat[linkId] or nil
            local first = tonumber(safe_prop(info, "linkTextfirstCharacterIndex")) or 0
            local length = tonumber(safe_prop(info, "linkTextLength")) or 0
            local minX, minY, maxX, maxY = 999999, 999999, -999999, -999999
            for j = 0, length - 1 do
                local ci = nil
                local charIndex = first + j
                ok = pcall(function() ci = charInfo[charIndex] end)
                if not ok or ci == nil then pcall(function() ci = charInfo:get_Item(charIndex) end) end
                if ci ~= nil then
                    local bl = safe_prop(ci, "bottomLeft")
                    local trc = safe_prop(ci, "topRight")
                    if bl ~= nil and trc ~= nil and tr ~= nil then
                        local w1 = world_to_screen(tr:TransformPoint(bl))
                        local w2 = world_to_screen(tr:TransformPoint(trc))
                        minX = math.min(minX, tonumber(w1.x) or minX, tonumber(w2.x) or minX)
                        minY = math.min(minY, tonumber(w1.y) or minY, tonumber(w2.y) or minY)
                        maxX = math.max(maxX, tonumber(w1.x) or maxX, tonumber(w2.x) or maxX)
                        maxY = math.max(maxY, tonumber(w1.y) or maxY, tonumber(w2.y) or maxY)
                    end
                end
            end
            if statId ~= nil and maxX > minX and maxY > minY then
                table.insert(DM.detailBounds, {
                    statId = statId,
                    x1 = minX - 6,
                    y1 = minY - 4,
                    x2 = maxX + 6,
                    y2 = maxY + 4
                })
            end
        end
    end
end

local function manual_detail_hit(mousePos)
    if mousePos == nil or DM.panel == nil or DM.detailRows == nil then return nil end

    local x = tonumber(mousePos.x) or 0
    local y = tonumber(mousePos.y) or 0
    for _, bound in ipairs(DM.detailBounds or {}) do
        if x >= bound.x1 and x <= bound.x2 and y >= bound.y1 and y <= bound.y2 then
            return DM.stats[bound.statId]
        end
    end

    local screenW, screenH = screen_size()
    local left, top, width = 16, screenH - 388, 520
    pcall(function()
        local rt = DM.panel:GetComponent(typeof(CS.UnityEngine.RectTransform))
        if rt ~= nil then
            local pos = rt.anchoredPosition
            local size = rt.sizeDelta
            left = tonumber(pos.x) or left
            top = screenH + (tonumber(pos.y) or -388)
            width = tonumber(size.x) or width
        end
    end)

    local detailLeft = left + 390
    local detailRight = left + 450
    if x < detailLeft or x > detailRight then return nil end

    local rowOffset = top - y
    local firstRowOffset = 30
    local rowHeight = 18
    if rowOffset < firstRowOffset then return nil end

    local rowIndex = math.floor((rowOffset - firstRowOffset) / rowHeight) + 1
    local statId = DM.detailRows[rowIndex]
    if statId == nil then return nil end
    return DM.stats[statId]
end

local function detail_stat_at_mouse(mousePos)
    if mousePos == nil or DM.text == nil then return nil end
    local stat = nil
    local linkIndex = -1
    local ok = pcall(function()
        linkIndex = CS.TMPro.TMP_TextUtilities.FindIntersectingLink(DM.text, mousePos, nil)
    end)
    if ok and linkIndex ~= nil and linkIndex >= 0 then
        local linkId = link_id_from_index(linkIndex)
        local statId = linkId ~= nil and DM.linkToStat[linkId] or nil
        stat = statId ~= nil and DM.stats[statId] or nil
    end
    if stat == nil then stat = manual_detail_hit(mousePos) end
    return stat
end

local function update_detail_hover()
    if not DM.visible or DM.text == nil or DM.tooltipPanel == nil or DM.tooltipText == nil then
        hide_tooltip()
        return
    end

    local mousePos = mouse_position()
    if mousePos == nil then
        hide_tooltip()
        return
    end

    local stat = detail_stat_at_mouse(mousePos)
    if stat == nil then
        hide_tooltip()
        return
    end

    DM.hoverStatId = stat.id
    local detailText, detailLines = stat_detail_text(stat)
    DM.tooltipText.text = detailText
    resize_detail_panel(DM.tooltipPanel, detailLines, 360, 190)
    pcall(function() DM.tooltipText:ForceMeshUpdate() end)
    local rt = DM.tooltipPanel:GetComponent(typeof(CS.UnityEngine.RectTransform))
    if rt ~= nil then
        local x = tonumber(mousePos.x) or 0
        local y = tonumber(mousePos.y) or 0
        local screenW, screenH = screen_size()
        local size = rt.sizeDelta
        local tipW = tonumber(size.x) or 360
        local tipH = tonumber(size.y) or 190
        local px = clamp(x + 18, 8, math.max(8, screenW - tipW - 8))
        local py = clamp(y - 18, tipH + 8, math.max(tipH + 8, screenH - 8))
        rt.anchoredPosition = CS.UnityEngine.Vector2(px, py)
    end
    pcall(function() DM.tooltipPanel:SetActive(true) end)
end

local function check_detail_click()
    if not DM.visible or DM.text == nil then return end
    local frame = current_frame()
    if frame == DM.lastClickFrame then return end
    if not mouse_pressed(0) then return end
    local mousePos = mouse_position()
    local stat = detail_stat_at_mouse(mousePos)
    if stat == nil then return end
    DM.lastClickFrame = frame
    show_detail_popup(stat, mousePos)
end

local function reset_round()
    DM.roundIndex = DM.roundIndex + 1
    for _, stat in pairs(DM.stats) do
        stat.current = 0
    end
end

local function reset_round_once(reason)
    local frame = current_frame()
    if DM.lastRoundResetFrame ~= nil and DM.lastRoundResetFrame >= 0 and frame >= 0 and frame - DM.lastRoundResetFrame < 10 then return false end
    local newFight = false
    if ensure_fight_identity ~= nil then
        local ok, value = pcall(ensure_fight_identity, reason or "round")
        newFight = ok and value == true
    end
    if newFight or DM.justResetFight then
        DM.justResetFight = false
        DM.roundStartHandled = true
        DM.lastRoundResetFrame = frame
        return false
    end
    reset_round()
    DM.roundStartHandled = true
    DM.lastRoundResetFrame = frame
    return true
end

local function reset_fight()
    DM.fightIndex = DM.fightIndex + 1
    DM.roundIndex = 1
    DM.statusById = {}
    DM.buffOwners = {}
    DM.buffObjectOwners = {}
    DM.buffStacks = {}
    DM.scriptContextStack = {}
    DM.fightSignature = nil
    DM.fightEnemySet = {}
    DM.justResetFight = true
    DM.roundStartHandled = false
    DM.friendSlots = {}
    DM.nextFriendSlot = 1
    if hide_detail_popup ~= nil then hide_detail_popup() end
    for _, stat in pairs(DM.stats) do
        stat.current = 0
        stat.battle = 0
        stat.details = {}
    end
end

-- Optional bridge for the standalone DamageMeterTraining mod.
-- This deliberately clears only per-fight statistics; the friendly
-- whole-run total remains intact.
_G.DamageMeterTrainingResetStats = function()
    reset_fight()
    DM.justResetFight = false
    pcall(all_known_statuses)
    pcall(refresh_ui)
    return true
end

_G.DamageMeterTrainingToggleWindow = function()
    DM.visible = not DM.visible
    pcall(refresh_ui)
    return DM.visible
end

local function enemy_id_set(ids)
    local set = {}
    for _, id in ipairs(ids or {}) do
        set[id] = true
    end
    return set
end

local function enemy_sets_overlap(oldSet, newIds)
    if oldSet == nil or newIds == nil then return false end
    for _, id in ipairs(newIds) do
        if oldSet[id] then return true end
    end
    return false
end

local function current_fight_signature()
    local playerId = "player"
    pcall(function()
        local fp = CS.FightPlayer.Instance
        if fp ~= nil and fp.Status ~= nil then
            playerId = status_id(fp.Status) or playerId
        end
    end)

    local ids = {}
    pcall(function()
        local enemies = CS.EnemyManager.Instance.enemyList
        foreach_collection(enemies, function(enemy)
            local status = safe_prop(enemy, "Status") or safe_prop(enemy, "status")
            local id = status_id(status)
            if id ~= nil then
                local name = status_name(status, id)
                local maxHp = tostring(tonumber(safe_prop(status, "MaxHp")) or "")
                table.insert(ids, id .. "@" .. tostring(status) .. ":" .. tostring(name) .. ":" .. maxHp)
            end
        end)
    end)
    table.sort(ids)
    if #ids == 0 then return nil, ids end
    return tostring(playerId) .. "|" .. table.concat(ids, ","), ids
end

ensure_fight_identity = function(reason)
    local signature, ids = current_fight_signature()
    if signature == nil then return false end

    if DM.fightSignature == nil then
        DM.fightSignature = signature
        DM.fightEnemySet = enemy_id_set(ids)
        return false
    end

    if signature == DM.fightSignature then return false end

    if not enemy_sets_overlap(DM.fightEnemySet, ids) then
        reset_fight()
        DM.fightSignature = signature
        DM.fightEnemySet = enemy_id_set(ids)
        log("new fight detected by " .. tostring(reason))
        return true
    end

    DM.fightSignature = signature
    DM.fightEnemySet = enemy_id_set(ids)
    return false
end

local function check_hotkey()
    local frame = current_frame()
    if frame == DM.lastKeyFrame then return end
    DM.lastKeyFrame = frame
    if key_was_pressed(DM.hotkeyName or "F8") then
        DM.visible = not DM.visible
        refresh_ui()
    end
end

local function update_live_ui()
    local frame = -1
    pcall(function() frame = CS.UnityEngine.Time.frameCount end)
    if frame == DM.lastUiFrame then return end
    DM.lastUiFrame = frame
    if DM.visible and DM.text ~= nil then
        refresh_ui()
    end
end

local function is_fight_active()
    local active = false
    pcall(function()
        local fight = CS.FightManager.Instance
        local fightType = fight ~= nil and fight.fightType or nil
        active = fight ~= nil and fightType ~= nil and tostring(fightType) ~= "None"
    end)
    return active
end

local function before_hit(status, val, damageType, fromDataId, fromInstanceId)
    if ensure_fight_identity ~= nil then
        pcall(ensure_fight_identity, "hit")
    end
    local ctx = current_script_context()
    local rawSource = ctx ~= nil and ctx.source or nil
    local rawSourceId = fromInstanceId ~= nil and tostring(fromInstanceId) or (ctx ~= nil and ctx.sourceId or nil)
    rawSource, rawSourceId = resolve_source_fallback(rawSource, rawSourceId)
    DM.lastHitSnapshot = {
        target = status_snapshot(status),
        fromId = rawSourceId,
        dataId = fromDataId ~= nil and tostring(fromDataId) or (ctx ~= nil and ctx.dataId or nil)
    }
end

local function after_hit(status, val, damageType, fromDataId, fromInstanceId)
    local snap = DM.lastHitSnapshot
    DM.lastHitSnapshot = nil
    if snap == nil or snap.target == nil then return end
    local amount = snapshot_loss(snap.target)
    if inside_damage_snapshot() then return end
    local sourceId = fromInstanceId ~= nil and tostring(fromInstanceId) or snap.fromId
    local dataId = fromDataId ~= nil and tostring(fromDataId) or snap.dataId
    local detailLabel = source_label(dataId)
    local ownerId = buff_owner_id(snap.target.status, dataId)
    if ownerId ~= nil then
        sourceId = ownerId
        detailLabel = source_label(dataId, "BUFF")
    end
    local source = fight_status_by_id(sourceId)
    source, sourceId = resolve_source_fallback(source, sourceId)
    if ownerId ~= nil then
        add_damage_split_by_buff(snap.target.status, dataId, amount, source, sourceId, detailLabel)
    else
        add_damage(source, sourceId, amount, snap.target.status, detailLabel)
    end
    if DM.changeHpHitTargets ~= nil and snap.target.id ~= nil and amount > 0 then
        DM.changeHpHitTargets[snap.target.id] = true
    end
    refresh_ui()
end

local function snapshot_targets(exe)
    local snaps = {}
    foreach_collection(safe_prop(exe, "Object"), function(status)
        local snap = status_snapshot(status)
        if snap ~= nil and snap.id ~= nil then snaps[snap.id] = snap end
    end)
    local selfSnap = status_snapshot(safe_prop(exe, "Self"))
    if selfSnap ~= nil and selfSnap.id ~= nil and snaps[selfSnap.id] == nil then
        snaps[selfSnap.id] = selfSnap
    end
    return snaps
end

local function inside_damage_snapshot()
    local stack = DM.damageSnapshotStack or {}
    return #stack > 0
end

local function before_damage(exe, amount)
    if ensure_fight_identity ~= nil then
        pcall(ensure_fight_identity, "damage")
    end
    local ctx = source_context_from_executor(exe)
    DM.damageSnapshotStack = DM.damageSnapshotStack or {}
    table.insert(DM.damageSnapshotStack, {
        source = ctx.source or safe_prop(exe, "Self"),
        sourceId = ctx.sourceId,
        dataId = ctx.dataId,
        targets = snapshot_targets(exe)
    })
end

local function after_damage(exe, amount)
    local stack = DM.damageSnapshotStack or {}
    local snap = stack[#stack]
    if #stack > 0 then table.remove(stack) end
    if snap == nil then return end
    local source = snap.source or safe_prop(exe, "Self")
    foreach_collection(safe_prop(exe, "Object"), function(status)
        local id = status_id(status)
        local old = id ~= nil and snap.targets[id] or nil
        if old ~= nil then
            local loss = snapshot_loss(old)
            if loss > 0 then
                local sourceId = snap.sourceId or status_id(source)
                local detailLabel = source_label(snap.dataId)
                local ownerId = buff_owner_id(status, snap.dataId)
                if ownerId ~= nil then
                    sourceId = ownerId
                    detailLabel = source_label(snap.dataId, "BUFF")
                end
                local sourceStatus = source
                if sourceId ~= nil then sourceStatus = fight_status_by_id(sourceId) or source end
                sourceStatus, sourceId = resolve_source_fallback(sourceStatus, sourceId)
                if ownerId ~= nil then
                    add_damage_split_by_buff(status, snap.dataId, loss, sourceStatus, sourceId, detailLabel)
                else
                    add_damage(sourceStatus, sourceId, loss, status, detailLabel)
                end
            end
        end
    end)
    refresh_ui()
end

local function before_change_hp(exe, amount)
    if ensure_fight_identity ~= nil then
        pcall(ensure_fight_identity, "change_hp")
    end
    if (tonumber(amount) or 0) >= 0 then
        DM.changeHpSnapshot = nil
        return
    end
    DM.changeHpHitTargets = {}
    local ctx = source_context_from_executor(exe)
    DM.changeHpSnapshot = {
        source = ctx.source or safe_prop(exe, "Self"),
        sourceId = ctx.sourceId,
        dataId = ctx.dataId,
        targets = snapshot_targets(exe)
    }
end

local function after_change_hp(exe, amount)
    local snap = DM.changeHpSnapshot
    DM.changeHpSnapshot = nil
    if snap == nil or (tonumber(amount) or 0) >= 0 then return end
    local source = snap.source or safe_prop(exe, "Self")
    foreach_collection(safe_prop(exe, "Object"), function(status)
        local id = status_id(status)
        local old = id ~= nil and snap.targets[id] or nil
        if old ~= nil and not DM.changeHpHitTargets[id] then
            local sourceId = snap.sourceId or status_id(source)
            local detailLabel = source_label(snap.dataId)
            local ownerId = buff_owner_id(status, snap.dataId)
            if ownerId ~= nil then
                sourceId = ownerId
                detailLabel = source_label(snap.dataId, "BUFF")
            end
            local sourceStatus = source
            if sourceId ~= nil then sourceStatus = fight_status_by_id(sourceId) or source end
            sourceStatus, sourceId = resolve_source_fallback(sourceStatus, sourceId)
            if ownerId ~= nil then
                add_damage_split_by_buff(status, snap.dataId, snapshot_loss(old), sourceStatus, sourceId, detailLabel)
            else
                add_damage(sourceStatus, sourceId, snapshot_loss(old), status, detailLabel)
            end
        end
    end)
    refresh_ui()
end

local function before_add_buff(exe, buffId, level)
    if ensure_fight_identity ~= nil then
        pcall(ensure_fight_identity, "add_buff")
    end
    if (tonumber(level) or 0) <= 0 then
        DM.addBuffSnapshot = nil
        return
    end
    local ctx = source_context_from_executor(exe)
    local source = ctx.source or safe_prop(exe, "Self")
    local targets = {}
    foreach_collection(safe_prop(exe, "Object"), function(status)
        local id = status_id(status)
        if id ~= nil then targets[id] = { status = status, level = buff_level(status, buffId) or 0 } end
    end)
    local selfStatus = safe_prop(exe, "Self")
    local selfId = status_id(selfStatus)
    if selfId ~= nil and targets[selfId] == nil then
        targets[selfId] = { status = selfStatus, level = buff_level(selfStatus, buffId) or 0 }
    end
    local sourceId = nil
    source, sourceId = resolve_source_fallback(source, ctx.sourceId or status_id(source))
    DM.addBuffSnapshot = {
        buffId = tostring(buffId or ""),
        source = source,
        sourceId = sourceId,
        targets = targets
    }
end

local function after_add_buff(exe, buffId, level)
    local snap = DM.addBuffSnapshot
    DM.addBuffSnapshot = nil
    if snap == nil or snap.buffId == "" or (tonumber(level) or 0) <= 0 then return end
    local source = snap.source or safe_prop(exe, "Self")
    local sourceId = snap.sourceId or status_id(source)
    source, sourceId = resolve_source_fallback(source, sourceId)
    local function visit(status)
        local id = status_id(status)
        if id == nil then return end
        local before = snap.targets[id] ~= nil and snap.targets[id].level or 0
        local after = buff_level(status, snap.buffId)
        if after ~= nil and after > before then
            add_buff_stack_owner(status, snap.buffId, source, sourceId, after - before)
        end
    end
    foreach_collection(safe_prop(exe, "Object"), visit)
    visit(safe_prop(exe, "Self"))
end

local function before_status_add_buff(status, buffConfig, level)
    if ensure_fight_identity ~= nil then
        pcall(ensure_fight_identity, "status_add_buff")
    end
    local buffId = buff_id_from_value(buffConfig)
    if buffId == nil then return end
    local before = buff_level(status, buffId) or 0
    local ctx = current_script_context()
    local source = ctx ~= nil and ctx.source or nil
    local sourceId = ctx ~= nil and ctx.sourceId or nil
    source, sourceId = resolve_source_fallback(source, sourceId)
    DM.statusAddBuffSnapshot = {
        buffId = buffId,
        source = source,
        sourceId = sourceId,
        targets = {
            [status_id(status) or ""] = { status = status, level = before }
        }
    }
end

local function after_status_add_buff(status, buffConfig, level)
    local snap = DM.statusAddBuffSnapshot
    DM.statusAddBuffSnapshot = nil
    local buffId = buff_id_from_value(buffConfig)
    if snap == nil or buffId == nil or snap.buffId ~= buffId then return end
    local before = 0
    local id = status_id(status) or ""
    if snap.targets[id] ~= nil then before = snap.targets[id].level or 0 end
    local after = buff_level(status, buffId)
    if after ~= nil and after > before then
        local source, sourceId = resolve_source_fallback(snap.source, snap.sourceId)
        add_buff_stack_owner(status, buffId, source, sourceId, after - before)
    end
end

local function before_script_run(exe, scriptName)
    DM.lastExecutor = exe
    push_script_context(exe)
end

local function after_script_run(exe, scriptName)
    pop_script_context()
end

local function before_buff_item_run(buffItem)
    local cfg = safe_prop(buffItem, "buffConfig")
    local status = safe_prop(buffItem, "status") or safe_prop(cfg, "Status")
    local buffId = buff_id_from_value(buffItem)
    local ownerId = buff_owner_id(status, buffId) or DM.buffObjectOwners[tostring(buffItem)] or (cfg ~= nil and DM.buffObjectOwners[tostring(cfg)] or nil)
    local source = ownerId ~= nil and DM.statusById[ownerId] or status
    if ownerId ~= nil then remember_id(ownerId) end
    if status ~= nil and buffId ~= nil and ownerId ~= nil then
        set_buff_owner(status, buffId, source, ownerId)
    end
    DM.scriptContextStack = DM.scriptContextStack or {}
    table.insert(DM.scriptContextStack, {
        source = source,
        sourceId = ownerId or status_id(source),
        dataId = buffId
    })
end

local function after_buff_item_run(buffItem)
    pop_script_context()
end

local function force_new_fight(reason)
    reset_fight()
    if ensure_fight_identity ~= nil then
        pcall(ensure_fight_identity, reason)
    end
    all_known_statuses()
    refresh_ui()
end

local function should_reset_round_event(eventName)
    eventName = tostring(eventName or "")
    if eventName == "StartRound" or eventName == "StartRoundEnd" then return true end
    if eventName == "RoundStart" or eventName == "PlayerTurn" or eventName == "PlayerTurnStart" then return true end
    return false
end

local function on_round_start(reason)
    reset_round_once(reason)
    all_known_statuses()
    refresh_ui()
end

local function on_event_trigger(exe, eventName)
    check_hotkey()
    eventName = tostring(eventName or "")
    if eventName == "FightStart" then
        force_new_fight("fight_start")
    elseif should_reset_round_event(eventName) then
        on_round_start("event_" .. eventName)
    elseif eventName == "EndRound" then
        DM.roundStartHandled = false
        all_known_statuses()
        refresh_ui()
    elseif eventName == "Win" or eventName == "Escape" then
        DM.roundStartHandled = false
        refresh_ui()
    end
end

function ModConfig:Setup()
    pcall(function() DM.modDir = self.DirectoryName end)
    pcall(load_hotkey_config)
    log("loaded")
    refresh_ui()

    pcall(function()
        self:AddMethodHookBefore("StatusManager.Hit", function(status, val, damageType, fromDataId, fromInstanceId)
            pcall(before_hit, status, val, damageType, fromDataId, fromInstanceId)
        end)
        self:AddMethodHookAfter("StatusManager.Hit", function(status, val, damageType, fromDataId, fromInstanceId)
            pcall(after_hit, status, val, damageType, fromDataId, fromInstanceId)
        end)
    end)

    pcall(function()
        self:AddMethodHookBefore("ScriptExecutor.Damage", function(exe, amount)
            pcall(before_damage, exe, amount)
        end)
        self:AddMethodHookAfter("ScriptExecutor.Damage", function(exe, amount)
            pcall(after_damage, exe, amount)
        end)
    end)

    pcall(function()
        self:AddMethodHookBefore("ScriptExecutor.ChangeHp", function(exe, amount)
            pcall(before_change_hp, exe, amount)
        end)
        self:AddMethodHookAfter("ScriptExecutor.ChangeHp", function(exe, amount)
            pcall(after_change_hp, exe, amount)
        end)
        self:AddMethodHookBefore("ScriptExecutor.PureChangeHp", function(exe, amount)
            pcall(before_change_hp, exe, amount)
        end)
        self:AddMethodHookAfter("ScriptExecutor.PureChangeHp", function(exe, amount)
            pcall(after_change_hp, exe, amount)
        end)
    end)

    pcall(function()
        self:AddMethodHookBefore("ScriptExecutor.AddBuff", function(exe, buffId, level)
            pcall(before_add_buff, exe, buffId, level)
        end)
        self:AddMethodHookAfter("ScriptExecutor.AddBuff", function(exe, buffId, level)
            pcall(after_add_buff, exe, buffId, level)
        end)
    end)

    pcall(function()
        self:AddMethodHookBefore("StatusManager.AddBuff", function(status, buffConfig, level)
            pcall(before_status_add_buff, status, buffConfig, level)
        end)
        self:AddMethodHookAfter("StatusManager.AddBuff", function(status, buffConfig, level)
            pcall(after_status_add_buff, status, buffConfig, level)
        end)
    end)

    pcall(function()
        self:AddMethodHookBefore("ScriptExecutor.RunScript", function(exe, scriptName)
            pcall(before_script_run, exe, scriptName)
        end)
        self:AddMethodHookAfter("ScriptExecutor.RunScript", function(exe, scriptName)
            pcall(after_script_run, exe, scriptName)
        end)
        self:AddMethodHookBefore("ScriptExecutor.EventTrigger", function(exe, eventName)
            pcall(before_script_run, exe, eventName)
        end)
        self:AddMethodHookAfter("ScriptExecutor.EventTrigger", function(exe, eventName)
            pcall(after_script_run, exe, eventName)
        end)
    end)

    pcall(function()
        self:AddMethodHookBefore("BuffItem.ApplyBuff", function(buffItem)
            pcall(before_buff_item_run, buffItem)
        end)
        self:AddMethodHookAfter("BuffItem.ApplyBuff", function(buffItem)
            pcall(after_buff_item_run, buffItem)
        end)
        self:AddMethodHookBefore("BuffItem.BuffProcess", function(buffItem, isacting)
            pcall(before_buff_item_run, buffItem)
        end)
        self:AddMethodHookAfter("BuffItem.BuffProcess", function(buffItem, isacting)
            pcall(after_buff_item_run, buffItem)
        end)
    end)

    pcall(function()
        self:AddMethodHookAfter("ScriptExecutor.EventTrigger", function(exe, eventName)
            pcall(on_event_trigger, exe, eventName)
        end)
    end)

    local fightInitHooks = {
        "FightManager.Init",
        "FightManager.ReSetFight",
        "FightUI.Init",
        "Witch.UI.Window.FightUI.Init"
    }
    for _, name in ipairs(fightInitHooks) do
        pcall(function()
            self:AddMethodHookAfter(name, function()
                pcall(force_new_fight, name)
            end)
        end)
    end

    local roundStartHooks = {
        "Fight_PlayerTurn.Init",
        "FightPlayer.StartRound",
        "FightManager.StartRound"
    }
    for _, name in ipairs(roundStartHooks) do
        pcall(function()
            self:AddMethodHookAfter(name, function()
                pcall(on_round_start, name)
            end)
        end)
    end

    local tickHooks = {
        "UIBase.Update",
        "Witch.UI.UIBase.Update",
        "Witch.UI.Window.UIBase.Update",
        "MapSelectUI.Update",
        "Witch.UI.Window.MapSelectUI.Update",
        "ModeChoiceUI.Update",
        "Witch.UI.Window.ModeChoiceUI.Update",
        "SelectHardUI.Update",
        "Witch.UI.Window.SelectHardUI.Update",
        "BackpackUI.Update",
        "Witch.UI.Window.BackpackUI.Update",
        "DeckUI.Update",
        "Witch.UI.Window.DeckUI.Update",
        "OutDeckUI.Update",
        "Witch.UI.Window.OutDeckUI.Update",
        "EventUI.Update",
        "Witch.UI.Window.EventUI.Update",
        "CardChoiceUI.Update",
        "Witch.UI.Window.CardChoiceUI.Update",
        "CardPackUI.Update",
        "Witch.UI.Window.CardPackUI.Update",
        "BattleRewardsUI.Update",
        "Witch.UI.Window.BattleRewardsUI.Update",
        "ShopUI.Update",
        "Witch.UI.Window.ShopUI.Update",
        "MainMenuUI.Update",
        "Witch.UI.Window.MainMenuUI.Update",
        "GameEntryUI.Update",
        "Witch.UI.Window.GameEntryUI.Update",
        "TopBarUI.Update",
        "Witch.UI.Window.TopBarUI.Update",
        "FightUI.Update",
        "Witch.UI.Window.FightUI.Update",
        "PopUpTextUI.Update",
        "Witch.UI.Window.PopUpTextUI.Update",
        "FightUI.UpdatePower",
        "Witch.UI.Window.FightUI.UpdatePower",
        "FightUI.UpdateCardMsg",
        "Witch.UI.Window.FightUI.UpdateCardMsg",
        "FightUI.ResetButtonCheck",
        "Witch.UI.Window.FightUI.ResetButtonCheck"
    }
    for _, name in ipairs(tickHooks) do
        pcall(function()
            self:AddMethodHookAfter(name, function()
                pcall(check_hotkey)
                pcall(update_live_ui)
                pcall(update_detail_hover)
                pcall(check_detail_click)
                pcall(update_detail_popup_drag)
            end)
        end)
    end
end
