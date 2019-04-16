--[[

Small script to test splay, just log the different neighbours during 1 minutes

--]]

require("splay.base")
print("Discovering Job - launch during 1 minute - v1")

neighbours = job.nodes
print("I am link to :")
for _, n in pairs(neighbours) do print(" - "..n.ip..":"..n.port) end

print("Exit Discovering Job")