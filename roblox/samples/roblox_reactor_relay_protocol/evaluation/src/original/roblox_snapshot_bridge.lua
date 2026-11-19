-- Evaluator-only server relay; read-only and exposes no gameplay action API.
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local relay = Instance.new("RemoteEvent")
relay.Name = "ReactorRelayEvaluatorSnapshotRelay"
relay.Parent = ReplicatedStorage
relay.OnServerEvent:Connect(function(_, snapshot)
    if type(snapshot) ~= "table" or snapshot._evaluator_channel ~= "client" then return end
    local ok, payload = pcall(HttpService.JSONEncode, HttpService, snapshot)
    if ok and #payload < 1000000 then
        pcall(HttpService.PostAsync, HttpService, "http://127.0.0.1:8765/snapshot", payload, Enum.HttpContentType.ApplicationJson, false)
    end
end)
