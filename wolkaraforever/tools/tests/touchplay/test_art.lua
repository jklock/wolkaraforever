-- R48: the non-spell buttons draw our own sharp art (addon/TouchPlay/Art, made by tools/make-art.py), not the
-- game's small icons stretched to touch size. Every Art file is referenced and every reference exists; each file is
-- a 32-bit TGA in power-of-two sizes at twice its drawn size or more; the buttons show their glyphs.
dofile("tests/stub.lua")

local ADDON = "addon/TouchPlay/"
local ART_DIR = ADDON .. "Art/"
local ART_PATH = "Interface\\AddOns\\TouchPlay\\Art\\"
local PX_PER_UNIT = 2          -- "twice the drawn size": the iPad draws about 1.6 px a unit
local CELL_PX = 256            -- a Glyphs.tga cell

local function readFile(path)
    local f = assert(io.open(path, "rb"), path)
    local s = f:read("*a")
    f:close()
    return s
end

local function list(cmd)
    local out = {}
    local p = assert(io.popen(cmd))
    for line in p:lines() do out[#out + 1] = line end
    p:close()
    return out
end

local function luaFiles()
    local files = {}
    for _, path in ipairs(list("ls " .. ADDON .. "*.lua")) do files[#files + 1] = path end
    return files
end

local function artFiles()
    local set = {}
    for _, name in ipairs(list("ls " .. ART_DIR .. " 2>/dev/null")) do set[name] = true end
    return set
end

-- The TGA header: id length, colour map, image type, then width, height, bits per pixel, descriptor.
local function tgaInfo(path)
    local s = readFile(path)
    local idLen, mapType, imageType = s:byte(1), s:byte(2), s:byte(3)
    local w = s:byte(13) + 256 * s:byte(14)
    local h = s:byte(15) + 256 * s:byte(16)
    local bpp, descriptor = s:byte(17), s:byte(18)
    return { idLen = idLen, mapType = mapType, imageType = imageType, w = w, h = h, bpp = bpp,
        alphaBits = descriptor % 16, bytes = #s }
end

local function isPowerOfTwo(n)
    if n < 1 then return false end
    while n > 1 do
        if n % 2 ~= 0 then return false end
        n = n / 2
    end
    return true
end

local function setup()
    Stub.reset(); Stub.loadAll(); Stub.login()
    assert(not ns.paused, ns.lastError)
end

-- ---------------------------------------------------------------------------------------
-- Files

T("every_art_file_is_referenced_and_every_reference_exists", function()
    local onDisk = artFiles()
    assert(next(onDisk), "Art/ holds the add-on's own art")
    local referenced = {}
    for _, path in ipairs(luaFiles()) do
        for name in readFile(path):gmatch('"([%w_%-]+%.tga)"') do referenced[name] = path end
    end
    for name, path in pairs(referenced) do
        assert(onDisk[name], path .. " names " .. name .. ", which is not in " .. ART_DIR)
    end
    for name in pairs(onDisk) do
        if name ~= "CREDITS.txt" then
            assert(name:match("%.tga$"), ART_DIR .. name .. " is not a .tga")
            assert(referenced[name], ART_DIR .. name .. " is not used by any add-on file")
        end
    end
    -- the kit's paths point into the add-on's own Art folder
    Stub.reset(); Stub.load("Core.lua", "Text.lua", "Style.lua")
    for _, key in ipairs({ "ART_RING", "ART_GLYPHS", "ART_MINIMAP" }) do
        local path = ns.Kit[key]
        assert(path:sub(1, #ART_PATH) == ART_PATH, key .. " is in Art: " .. path)
        assert(onDisk[path:sub(#ART_PATH + 1)], key .. " exists: " .. path)
    end
end)

T("art_files_are_32_bit_tga_in_power_of_two_sizes", function()
    local want = { ["Ring.tga"] = { 256, 256 }, ["Glyphs.tga"] = { 2048, 1024 }, ["Minimap.tga"] = { 512, 512 } }
    for name in pairs(artFiles()) do if name:match("%.tga$") then
        local t = tgaInfo(ART_DIR .. name)
        assert(t.mapType == 0 and t.imageType == 2, name .. ": an uncompressed true-colour TGA")
        assert(t.bpp == 32 and t.alphaBits == 8, name .. ": 32 bits with an 8-bit alpha")
        assert(isPowerOfTwo(t.w) and isPowerOfTwo(t.h), name .. ": power-of-two sizes")
        assert(t.bytes >= 18 + t.idLen + t.w * t.h * 4, name .. ": the whole image is there")
        local size = want[name]
        assert(size and t.w == size[1] and t.h == size[2], name .. " is " .. t.w .. " x " .. t.h)
    end end
end)

T("glyph_cells_match_the_art_script", function()
    Stub.reset(); Stub.load("Core.lua", "Text.lua", "Style.lua")
    local script = readFile("tools/make-art.py")
    local block = assert(script:match("GLYPHS = %[(.-)\n%]"), "make-art.py lays out GLYPHS")
    local row, seen = 0, 0
    for line in block:gmatch("%[([^%[%]]+)%]") do
        local col = 0
        for item in line:gmatch("[^,]+") do
            local name = item:match('"([%w_]+)"')
            if name then
                local cell = ns.Kit.GLYPHS[name]
                assert(cell and cell[1] == col and cell[2] == row, name .. " sits at " .. col .. ", " .. row)
                seen = seen + 1
            end
            col = col + 1
        end
        row = row + 1
    end
    local count = 0
    for _ in pairs(ns.Kit.GLYPHS) do count = count + 1 end
    assert(seen == count and count > 0, "every glyph in Style.lua is drawn by make-art.py")
end)

-- ---------------------------------------------------------------------------------------
-- No small game icons on the non-spell buttons

-- The files that draw the non-spell buttons: Bags, Menu and its tiles, the minimap ring and its small buttons,
-- Interact, Jump, Dive, Next target, the page boxes, the chat strip. None names a game icon or the old soft art.
local BUTTON_FILES = { "Style.lua", "Hud.lua", "Interact.lua", "Cluster.lua", "Menu.lua", "Chat.lua" }
-- (as written in the source: a Lua string's "\\" is two characters in the file)
local OLD_ART = { "Interface\\\\Icons\\\\", "MiniMap-TrackingBorder", "UI-Minimap-Border", "UI-Minimap-ZoomButton-Highlight",
    "GossipGossipIcon", "Button-Backpack-Up", "Arrow-Up-Up", "Arrow-Down-Up", "ReadyCheck-NotReady" }

-- The allowed exceptions: game icons that show a spell, item or mount (not a button's own picture).
--   Picker.lua  the random favourite mount's icon on a spell button
--   Loot.lua    the question mark for an item whose icon the game has not sent yet
-- (The tracking ring shows the tracked ability's icon from the game at run time: no literal.)
local ICON_EXCEPTIONS = { ["Picker.lua"] = true, ["Loot.lua"] = true }

T("no_game_icons_on_the_non_spell_buttons", function()
    for _, name in ipairs(BUTTON_FILES) do
        local src = readFile(ADDON .. name)
        for _, art in ipairs(OLD_ART) do
            assert(not src:find(art, 1, true), name .. " still names " .. art)
        end
    end
    for _, path in ipairs(luaFiles()) do
        local name = path:match("[^/]+$")
        if readFile(path):find("Interface\\\\Icons\\\\", 1, true) then
            assert(ICON_EXCEPTIONS[name], name .. " names a game icon and is not an allowed exception")
        end
    end
end)

-- ---------------------------------------------------------------------------------------
-- The buttons show our art, at twice the drawn size or more

local function glyphOf(texture) return texture.touchGlyph end

local function assertRing(face, glyph, what)
    local Kit = ns.Kit
    assert(face.ring.texture == Kit.ART_RING, what .. ": the ring is our own")
    assert(glyphOf(face.icon) == glyph, what .. " shows " .. tostring(glyph) .. ", not " .. tostring(glyphOf(face.icon)))
    local d = face:GetWidth()
    assert(math.abs(face.ring:GetWidth() - d * Kit.RING_SPAN) < 1e-6, what .. ": the ring spans 1.25 x the button")
    assert(d * Kit.RING_SPAN * PX_PER_UNIT <= 256, what .. ": Ring.tga is twice the drawn size or more")
    assert(face.icon:GetWidth() * PX_PER_UNIT <= CELL_PX, what .. ": a glyph cell is twice the drawn size or more")
    -- polish pass: the glow is the press look (lit while pressed), never a hover highlight (a touch screen has no
    -- hover; the pointer left by the last plain tap kept it lit)
    assert(face:GetHighlightTexture() == nil, what .. ": no hover highlight")
    local glow = face.touchPressLayer and face.touchPressLayer.glow
    assert(glow and glyphOf(glow) == "glow" and glow.blendMode == "ADD", what .. ": the press glow is our own")
end

T("rings_show_their_glyphs", function()
    setup()
    local Hud, Interact, Cluster = ns.Hud, ns.Interact, ns.Cluster
    assertRing(Hud.bags.face, "bag", "Bags")
    assertRing(Hud.menu.face, "menu", "Menu")
    assertRing(Hud.mail, "mail", "Mail")
    assertRing(Cluster.nextTarget.face, "cross", "Next target")
    assertRing(Interact.interact, "talk", "Interact")
    assertRing(Interact.jump, "jump", "Jump")
    assertRing(Interact.dive, "mount", "Mount (on land, R50)")
    Stub.setSwimming(true); Stub.fire("MIRROR_TIMER_START")
    assertRing(Interact.dive, "dive", "Dive")
    -- the tracking ring shows the game's own tracking icon (an allowed exception), the ring itself is ours
    assert(Hud.tracking.ring.texture == ns.Kit.ART_RING)
end)

T("interact_glyph_follows_what_it_will_do", function()
    setup()
    local Interact = ns.Interact
    local want = { talk = "talk", loot = "loot", skin = "skin", attack = "sword", open = "open", reelin = "hook",
        none = "talk", cancel = "cancel", up = "jump", down = "dive", mount = "mount" }
    local count = 0
    for key, glyph in pairs(Interact.ICONS) do
        assert(want[key] == glyph and ns.Kit.GLYPHS[glyph], key .. " shows the " .. tostring(want[key]) .. " glyph")
        count = count + 1
    end
    assert(count == 11, "every face Interact can paint has a glyph")
    -- nothing near: the talk bubble, greyed
    assert(glyphOf(Interact.interact.icon) == "talk" and Interact.interact.icon.desaturated == true)
end)

T("page_boxes_are_our_box_tinted_gold_when_lit", function()
    setup()
    local boxes = ns.Cluster.pageBoxes
    assert(#boxes == 4)
    for p, box in ipairs(boxes) do
        assert(glyphOf(box.art) == "box", "page " .. p .. " is our box")
        assert(box:GetWidth() * PX_PER_UNIT <= CELL_PX, "a cell is twice the box or more")
        local v = box.art.vertex
        if p == 1 then assert(v[1] == 1 and math.abs(v[2] - 0.82) < 1e-6 and v[3] == 0, "page 1 is lit gold")
        else assert(v[1] == 0.75 and v[2] == 0.75 and v[3] == 0.75, "page " .. p .. " is grey") end
    end
end)

T("menu_tiles_show_the_mockup_glyphs", function()
    setup()
    local want = { character = "person", spellbook = "book", talents = "star", quests = "scroll", map = "map",
        bags = "bag", professions = "hammer", social = "people", chat = "chat", editLayout = "layout",
        settings = "gear", logout = "exit" }
    for key, glyph in pairs(want) do
        local icon = ns.Menu.tiles[key].icon
        assert(glyphOf(icon) == glyph, key .. " shows " .. glyph)
        assert(icon:GetWidth() * PX_PER_UNIT <= CELL_PX, key .. ": a cell is twice the drawn size or more")
    end
end)

T("minimap_ring_is_our_own_round_the_disc", function()
    setup()
    local Hud = ns.Hud
    local art = Hud.borderArt
    assert(art.texture == ns.Kit.ART_MINIMAP)
    assert(art:GetWidth() == 256 and art:GetHeight() == 256 and 256 * PX_PER_UNIT <= 512)
    -- its top-left is 128 units left of the disc's centre (1250 - 1035 - 128 = 87 into the 330 frame)
    local point, rel, relPoint, x, y = art:GetPoint(1)
    assert(point == "TOPLEFT" and rel == Hud.border and relPoint == "TOPLEFT" and x == 87 and y == 0)
end)

-- ---------------------------------------------------------------------------------------
-- R49: the icons are game-icons.net's (CC BY 3.0): each is credited in Art/CREDITS.txt and NOTICE.md, and its
-- SVG source is kept in tools/art-src so tools/make-art.py can draw the art again.

local function iconTable()
    local script = readFile("tools/make-art.py")
    local block = assert(script:match("\nICONS = {(.-)\n}"), "make-art.py has its ICONS table")
    local icons = {}
    for glyph, author, name in block:gmatch('"([%w_]+)": %("([%w-]+)", "([%w-]+)"') do
        icons[#icons + 1] = { glyph = glyph, author = author, name = name }
    end
    return icons
end

T("every_icon_is_credited_and_its_source_kept", function()
    Stub.reset(); Stub.load("Core.lua", "Text.lua", "Style.lua")
    local icons = iconTable()
    local credits = readFile(ART_DIR .. "CREDITS.txt")
    local notice = readFile(ADDON .. "NOTICE.md")
    assert(credits:find("CC BY 3.0", 1, true) and notice:find("CC BY 3.0", 1, true))
    assert(notice:find("https://creativecommons.org/licenses/by/3.0/", 1, true), "NOTICE.md links the licence")
    local glyphs = 0
    for name in pairs(ns.Kit.GLYPHS) do
        if name ~= "glow" and name ~= "box" then glyphs = glyphs + 1 end
    end
    assert(#icons == glyphs, "every icon glyph comes from game-icons.net: " .. #icons .. " of " .. glyphs)
    for _, icon in ipairs(icons) do
        assert(ns.Kit.GLYPHS[icon.glyph], icon.glyph .. " is a glyph the add-on knows")
        local page = "https://game-icons.net/1x1/" .. icon.author .. "/" .. icon.name .. ".html"
        assert(credits:find(icon.glyph .. ': "' .. icon.name .. '" by ', 1, true), "CREDITS.txt names " .. icon.name)
        assert(credits:find(page, 1, true), "CREDITS.txt links " .. page)
        assert(notice:find("[" .. icon.name .. "](" .. page .. ")", 1, true), "NOTICE.md credits " .. icon.name)
        local src = "tools/art-src/" .. icon.author .. "/" .. icon.name .. ".svg"
        assert(readFile(src):find("<svg", 1, true), src .. " is kept")
    end
end)

Stub.done("art")
