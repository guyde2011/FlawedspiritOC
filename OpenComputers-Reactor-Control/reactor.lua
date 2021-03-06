--[[
This program lets you monitor and actively control a Big Reactors reactor and turbines with an OpenComputers computer.

This program was tested on and designed to work with the mod versions and configurations installed on Flawedspirit's Mental Instability Pack, though as the pack uses default settings for both Big Reactors and OpenComputers, there should be no issues using a different modpack, or even a modpack that makes changes to how BR works.

- http://technicpack.net/modpack/mi-reloaded.604813
- https://flawedspirit.com/minecraft/#pack

Computer Design
------------------------
Please note that to keep the code (relatively) simple, the program makes a few assumptions; those being:

- A Tier 3 Computer
- A Tier 2 or better Graphics Card
- An Internet Card
- One Tier 2 screen OR one Tier 3 screen (for best results)
- One reactor
- Any number of (or zero) turbines

Notes
------------------------
- Only one reactor has been tested with this program (additional reactors added AT OWN RISK)
- Data for only 6 turbines will display onscreen if using a Tier 2 screen
- Data for up to 28 turbines will display onscreen if using a Tier 3 screen
- Data for ALL turbines will still be tallied in the 'totals' row
- By default, the program updates once every 2 seconds, though the rate is adjustable

Features
------------------------
- Dynamic tracking of reactor information, like temperature, fuel/waste levels, coolant levels*, steam output*, or RF storage*
- Dynamic tracking of up to 6 turbines, including speed, steam input, RF generation, and RF storage
- In-program control of reactor power and control rod settings
- Real-time warning if certain parameters indicate abnormal or non-optimal operation of reactors/turbines
- NEW! Turbine auto mode! Set it to either 900 or 1800 RPM by pressing T and the program will toggle your turbines' induction coils or active state to keep it at the right speed**

* If applicable
** Note: the author takes no responsibility if you bankrupt your base's energy stores because your turbines are all disengaged. Please use responsibly.

Usage
------------------------
- Press the left and right arrow keys to toggle between page 1 (turbine/RF storage information) or 2 (control rod configuration)
- Press L or , to lower/raise control rods by 1%
- Press ; or . to lower/raise control rods by 5%
- Press ' or / to lower/raise control rods by 10%
- Press P to toggle reactor power
- Press Q to exit the program and return to your computer's terminal prompt
- Press T to toggle 'Auto Mode' on all turbines. This will engage the induction coil when your preferred rotational speed (900 or 1800 RPM) is reached

Resources
------------------------
- This script is available from:
  = http://pastebin.com/zWju7H0z
- Official OpenComputers Site: http://ocdoc.cil.li/
- Official Big Reactors Site: http://www.big-reactors.com/#/
- Big Reactors API: http://wiki.technicpack.net/Reactor_Computer_Port

Changelog
------------------------
- 0.1.6
  - Fixed a bug that caused the program to crash when run on a Tier 2 screen
- 0.1.5
  - Addition of turbine auto mode
  - Changes to make the program take better advantage of larger screen sizes
  - Bug fixes
- 0.1.4
  - First release to Github! :D

TODO
------------------------
- See https://github.com/Flawedspirit/FlawedspiritOC/issues for any outstanding issues.
- Fix screen flickering issue on Page 1 (may not be possible at the moment)
]]

local component = require("component")
local event = require("event")
local keyboard = require("keyboard")
local os = require("os")
local term = require("term")

local pollRate = 2 -- Change to whatever value you'd like; time is in seconds
local active = true
local currentPage = 1
local turbineAutoMode = 0 -- This can be changed to 900 or 1800 if you want

-- Static Text Elements
local header = "Reactor: "
local headerOutput = "Running at %d%% max rated output"
local version = "v0.1.6"

-- Components
local gpu = component.gpu
local reactor = component.br_reactor
local w, h = gpu.getResolution()

local turbine = {}
local i = 1
for address, type in component.list("br_turbine") do
  turbine[i] = component.proxy(address)
  i = i + 1
end 

