-- use ChangeScreenResolution command to set output to best fitting fps rate
--  when playing videos with mpv.

utils = require 'mp.utils'

-- if you want your display output switched to a certain mode during playback,
--  use e.g. "--script-opts=winframes-output-mode=1920x1080"
winframes_output_mode = mp.get_opt("winframes-output-mode")

winframes_exec_path = mp.get_opt("winframes-exec-path") or 'ChangeScreenResolution.exe'

winframes_blacklist = {}
function winframes_parse_blacklist()
   -- use e.g. "--script-opts=winframes-blacklist=25" to have xrand.lua not use 25Hz refresh rate

	-- Parse the optional "blacklist" from a string into an array for later use.
	-- For now, we only support a list of rates, since the "mode" is not subject
	--  to automatic change (mpv is better at scaling than most displays) and
	--  this also makes the blacklist option more easy to specify:
	local b = mp.get_opt("winframes-blacklist")
	if (b == nil) then
		return
	end
	
	local i = 1
	for s in string.gmatch(b, "([^, ]+)") do
		winframes_blacklist[i] = 0.0 + s
		i = i+1
	end
end
winframes_parse_blacklist()

local function cmdToString(p)
	local cmd_as_string = ""
	for k, v in pairs(p["args"]) do
		cmd_as_string = cmd_as_string .. v .. " "
	end
	return cmd_as_string
end

local function trimmer(s)
	return string.gsub(string.gsub(s or '', '^%s+', ''),'%s+$','')
end

function winframes_check_blacklist(mode, rate)
	-- check if (mode, rate) is black-listed - e.g. because the
	--  computer display output is known to be incompatible with the
	--  display at this specific mode/rate 
	
	for i=1,#winframes_blacklist do
		r = winframes_blacklist[i]
		
		if (r == rate) then
			mp.msg.log("v", "will not use mode '" .. mode .. "' with rate " .. rate .. " because option --script-opts=winframes-blacklist said so")
			return true
		end
	end
	
	return false
end

