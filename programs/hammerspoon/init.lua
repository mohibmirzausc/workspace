-- Hang up the current call with one hotkey.
--
-- Tandem and Tuple expose their leave control through the macOS Accessibility
-- API, so this presses the real button rather than killing the app: the call
-- tears down cleanly and the app stays running.
--
-- Google Meet is deliberately NOT handled, though it was and could be again.
-- Its "Leave call" is a real AXButton with real geometry but offers no
-- AXPress -- Chrome exposes none for web content, on the button or on any
-- ancestor up to the window -- so it needs a synthetic click, and that click
-- only lands under two conditions that are awkward in practice: Chrome builds
-- an AX tree for the VISIBLE TAB ONLY, so Meet in a background tab has no
-- button to find at all, and Meet's control bar auto-hides after a few
-- seconds, taking its buttons out of the tree with it. The result worked only
-- with the Meet tab foreground and freshly moused-over, which is most of the
-- work of just clicking Leave by hand.
--
-- If it is ever wanted back, the clean route is not AX at all: enabling
-- Chrome's View > Developer > Allow JavaScript from Apple Events permits
-- `document.querySelector('[aria-label="Leave call"]').click()` in any tab,
-- background included, with no window activation and no cursor movement.
-- That setting lets any app that can send Apple Events run JavaScript in
-- logged-in browser sessions, which is why it is not on here.
--
-- Verified live twice, and the two cases differ. A Tandem ROOM exposes a real
-- AXButton titled "Leave Room" with AXPress on it. A Tandem CALL exposes an
-- AXStaticText reading "LEAVE" whose pressable element is an unlabelled
-- AXGroup four levels up. Both now resolve; pressing either left the call
-- with Tandem still running.
--
-- Three things that look like details but are not:
--
--   * Tuple builds NO accessibility tree until its app is activated. Probed
--     in the background during a live call it shows zero AX windows, is
--     absent from the CoreGraphics window list, and a hit-test at the Leave
--     button's own coordinates returns the desktop behind it -- all of which
--     reads as "this app cannot be automated". Activate it and a perfectly
--     ordinary tree appears, Leave button included.
--
--   * The search is breadth-first. Tandem's leave button sits at depth 16 of a
--     1310-element tree; depth-first finds it in 79ms, breadth-first in 12ms
--     visiting 149 elements, because it stops as soon as it reaches that depth.
--     Chrome's tree is 7692 elements, where the difference matters far more.
--   * AppleScript cannot see any of this. `entire contents` returns zero
--     elements for every Chromium-backed app, which is why this uses the AX
--     API directly.

local M = {}

-- EVERY target in a call is left, not just the first one found. Being in a
-- Tandem and a Tuple call at the same time is the case this hotkey exists
-- for, and stopping at the first match left the other one running with
-- nothing to say it had been missed. The frontmost app is still tried first,
-- but only so an app already in front is not activated out from under the
-- cursor. Titles are matched case-insensitively.
local TARGETS = {
  -- "leave room" is a room; bare "leave" is the in-call control (it renders
  -- as "LEAVE" but matching is case-insensitive). Both confirmed live.
  { app = "Tandem",       titles = { "leave room", "leave call", "leave" } },
  -- Tuple only builds its AX tree once the app is ACTIVATED. While it is in
  -- the background the call panel is a menu-bar popover that exposes nothing:
  -- zero AX windows, absent from the CoreGraphics window list, and a hit-test
  -- at the Leave button's own screen coordinates returns the desktop behind
  -- it. Activate it first and a normal tree appears, with a real AXButton
  -- titled "Leave" carrying AXPress. Confirmed live: pressed it, the call
  -- ended and Tuple stayed running.
  --
  -- Tuple's own shortcut for this is Cmd-Esc, which its AX tree advertises
  -- next to the button. Pressing the button is preferred anyway: it needs no
  -- keystroke synthesis and cannot be swallowed by whatever has focus.
  { app = "Tuple",        titles = { "leave", "leave call" }, activate = true },
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

  -- Try the frontmost app first. It does not decide WHICH call ends any more
  -- -- every call found is left -- but it keeps the app being looked at from
  -- being activated out from under the cursor when it is already in front.
  local ordered = {}
  for _, t in ipairs(TARGETS) do
    if t.app == frontName then table.insert(ordered, 1, t) else ordered[#ordered + 1] = t end
  end

  local restoreTo = nil
  local left = {}

  for _, target in ipairs(ordered) do
    local app = hs.application.get(target.app)
    if app then
      -- Tuple builds no AX tree at all until it is activated, so for it the
      -- search would otherwise always come up empty. Remember what was in
      -- front so focus can be handed back if this target turns out not to be
      -- in a call.
      if target.activate and not app:isFrontmost() then
        restoreTo = restoreTo or frontmost
        app:activate()
        -- Activation is asynchronous and the tree is not there immediately.
        -- Poll rather than sleeping a fixed amount, and cap it: this blocks
        -- Hammerspoon's main thread, so the cap is the worst case the hotkey
        -- can ever hang for. Observed activation is well under 300ms.
        local deadline = hs.timer.absoluteTime() + 800 * 1e6
        repeat
          local probe = hs.axuielement.applicationElement(app)
          local windows = probe and probe:attributeValue("AXWindows")
          if windows and #windows > 0 then break end
          hs.timer.usleep(50000)
        until hs.timer.absoluteTime() > deadline
      end

      local axApp = hs.axuielement.applicationElement(app)
      if axApp then
        -- Chromium only populates its AX tree once an assistive client asks.
        axApp:setAttributeValue("AXManualAccessibility", true)
        local button = findLeaveButton(axApp, target.titles)
        if button then
          button:performAction("AXPress")
          left[#left + 1] = target.app
          -- Deliberately NOT returning: being in a Tandem and a Tuple call at
          -- once is the case this hotkey is for, and stopping at the first
          -- one left the other running with no indication it had been missed.
        end
      end
    end
  end

  -- Hand focus back either way: a call was left from a hotkey, so whatever
  -- was in front is still what should be in front.
  if restoreTo then restoreTo:activate() end

  if #left == 0 then
    hs.alert.show("No call to leave", 0.8)
  else
    hs.alert.show("Left " .. table.concat(left, " + ") .. " call", 0.8)
  end
end

-- Caps Lock is remapped to ctrl+alt+cmd in programs/karabiner.nix, so this is
-- Caps Lock+H. Karabiner passes the chord through untouched: H is bound
-- nowhere in karabiner.nix nor in any of OmniWM's 188 hotkeys.
hs.hotkey.bind({ "ctrl", "alt", "cmd" }, "h", M.hangUp)

return M