-- Reactor/turbine Data
local totalControlRodLevel = 0
local turbineMaxSteamIn = 0
local controlRods = {}
local reactorStatus = {}

-- Colors Helper
local colors = {}
colors.white      = 0xFFFFFF
colors.orange     = 0xFFA500
colors.magenta    = 0xFF00FF
colors.lightblue  = 0x00AEEF
colors.yellow     = 0xFFFF00
colors.lime       = 0x00FF00
colors.pink       = 0xFFC0CB
colors.gray       = 0x555555
colors.grey       = 0x555555
colors.silver     = 0xAAAAAA
colors.cyan       = 0x00FFFF
colors.purple     = 0x800080
colors.blue       = 0x0000FF
colors.brown      = 0x603913
colors.green      = 0x008000
colors.red        = 0xFF0000
colors.black      = 0x000000

-- Returns a whole number expressing a percentage
-- out of 100 e.g. 90 is 90%
function percent(val, max)
  return (val / max) * 100
end

function hLine(row)
  gpu.fill(1, row, w, 1, "─")
end

function label(x, y, message, color, ...)
  local color = color or gpu.getForeground()
  local oldColor = gpu.getForeground()
  
  gpu.setForeground(color)
  term.setCursor(x, y)
  print(string.format(message, ...))
  gpu.setForeground(oldColor)
end

function box(row, message, color)
  --gpu.fill(1, row, w, row + 3, " ")
  local color = color or gpu.getForeground()
  local oldColor = gpu.getForeground()

  term.setCursor(1, row)
  gpu.setForeground(color)

  -- Corners
  gpu.set(1, row, "╒")
  gpu.set(w, row, "╕")
  gpu.set(1, row + 2, "└")
  gpu.set(w, row + 2, "┘")

  -- Left and right
  gpu.set(1, row + 1, "│")
  gpu.set(w, row + 1, "│")

  -- Top and bottom
  gpu.fill(2, row, w - 2, 1, "═")
  gpu.fill(2, row + 2, w - 2, 1, "─")  

  gpu.set(3, row + 1, message)
  gpu.setForeground(oldColor)
end

-- Displayed if a reactor cannot be found at all
-- and this program is rendered useless
function printNoSignal()
  icon = "[ ! ] "
  message = "No Signal"

  gpu.setBackground(colors.black)
  gpu.fill(1, 1, w, h, " ")

  gpu.setForeground(colors.red)
  gpu.set(w / 2 - (string.len(icon) + string.len(message)) / 2 + 1, (h / 2) + 1, "[ ! ]")

  gpu.setForeground(colors.white)
  gpu.set((w / 2) - 1, (h / 2) + 1, message)
end

function printControlHelp()
  hLine(h - 5)
  label(1, h - 4, "%s", nil, "l / ,")
  label(16, h - 4, "%s", nil, "; / .")
  label(32, h - 4, "%s", nil, "' / /")
  label(48, h - 4, "%s", nil, "p")
  label(64, h - 4, "%s", nil, "q")

  label(1, h - 3, "%s", colors.gray, "Rods +1/-1")
  label(16, h - 3, "%s", colors.gray, "Rods +5/-5")
  label(32, h - 3, "%s", colors.gray, "Rods +10/-10")
  label(48, h - 3, "%s", colors.gray, "Reactor Power")
  label(64, h - 3, "%s", colors.gray, "Quit")

  if w > 80 then
    label(80, h - 4, "%s", nil, "t")
    label(80, h - 3, "%s", colors.gray, "Turbine Auto Mode")
  end
end
function toggleAutoMode()
  if turbineAutoMode == 0 then
    turbineAutoMode = 900
  elseif turbineAutoMode == 900 then
    turbineAutoMode = 1800
  elseif turbineAutoMode == 1800 then
    turbineAutoMode = 0
  else
    turbineAutoMode = 0
  end
end

