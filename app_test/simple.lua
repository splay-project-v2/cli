--[[

Small script to test splay, just log the different neighbours, exit directly after

--]]

require("splay.base")

print("SIMPLE.LUA START")
print("I am the job "..job.position)

neighbours = job.nodes
print("I am link to :")
for _, n in pairs(neighbours) do print(" - "..n.ip..":"..n.port) end

print("SIMPLE.LUA EXIT")