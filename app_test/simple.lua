--[[

Small script to test splay, just log the different neighbours during 1 minutes

--]]

require("splay.base")

print("I am the job "..job.position)

neighbours = job.nodes
print("I am link to :")
for _, n in pairs(neighbours) do print(" - "..n.ip..":"..n.port) end

print("Exit Discovering Job")