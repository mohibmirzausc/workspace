-- Show a HUD whenever the microphone input volume changes, to find out what
-- keeps moving it.
--
-- This is a DIAGNOSTIC, not a fix. Something lowers the built-in mic's input
-- volume over time -- it was seen at 36% and later 10% in the same session --
-- and darwin.nix already records the pattern: "Krisp/Zoom/Tandem/Tuple all
-- lower it and do not restore it." Polling at 1s intervals for 90s caught
-- nothing, so the change is event-driven, not a background sweep. Hence a
-- watcher rather than a poll.
--
-- hs.audiodevice's per-device watcher emits 'vmvc' on a volume change. Note
-- that is the DEVICE watcher (dev:watcherCallback / dev:watcherStart), not
-- hs.audiodevice.watcher, which reports device add/remove instead and would
-- never fire for this.
--
-- The watcher is attached to whichever device is default at load, so it is
-- re-attached when the default input changes -- otherwise switching to a
-- headset would silently stop the diagnosis.

local M = {}

local watched = nil  -- the device currently carrying our callback
local last = nil     -- last volume seen, so the HUD can show old -> new

local function show(old, new)
  local text
  if old then
    text = string.format("mic %d%% → %d%%", math.floor(old + 0.5), math.floor(new + 0.5))
  else
    text = string.format("mic %d%%", math.floor(new + 0.5))
  end
  hs.alert.closeAll()
  hs.alert.show(text, 1.5)
end

local function onDeviceEvent(uid, event)
  if event ~= "vmvc" then return end
  local dev = hs.audiodevice.findDeviceByUID(uid)
  if not dev then return end
  local new = dev:inputVolume()
  -- inputVolume() returns nil for devices with no input gain control.
  if type(new) ~= "number" then return end
  -- The event fires for tiny float jitter too; only report a real move.
  if last and math.abs(new - last) < 1 then return end
  show(last, new)
  last = new
end

local function attach()
  local dev = hs.audiodevice.defaultInputDevice()
  if not dev then return end
  if watched and watched:uid() == dev:uid() then return end
  if watched then
    watched:watcherStop()
    watched:watcherCallback(nil)
  end
  dev:watcherCallback(onDeviceEvent)
  dev:watcherStart()
  watched = dev
  local v = dev:inputVolume()
  last = type(v) == "number" and v or nil
end

function M.start()
  attach()
  -- Re-attach when the default input device changes, so the diagnosis
  -- survives plugging in a headset or Krisp swapping the default.
  hs.audiodevice.watcher.setCallback(function() attach() end)
  hs.audiodevice.watcher.start()
end

function M.stop()
  hs.audiodevice.watcher.stop()
  if watched then
    watched:watcherStop()
    watched:watcherCallback(nil)
    watched = nil
  end
end

return M
