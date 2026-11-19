-- Evaluator-only read bridge.  It has no action/reset/win API.
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local endpoint = "http://127.0.0.1:8765/snapshot"

-- HttpService requests are not reliable from a LocalScript on every Studio
-- build. This evaluator-owned event only relays the read-only client snapshot
-- to this server bridge; it exposes no action or gameplay mutation API.
local clientRelay = Instance.new("RemoteEvent")
clientRelay.Name = "PocketGreenhouseEvaluatorSnapshotRelay"
clientRelay.Parent = ReplicatedStorage

clientRelay.OnServerEvent:Connect(function(_, snapshot)
    if type(snapshot) ~= "table" or snapshot._evaluator_channel ~= "client" then
        return
    end
    local ok, payload = pcall(HttpService.JSONEncode, HttpService, snapshot)
    if not ok or #payload > 1000000 then
        return
    end
    local sent, sendError = pcall(function()
        HttpService:PostAsync(endpoint, payload, Enum.HttpContentType.ApplicationJson, false)
    end)
    if not sent then
        warn("__PG_BRIDGE_ERROR__" .. tostring(sendError))
    end
end)
