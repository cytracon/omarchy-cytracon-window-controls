-- Compositor-side right-button drag for window-controls.
-- A hyprctl dispatch of window.drag() from Quickshell does not start an
-- interactive move while the pointer is on a layer-shell surface. A mouse
-- bind with drag=true does.

window_controls = window_controls or {}
window_controls.bar_w = 103
window_controls.bar_h = 28
window_controls.inset = 3

local function on_screen(w)
  if not w or w.mapped == false or w.hidden == true then
    return false
  end
  if w.pinned then
    return true
  end
  local ws = w.workspace
  if not ws or ws.special then
    return false
  end
  return ws.visible == true or ws.active == true
end

local function bar_rect(w)
  local at, sz = w.at, w.size
  local x = at.x + sz.x - window_controls.bar_w - window_controls.inset
  local y = at.y + window_controls.inset
  return x, y, window_controls.bar_w, window_controls.bar_h
end

local function point_in_bar(w, px, py)
  local x, y, bw, bh = bar_rect(w)
  return px >= x and px <= x + bw and py >= y and py <= y + bh
end

local function zscore(w)
  local fs = (w.fullscreen == 2) and 10000 or 0
  local fl = w.floating and 1000 or 0
  return fs + fl - (w.focus_history_id or 9999)
end

function window_controls.window_at_bar(px, py)
  local list = hl.get_windows()
  local best, bestz = nil, -1e9
  for i = 1, #list do
    local w = list[i]
    if on_screen(w) and w.fullscreen ~= 2 and point_in_bar(w, px, py) then
      local z = zscore(w)
      if z > bestz then
        best, bestz = w, z
      end
    end
  end
  return best
end

function window_controls.install(bar_w, bar_h, inset)
  if type(bar_w) == "number" then
    window_controls.bar_w = bar_w
  end
  if type(bar_h) == "number" then
    window_controls.bar_h = bar_h
  end
  if type(inset) == "number" then
    window_controls.inset = inset
  end
  if window_controls.bind then
    pcall(function()
      window_controls.bind:remove()
    end)
    window_controls.bind = nil
  end
  window_controls.bind = hl.bind("mouse:273", function()
    local pos = hl.get_cursor_pos()
    if not pos then
      return
    end
    local win = window_controls.window_at_bar(pos.x, pos.y)
    if not win then
      return
    end
    if win.fullscreen == 1 then
      hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", window = win }))
    end
    if not win.floating then
      hl.dispatch(hl.dsp.window.float({ action = "toggle", window = win }))
    end
    hl.dispatch(hl.dsp.window.drag({ window = win }))
  end, {
    mouse = true,
    drag = true,
    non_consuming = true,
    description = "Window controls move",
  })
end

function window_controls.uninstall()
  if window_controls.bind then
    pcall(function()
      window_controls.bind:remove()
    end)
    window_controls.bind = nil
  end
end