-- Event handler for when a key is pressed
function onKeyDown(key)
  local event, address, _, key, _ = event.pull()
  if key == keyboard.keys.right then
    currentPage = 2
    gpu.fill(1, 1, w, h, " ")
  elseif key == keyboard.keys.left then
    currentPage = 1
    gpu.fill(1, 1, w, h, " ")
  elseif key == keyboard.keys.l then
    reactor.setAllControlRodLevels(totalControlRodLevel + 1)
  elseif key == keyboard.keys.comma then
    reactor.setAllControlRodLevels(totalControlRodLevel - 1)
  elseif key == keyboard.keys.semicolon then
    reactor.setAllControlRodLevels(totalControlRodLevel + 5)
  elseif key == keyboard.keys.period then
    reactor.setAllControlRodLevels(totalControlRodLevel -5)
  elseif key == keyboard.keys.apostrophe then
    reactor.setAllControlRodLevels(totalControlRodLevel + 10)
  elseif key == keyboard.keys.slash then
    reactor.setAllControlRodLevels(totalControlRodLevel - 10)
  elseif key == keyboard.keys.p then
    reactor.setActive(not reactor.getActive())
  elseif key == keyboard.keys.q then
    active = false
  elseif key == keyboard.keys.t then
    toggleAutoMode()
  end
end

-- Listen for "key_down" event to control program flow
event.listen("key_down", onKeyDown)

