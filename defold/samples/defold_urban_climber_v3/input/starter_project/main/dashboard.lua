-- Public read-only Game State Dashboard transport for Defold.
--
-- The game owns the capture function and maps its real state into the public
-- contract.  This module only serializes snapshots; it exposes no input,
-- restart, state-mutation, or result-forcing API.

local M = {}

local VALID_PHASE = {
	not_ready = true,
	menu = true,
	playing = true,
	paused = true,
	won = true,
	lost = true,
}

local capture_fn
local output
local revision = 0
local last_payload
local elapsed = 0
local interval = 0.20

local function encode_snapshot(value)
	-- Lua has no distinct empty-array value.  Defold therefore encodes an
	-- empty table as {}, while these two contract fields are always arrays.
	local encoded = json.encode(value)
	-- Defold's encoder may emit empty Lua tables as `{}`.  Only the two
	-- contract array fields are normalized; nested object tables remain objects.
	encoded = encoded:gsub('"entities":{}', '"entities":[]')
	encoded = encoded:gsub('"targets":{}', '"targets":[]')
	return encoded
end

local function validate_body(body)
	assert(type(body) == "table", "dashboard capture must return a table")
	assert(VALID_PHASE[body.phase], "invalid dashboard phase")
	assert(type(body.slots) == "table", "dashboard slots must be a table")
	assert(type(body.entities) == "table", "dashboard entities must be a table")
	assert(type(body.targets) == "table", "dashboard targets must be a table")
end

local function write_snapshot(force)
	if not capture_fn then
		return
	end

	local body = capture_fn()
	validate_body(body)
	local payload = encode_snapshot({
		phase = body.phase,
		slots = body.slots,
		entities = body.entities,
		targets = body.targets,
	})
	if not force and payload == last_payload then
		return
	end

	last_payload = payload
	revision = revision + 1
	local line = encode_snapshot({
		revision = revision,
		phase = body.phase,
		slots = body.slots,
		entities = body.entities,
		targets = body.targets,
	})
	output:write(line, "\n")
	output:flush()
end

function M.init(read_only_capture, path)
	assert(type(read_only_capture) == "function", "dashboard.init requires a capture function")
	capture_fn = read_only_capture
	local file_path = path or "dashboard.jsonl"
	local err
	output, err = io.open(file_path, "w")
	-- Finder/CUA may launch an app bundle with `/` as its working directory.
	-- Keep the documented project-relative transport whenever it is writable,
	-- but do not let an unwritable launch directory abort the entire GUI script.
	-- Normal project-root/evaluator launches therefore still use dashboard.jsonl.
	if not output and not path then
		output, err = io.open("/tmp/urban_climber_two_roof_relay_dashboard.jsonl", "w")
	end
	assert(output, "cannot open dashboard path: " .. tostring(err))
	write_snapshot(true)
end

function M.update(dt)
	elapsed = elapsed + (dt or 0)
	if elapsed < interval then
		return
	end
	elapsed = elapsed - interval
	write_snapshot(false)
end

function M.publish_now()
	write_snapshot(false)
end

function M.final()
	if output then
		output:flush()
		output:close()
		output = nil
	end
end

return M
