-- Hang up the current call with one hotkey.
--
-- Tandem, Tuple and Google Meet all expose their leave control through the
-- macOS Accessibility API, so this presses the real button rather than killing
-- the app: the call tears down cleanly and the app stays running.
--
-- Verified live twice, and the two cases differ. A Tandem ROOM exposes a real
-- AXButton titled "Leave Room" with AXPress on it. A Tandem CALL exposes an
-- AXStaticText reading "LEAVE" whose pressable element is an unlabelled
-- AXGroup four levels up. Both now resolve; pressing either left the call
-- with Tandem still running.
--
-- Two things that look like details but are not:
--
--   * The search is breadth-first. Tandem's leave button sits at depth 16 of a
--     1310-element tree; depth-first finds it in 79ms, breadth-first in 12ms
--     visiting 149 elements, because it stops as soon as it reaches that depth.
--     Chrome's tree is 7692 elements, where the difference matters far more.
--   * AppleScript cannot see any of this. `entire contents` returns zero
--     elements for every Chromium-backed app, which is why this uses the AX
--     API directly.

local M = {}

-- Ordered: whichever app is frontmost wins, so being in two calls at once
-- leaves the one being looked at. Titles are matched case-insensitively.
local TARGETS = {
  -- "leave room" is a room; bare "leave" is the in-call control (it renders
  -- as "LEAVE" but matching is case-insensitive). Both confirmed live.
  { app = "Tandem",       titles = { "leave room", "leave call", "leave" } },
  -- Tuple's titles are speculative and will probably not match. Probed during
  -- a live call: it exposes zero AX windows, its overlay is absent from the
  -- CoreGraphics window list too (so it is drawn on a private layer), and its
  -- menus hold no leave/end-call item or shortcut -- only Quit. Left in so the
  -- search is harmless if a future version exposes one; until then hangUp()
  -- falls through to the next target and Tuple must be left by hand.
  { app = "Tuple",        titles = { "leave call", "leave", "hang up", "end call" } },
  { app = "Google Chrome", titles = { "leave call", "end call", "hang up" } },
}

local MAX_NODES = 4000  -- bounded so a pathological tree cannot hang the hotkey
local MAX_DEPTH = 22

-- Breadth-first search for the leave control.
--
-- Two shapes exist and both have been seen live, so both are handled:
--
--   * A room exposes a real AXButton titled "Leave Room" with AXPress on it.
--   * A call exposes an AXStaticText reading "LEAVE" whose pressable element
--     is an unlabelled AXGroup FOUR levels up -- the intervening groups carry
--     only AXShowMenu/AXScrollToVisible.
--
-- So matching AXButton alone finds a room but silently misses a call, which is
-- what "No call to leave" meant on a call that was plainly in progress. Match
-- on the label wherever it appears, then press the nearest pressable ancestor.
local function findLeaveButton(axApp, titles)
  local want = {}
  for _, t in ipairs(titles) do want[t] = true end

  local function pressable(el)
    for _, action in ipairs(el:actionNames() or {}) do
      if action == "AXPress" then return true end
    end
    return false
  end

  local windows = axApp:attributeValue("AXWindows") or {}
  local queue, head, seen = {}, 1, 0
  for _, w in ipairs(windows) do queue[#queue + 1] = { el = w, depth = 0, chain = {} } end

  while head <= #queue and seen < MAX_NODES do
    local node = queue[head]; head = head + 1
    local el, depth, chain = node.el, node.depth, node.chain
    seen = seen + 1

    -- The label can be AXTitle (button) or AXValue (static text).
    local label = el:attributeValue("AXTitle") or el:attributeValue("AXValue")
    if type(label) == "string" then
      label = label:lower():gsub("^%s*(.-)%s*$", "%1")
      if want[label] then
        if pressable(el) then return el end
        -- Nearest pressable ancestor, closest first. Bounded at 6: the
        -- observed depth is 4 and an unbounded walk would eventually hit the
        -- window itself, which is pressable and would do the wrong thing.
        for i = #chain, math.max(1, #chain - 5), -1 do
          if pressable(chain[i]) then return chain[i] end
        end
      end
    end

    if depth < MAX_DEPTH then
      -- Copy explicitly: table.unpack is 5.2+ and Hammerspoon runs LuaJIT.
      local nextChain = {}
      for i = 1, #chain do nextChain[i] = chain[i] end
      nextChain[#nextChain + 1] = el
      for _, child in ipairs(el:attributeValue("AXChildren") or {}) do
        queue[#queue + 1] = { el = child, depth = depth + 1, chain = nextChain }
      end
    end
  end
  return nil
end

function M.hangUp()
  local frontmost = hs.application.frontmostApplication()
  local frontName = frontmost and frontmost:name()

  -- Try the frontmost app first so the visible call is the one that ends.
  local ordered = {}
  for _, t in ipairs(TARGETS) do
    if t.app == frontName then table.insert(ordered, 1, t) else ordered[#ordered + 1] = t end
  end

  for _, target in ipairs(ordered) do
    local app = hs.application.get(target.app)
    if app then
      local axApp = hs.axuielement.applicationElement(app)
      if axApp then
        -- Chromium only populates its AX tree once an assistive client asks.
        axApp:setAttributeValue("AXManualAccessibility", true)
        local button = findLeaveButton(axApp, target.titles)
        if button then
          button:performAction("AXPress")
          hs.alert.show("Left " .. target.app .. " call", 0.8)
          return
        end
      end
    end
  end

  hs.alert.show("No call to leave", 0.8)
end

-- Caps Lock is remapped to ctrl+alt+cmd in programs/karabiner.nix, so this is
-- Caps Lock+H. Karabiner passes the chord through untouched: H is bound
-- nowhere in karabiner.nix nor in any of OmniWM's 188 hotkeys.
hs.hotkey.bind({ "ctrl", "alt", "cmd" }, "h", M.hangUp)

return M