while active do
  gpu.fill(1, 1, w, h, " ")
  if component.isAvailable("br_reactor") then
    label(w - (string.len(version) + 1), h - 1, version, colors.gray)
    box(1, header, nil)

    -- Get and update values of each control rod
    for i = 1, reactor.getNumberOfControlRods() - 1 do
      controlRods[i] = reactor.getControlRodLevel(i)
    end

    -- Iterate through and take the sum of each control rod level
    -- Average it to get total control rod level
    totalControlRodLevel = 0
    for i = 1, #controlRods do
      totalControlRodLevel = totalControlRodLevel + controlRods[i]
    end
    totalControlRodLevel = totalControlRodLevel / #controlRods

    -- Update reactor data
    reactorStatus.temperature      = {"Temp", reactor.getCasingTemperature()}
    reactorStatus.fuel             = {"Fuel", reactor.getFuelAmount()}
    reactorStatus.waste            = {"Waste", reactor.getWasteAmount()}
    reactorStatus.fuelMax          = {"Max Fuel", reactor.getFuelAmountMax()}
    reactorStatus.burnRate         = {"Burn Rate", reactor.getFuelConsumedLastTick()}
    reactorStatus.reactivity       = {"Reactivity", reactor.getFuelReactivity()}
    reactorStatus.coolant          = {"Coolant", reactor.getCoolantAmount()}
    reactorStatus.coolantMax       = {"Max Coolant", reactor.getCoolantAmountMax()}
    reactorStatus.steam            = {"Steam Out", reactor.getHotFluidProducedLastTick()}
    reactorStatus.steamMax         = {"Max Steam", reactor.getHotFluidAmountMax()}
    reactorStatus.storedRF         = {"Stored Power", reactor.getEnergyStored()}

    label(1, 4, "%s: %.3f mB/t (%s: %d%%)", nil, reactorStatus.burnRate[1], reactorStatus.burnRate[2], reactorStatus.reactivity[1], reactorStatus.reactivity[2])

    -- REACTOR TABLE
    -- Table header
    label(1, 6, "%s", nil, reactorStatus.temperature[1])
    label(16, 6, "%s", nil, reactorStatus.fuel[1])
    label(32, 6, "%s", nil, reactorStatus.waste[1])
    label(48, 6, "%s", nil, reactorStatus.coolant[1])
    label(64, 6, "%s", nil, reactorStatus.steam[1])
    hLine(7)

    -- Table body
    label(1, 8, "%d °C", colors.red, reactorStatus.temperature[2])

    if percent(reactorStatus.fuel[2], reactorStatus.fuelMax[2]) > 10 then
      label(16, 8, "%d mB", nil, reactorStatus.fuel[2])
    else
      label(16, 8, "%d mB [!]", colors.red, reactorStatus.fuel[2])
    end

    if percent(reactorStatus.waste[2], reactorStatus.fuelMax[2]) < 90 then
      label(32, 8, "%d mB", nil, reactorStatus.waste[2])
    else
      label(32, 8, "%d mB [!]", colors.red, reactorStatus.waste[2])
    end

    if percent(reactorStatus.coolant[2], reactorStatus.coolantMax[2]) > 10 then
      label(48, 8, "%d mB", nil, reactorStatus.fuel[2])
    else
      label(48, 8, "%d mB [!]", colors.red, reactorStatus.coolant[2])
    end
    
    if reactorStatus.steam[2] >= turbineMaxSteamIn then
      label(64, 8, "%d mB/t", nil, reactorStatus.steam[2])
    else
      label(64, 8, "%d mB/t [!]", colors.red, reactorStatus.steam[2])
    end

    -- Percentages
    label(16, 9, "(%.1f%%)", colors.gray, percent(reactorStatus.fuel[2], reactorStatus.fuelMax[2]))
    label(32, 9, "(%.1f%%)", colors.gray, percent(reactorStatus.waste[2], reactorStatus.fuelMax[2]))
    label(48, 9, "(%.1f%%)", colors.gray, percent(reactorStatus.coolant[2], reactorStatus.coolantMax[2]))
    label(64, 9, "(%.1f%%)", colors.gray, percent(reactorStatus.steam[2], reactorStatus.steamMax[2]))

    if reactor.getActive() then
      label(string.len(header) + 3, 2, "ON", colors.lime)
      label(w - string.len(headerOutput), 2, headerOutput, nil, (100 - totalControlRodLevel))
    else
      label(string.len(header) + 3, 2, "OFF", colors.red)
      label((w + 1) - string.len(headerOutput), 2, headerOutput, nil, 0)
    end

    if currentPage == 1 then
      box(h - 2, "Press [→] to go to page 2", nil)

      if h > 25 then
        printControlHelp()
      end

      if component.isAvailable("br_turbine") then
        -- TURBINE TABLE
        -- Table header
        label(1, 11, "%s", nil, "Turbine #")
        label(16, 11, "%s", nil, "Speed")
        label(32, 11, "%s", nil, "Steam In")
        label(48, 11, "%s", nil, "RF Out")
        label(64, 11, "%s", nil, "Stored RF")

        if w > 80 then
          label(80, 11, "%s", nil, "Coil State")
        end
        hLine(12)

        -- Table body
        -- Update turbine status
        local turbineTotalSteamIn = 0
              turbineMaxSteamIn = 0
        local turbineTotalRFOut = 0
        local turbineStoredRF = 0

        -- by default, only 6 turbines will fit on the screen
        local maxTurbines = 0

        if h > 25 then
          maxTurbines = math.min(#turbine, 28)
          hOffset = 6
        else
          maxTurbines = math.min(#turbine, 6)
          hOffset = 4
        end

        if #turbine > maxTurbines then
          label(1, h - (hOffset + 2), "...", colors.orange)
          label(16, h - (hOffset + 2), "%d %s", colors.orange, (#turbine - 6), "turbine(s) not shown. Totals shown for all turbines.")
        end

        for i = 1, #turbine do
          turbineTotalSteamIn = turbineTotalSteamIn + turbine[i].getFluidFlowRate()
          turbineMaxSteamIn = turbineMaxSteamIn + turbine[i].getFluidFlowRateMax()
          turbineTotalRFOut = turbineTotalRFOut + turbine[i].getEnergyProducedLastTick()
          turbineStoredRF = turbineStoredRF + turbine[i].getEnergyStored()

          -- Auto Mode (TM but not really) fun
          if turbineAutoMode == 900 or turbineAutoMode == 1800 then
            if turbineAutoMode == 900 and turbine[i].getRotorSpeed() < 895 or
             turbineAutoMode == 1800 and turbine[i].getRotorSpeed() < 1795 then
              turbine[i].setInductorEngaged(false)
            else
              turbine[i].setInductorEngaged(true)
            end

            if turbineAutoMode == 900 and turbine[i].getRotorSpeed() > 920 or
             turbineAutoMode == 1800 and turbine[i].getRotorSpeed() > 1820 then
              turbine[i].setActive(false)
            else
              turbine[i].setActive(true)
            end
          end
          
          if w > 80 then
            label(80, 11, "%s", nil, "Coil State")
            label(96, 11, "%s", nil, "Status")
          end
        end

        for i = 1, maxTurbines do
          label(1, 12 + i, "%d", nil, i)

          if turbine[i].getRotorSpeed() >= 895 and turbine[i].getRotorSpeed() <= 905 or
           turbine[i].getRotorSpeed() >= 1795 and turbine[i].getRotorSpeed() <= 1805 then
            label(16, 12 + i, "%.1f RPM", colors.cyan, turbine[i].getRotorSpeed())
          elseif turbine[i].getRotorSpeed() >= 880 and turbine[i].getRotorSpeed() <= 920 or
           turbine[i].getRotorSpeed() >= 1780 and turbine[i].getRotorSpeed() <= 1820 then
            label(16, 12 + i, "%.1f RPM", colors.lime, turbine[i].getRotorSpeed())
          elseif turbine[i].getRotorSpeed() >= 1821 then
            label(16, 12 + i, "%.1f RPM [!]", colors.red, turbine[i].getRotorSpeed())
          else
            label(16, 12 + i, "%.1f RPM", colors.orange, turbine[i].getRotorSpeed())
          end
          label(32, 12 + i, "%d mB/t", nil, turbine[i].getFluidFlowRate())
          label(48, 12 + i, "%d RF/t", nil, turbine[i].getEnergyProducedLastTick())
          label(64, 12 + i, "%d RF", nil, turbine[i].getEnergyStored())

          if w > 80 then
            if turbine[i].getInductorEngaged() then
              label(80, 12 + i, "%s", colors.lime, "Engaged")
            else
              label(80, 12 + i, "%s", colors.red, "Disengaged")
            end
            if turbine[i].getRotorSpeed() >= 1821 then
              label(96, 12 + i, "%s", colors.red, "Overspeed")
            elseif turbine[i].getRotorSpeed() < 880 then
              label(96, 12 + i, "%s", colors.red, "Underspeed")
            elseif turbine[i].getActive() == false then
              label(96, 12 + i, "%s", colors.gray, "Disabled")
            else
              label(96, 12 + i, "%s", nil, "Normal")
            end
          end
        end

        hLine(h - (hOffset + 1))
        label(1, h - (hOffset), "%s", nil, "TOTAL")
        label(16, h - (hOffset), "%s", nil, "--")
        label(32, h - (hOffset), "%d mB/t", nil, turbineTotalSteamIn)
        label(48, h - (hOffset), "%d RF/t", nil, turbineTotalRFOut)
        label(64, h - (hOffset), "%d RF", nil, turbineStoredRF)

        if turbineAutoMode == 0 then
          label(80, h - (hOffset), "%s %s", nil, "Auto Mode:", "Off")
        elseif turbineAutoMode == 900 then
          label(80, h - (hOffset), "%s %s", nil, "Auto Mode:", "900 RPM")
        elseif turbineAutoMode == 1800 then
         label(80, h - (hOffset), "%s %s", nil, "Auto Mode:", "1800 RPM")
        end
      else
        label(1, 11, "%s: %d RF", nil, reactorStatus.storedRF[1], reactorStatus.storedRF[2])
        label(1, 13, "%s", nil, "No turbines were detected.")
      end

      os.sleep(pollRate)
    elseif currentPage == 2 then
      local maxBarLength = (w - 11) - 11

      box(h - 2, "Press [←] to go to page 1", nil)
      label(1, 11, "%s", nil, "Control Rods")
      hLine(12)

      gpu.fill(11, 13, math.ceil(maxBarLength * (totalControlRodLevel / 100) + 0.5), 1, "=")
      label(1, 13, "%s", nil, "ALL RODS [")
      label(w - 10, 13, "%s %d%%", nil, "]", totalControlRodLevel)

      printControlHelp()
      os.sleep(pollRate)
    end
  else
    printNoSignal()
  end
end

-- Unregister key_down event on program exit or things get... weird...
event.ignore("key_down", onKeyDown)
term.clear()