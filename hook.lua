-- Hyprland-side helpers for window-controls.
-- Right-button drag must be a compositor mouse bind; dispatching drag()
-- from Quickshell while the pointer is on a layer-shell surface does not
-- start an interactive move.

window_controls = window_controls or {}

function window_controls.set_drag_target(address)
  if window_controls.bind then
    pcall(function()
      window_controls.bind:remove()
    end)
    window_controls.bind = nil
  end
  if type(address) ~= "string" or address == "" then
    return
  end
  local selector = address
  if not address:find("^address:") then
    selector = "address:" .. address
  end
  window_controls.bind = hl.bind("mouse:273", function()
    local win = hl.get_window(selector)
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
    description = "Window controls move",
  })
end
