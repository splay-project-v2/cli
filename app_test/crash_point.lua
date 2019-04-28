print("CRASH_POINT.LUA START")

require("splay.base")
local math = require("math")
local net = require("splay.net")
local misc = require("splay.misc")

function receive(s)
    local ip, port = s:getpeername()
    while events.yield() do
        local data, err = s:receive("*l")
        print("I received : "..data)
        -- CRASH POINT 2 : STOP : AFTER 6
    end
end

function send(s)
    while events.yield() do
        -- CRASH POINT 1 : RECOVERY 1 : AFTER 3
        events.sleep(0.5)
        print("I send data") 
        s:send("I AM "..job.position.."\n")
    end
end

function init(s, connect)
    local ip, port = s:getpeername()
    print("Connection accepted with : "..ip..":"..port)
end

function final(s)
    local ip, port = s:getpeername()
    print("Closing: "..ip..":"..port)
end

events.run(function()
    -- Accept connection from other nodes
    net.server(job.me.port, {initialize = init, send = send, receive = receive, finalize = final})
    
    -- Launch connection to each orther node
    events.thread(function ()
        events.sleep(1)
        for i, n in pairs(job.nodes) do
            if n.port ~= job.me.port or n.ip ~= job.me.ip then
                print("Try to begin connection to "..n.ip..":"..n.port.." - index "..i)
                net.client(n, {initialize = init, send = send, receive = receive, finalize = final})
            end
        end
    end)
    
    -- Crash point or kill before
end)