winframes_detect_done = false
winframes_modes = {}
winframes_connected_outputs = {}
function winframes_detect_available_rates()
	if (winframes_detect_done) then
		return
	end
	winframes_detect_done = true
	
	-- ChangeScreenResolution.exe doesn't show the which mode is currently active, so we need to query it separately.
	
	local p = {}
	p["cancellable"] = false
	p["args"] = {}
	p["args"][1] = winframes_exec_path
	p["args"][2] = "/l"
	local res = utils.subprocess(p)

	if (res["error"] ~= nil) then
		mp.msg.log("info", "failed to execute '"..cmdToString(p).."', error message: " .. res["error"])
		return
	end

	local q = {}
	q["cancellable"] = false
	q["args"] = {}
	q["args"][1] = winframes_exec_path
	q["args"][2] = "/m"
	local qes = utils.subprocess(q)

	if (qes["error"] ~= nil) then
		mp.msg.log("info", "failed to execute '"..cmdToString(q).."', error message: " .. qes["error"])
		return
	end
	
	
	mp.msg.log("v",cmdToString(p).."\n" .. res["stdout"])

	for found in string.gmatch(res["stdout"], '(%[[^%[]+)') do

		local currentSettings = trimmer(string.match(found,'Settings: ([^\\n]+)'))

		--displays without settings are definitely not connected
		if currentSettings ~= '' then

			local index = trimmer(string.match(found,'^%[(%d+)%]'))

			local output = trimmer(string.match(found,'^%[%d+%] +([^\n ]+)'))

			local old_mode,rate = string.match(currentSettings,'([0-9x]+) %d+bit @(%d+)Hz .+')

			local matcher = trimmer(string.gsub(currentSettings,'@'..rate..'Hz','@(%%d+)Hz'))

			local _, __, rawlist = string.find(qes["stdout"],'Display modes for '..output..':([^D]+)')
			local mls = trimmer(rawlist)
			
			table.insert(winframes_connected_outputs, output)
			
			-- the first line with a "*" after the match contains the rates associated with the current mode
			-- local mls = string.match(res["stdout"], "\n" .. string.gsub(output, "%p", "%%%1") .. " connected.*")
			local mode = nil

			-- old_rate = 0 means "no old rate known to switch to after playback"
			local old_rate = 0.0+trimmer(rate)
			
			
			if (winframes_output_mode ~= nil) then		
				local specialMatcher = trimmer(string.gsub(matcher,'^'..old_mode,winframes_output_mode))
				-- special case: user specified a certain preferred mode to use for playback
				mp.msg.log("v", "looking for refresh rates for user supplied output mode " .. winframes_output_mode)
				found = string.match(mls, specialMatcher)
				if (mode == nil) then
					mp.msg.log("info", "user preferred output mode " .. winframes_output_mode .. " not found for output " .. output .. " - will use current mode")
					mode = old_mode
				else 
					mp.msg.log("info", "using user preferred winframes_output_mode " .. winframes_output_mode .. " for output " .. output)
					matcher = specialMatcher
					mode = winframes_output_mode
					mp.msg.log("v", "old_rate=" .. old_rate .. " found for old_mode=" .. tostring(old_mode))
				end
			else
				mode = old_mode
			end

			
			mp.msg.log("info", "output " .. output .. " mode=" .. mode .. " old rate=" .. old_rate)
			
			winframes_modes[output] = { index=index, mode = mode, old_mode = old_mode, rates = {}, old_rate = old_rate }
			for s in string.gmatch(mls, matcher) do
				-- check if rate "r" is black-listed - this is checked here because 
				if (not winframes_check_blacklist(mode, 0.0 + s)) then
					winframes_modes[output].rates[#winframes_modes[output].rates+1] = 0.0 + s
				end
			end
			

		end
	end
end

function winframes_find_best_fitting_rate(fps, output)
	local winframes_rates = winframes_modes[output].rates
	mp.msg.log("info", "output " .. output .. " fps=" .. fps.." available rates="..#winframes_rates)

	
  local best_fitting_rate = nil
  local best_fitting_ratio = math.huge
  
	-- try integer multipliers of 1 to 10 (given that high-fps displays exist these days)
	for m=1,10 do
		for i=1,#winframes_rates do
			local r = winframes_rates[i]
			local ratio = r / (m * fps)
      if (ratio < 1.0) then
        ratio = 1.0 / ratio
      end
      -- If the ratio is more than "very insignificantly off",
      -- then add a tiny additional score that will prefer faster
      -- over slower display frame rates, because those will cause
      -- shorter "stutters" when the display needs to skip or 
      -- duplicate one source frame.
      -- If the ratio is very close to 1.0, then we rather not
      -- choose the higher of the existing display rates, because
      -- displays performing frame interpolation work better when
      -- presented the actual, non-repeated source material frames.
      if (ratio > 1.0001) then
        ratio = ratio + (0.00000001 * (1000.0 - r))
      end
      -- mp.msg.log("info", "ratio " .. ratio .. " for r == " .. r)
      if (ratio < best_fitting_ratio) then
        best_fitting_ratio = ratio
        -- the xrand -q output may print nearby frequencies as the same
        -- rounded numbers - therefore, if our multiplier is == 1,
        -- we better return the video's frame rate, which ChangeScreenResolution
        -- is then likely to set the best rate for, even if the mode
        -- has some "odd" rate
        if (m == 1) then
          r = fps
        end
        best_fitting_rate = r
			end
		end		
	end
  
  return best_fitting_rate
end


winframes_active_outputs = {}
function winframes_set_active_outputs()
	local dn = mp.get_property("display-names")
	
	if (dn ~= nil) then
		mp.msg.log("v","display-names=" .. dn)
		winframes_active_outputs = {}
		for w in (dn .. ","):gmatch("([^,]*),") do 
			table.insert(winframes_active_outputs, w)
		end
	end
end

-- last detected non-nil video frame rate:
winframes_cfps = nil

--we keep track if we changed the refresh rate of multiple monitors
winframes_multi = false

-- for each output, we remember which refresh rate we set last, so
-- we do not unnecessarily set the same refresh rate again
winframes_previously_set = {}

function winframes_set_rate()

	local f = mp.get_property_native("container-fps")
	if (f == nil or f == winframes_cfps) then
		-- either no change or no frame rate information, so don't set anything
		return
	end
	winframes_cfps = f

	winframes_detect_available_rates()
	
	winframes_set_active_outputs()
   -- unless "--script-opts=xrandr-ignore_unknown_oldrate=true" is set, 
	--  xrandr.lua will not touch display outputs for which it cannot
	--  get information on the current refresh rate for - assuming that
	--  such outputs are "disabled" somehow.
	local ignore_unknown_oldrate = mp.get_opt("winframes-ignore_unknown_oldrate")
	if (ignore_unknown_oldrate == nil) then
		ignore_unknown_oldrate = false
	end


	local outs = {}
	if (#winframes_active_outputs == 0) then
		-- No active outputs - probably because vo (like with vdpau) does
		-- not provide the information which outputs are covered.
		-- As a fall-back, let's assume all connected outputs are relevant.
		mp.msg.log("v","no output is known to be used by mpv, assuming all connected outputs are used.")
		outs = winframes_connected_outputs
	else
		outs = winframes_active_outputs
	end
	mp.msg.log("info", "let's get outputs")
		
	-- iterate over all relevant outputs used by mpv's output:
	for n, output in ipairs(outs) do
		
		if (ignore_unknown_oldrate == false and winframes_modes[output].old_rate == 0) then
			mp.msg.log("info", "not touching output " .. output .. " because winframes did not indicate a used refresh rate for it - use --script-opts=winframes-ignore_unknown_oldrate=true if that is not what you want.")
		else
			local bfr = winframes_find_best_fitting_rate(winframes_cfps, output)

			if (bfr == 0.0) then
				mp.msg.log("info", "no non-blacklisted rate available, not invoking winframes")
			else
				mp.msg.log("info", "container fps is " .. winframes_cfps .. "Hz, for output " .. output .. " mode " .. winframes_modes[output].mode .. " the best fitting display rate we will pass to winframes is " .. bfr .. "Hz")

				if (bfr == winframes_previously_set[output]) then
					mp.msg.log("v", "output " .. output .. " was already set to " .. bfr .. "Hz before - not changing")
				else 
					-- invoke ChangeScreenResolution to set the best fitting refresh rate for output 
					local p = {}
					p["cancellable"] = false
					p["args"] = {
						winframes_exec_path,
						"/d="..winframes_modes[output].index,
						"/f="..math.floor(bfr) -- ChangeScreenResolution doesn't accept decimals so 23.976 -> 23, 59.94 -> 59, etc
					}
					if(winframes_modes[output].mode ~= winframes_modes[output].old_mode) then
						p["args"][4] = "/w="..string.match(winframes_modes[output].mode, "^[0-9]+")
						p["args"][5] = "/h="..string.match(winframes_modes[output].mode, "[0-9]+$")
					end

					mp.msg.log("debug", "executing as subprocess: \"" .. cmdToString(p) .. "\"")
					local res = utils.subprocess(p)

					if (res["error"] ~= nil) then
						mp.msg.log("error", "failed to set refresh rate for output " .. output .. " using ChangeScreenResolution, error message: " .. res["error"])
					else
						winframes_previously_set[output] = bfr
					end
				end
			end
		end
	end
end


function winframes_set_old_rate()
	
	local outs = {}
	if (#winframes_active_outputs == 0 or winframes_multi) then
		-- No active outputs - probably because vo (like with vdpau) does
		-- not provide the information which outputs are covered.
		-- As a fall-back, let's assume all connected outputs are relevant.
		-- If we set the refresh rate for multiple monitors, we also iterate all.
		mp.msg.log("v","no output is known to be used by mpv, assuming all connected outputs are used.")
		outs = winframes_connected_outputs
	else
		outs = winframes_active_outputs
	end
		
	-- iterate over all relevant outputs used by mpv's output:
	for n, output in ipairs(outs) do
		
		local old_rate = winframes_modes[output].old_rate
		
		if (old_rate == 0 or winframes_previously_set[output] == nil ) then
			mp.msg.log("v", "no previous frame rate known for output " .. output .. " - so no switching back.")
		else

			if (math.abs(old_rate-winframes_previously_set[output]) < 0.001) then
				mp.msg.log("v", "output " .. output .. " is already set to " .. old_rate .. "Hz - no switching back required")
			else 

				mp.msg.log("info", "switching output " .. output .. " that was set for replay to mode " .. winframes_modes[output].mode .. " at " .. winframes_previously_set[output] .. "Hz back to mode " .. winframes_modes[output].old_mode .. " with refresh rate " .. old_rate .. "Hz")

				-- invoke ChangeScreenResolution to set the best fitting refresh rate for output 
				local p = {}
				p["cancellable"] = false
				p["args"] = {
					winframes_exec_path,
					"/d=".. winframes_modes[output].index,
					"/f="..math.floor(old_rate) -- ChangeScreenResolution doesn't accept decimals so 23.976 -> 23, 59.94 -> 59, etc
				}
				if(winframes_modes[output].mode ~= winframes_modes[output].old_mode) then
					p["args"][4] = "/w="..string.match(winframes_modes[output].old_mode, "^[0-9]+")
					p["args"][5] = "/h="..string.match(winframes_modes[output].old_mode, "[0-9]+$")
				end

				local res = utils.subprocess(p)

				if (res["error"] ~= nil) then
					mp.msg.log("error", "failed to set refresh rate for output " .. output .. " using xrandr, error message: " .. res["error"])
				else
					winframes_previously_set[output] = old_rate
				end
			end
		end
		
	end
	
end

-- we'll consider setting refresh rates whenever the video fps or the active outputs change:
mp.observe_property("container-fps", "native", winframes_set_rate)
mp.observe_property("display-names", "native", function()
	winframes_cfps = nil
	winframes_multi  = true
	winframes_set_rate()
end)


-- and we'll try to revert the refresh rate when mpv is shut down
mp.register_event("shutdown", winframes_set_old_rate)
