
--[[ job = {}
job.me = {ip = '127.0.0.1', port= tonumber(arg[1])}
--job.nodes = {{ip= '127.0.0.1', port= 15001 }, {ip= '127.0.0.1', port= 15002 },{ip= '127.0.0.1', port= 15003 },{ip= '127.0.0.1', port= 15004 },{ip= '127.0.0.1', port= 15005 }}
job.nodes = {{ip= '127.0.0.1', port= 11158 }, {ip= '127.0.0.1', port= 11159 }}

settings = { 
    ["local_start_port"] = 11000,
    ["local_ip"] = '127.0.0.1',
    --["blacklist"] = { [1] = "127.0.0.1",[2] = "localhost"},
    ["ip"] = "127.0.0.1",
    ["end_port"] = tonumber(arg[1]),
    ["start_port"] = tonumber(arg[1]),
    ["max_receive"] = 134217728,
    ["max_sockets"] = 32,
    ["local_end_port"] = 12000,
    ["nb_ports"] = 1,
    ["list"] = { 
        ["position"] = 2,
        ["type"] = head,
        ["nodes"] = job.nodes
    },
    ["max_send"] = 134217728
}

socket = require("socket")
rs = require("splay.restricted_socket")
rs.init(settings)
socket = rs.wrap(socket)
package.loaded['socket.core'] = socket ]]

print("Begin Simple network : I am "..job.me.ip..":"..job.me.port)

require("splay.base")
local math = require("math")
local net = require("splay.net")
local misc = require("splay.misc")

function receive(s)
    print("Receive Stand by")
    local ip, port = s:getpeername()
    while events.yield() do
        local data, err = s:receive("*l")
        print("I received "..data.." from "..ip..":"..port)
    end
end

function send(s)
    print("Send Stand by")
    while events.yield() do
        events.sleep(3)
        s:send("Hello i am "..misc.dump(job.me).."\n")
    end
end

function init(s, connect)
    local ip, port = s:getpeername()
    print("Connection with : "..ip..":"..port)
end

function final(s)
    local ip, port = s:getpeername()
    print("Closing: "..ip..":"..port.." - index ")
end

events.run(function()
    -- Accept connection from other nodes
    net.server(job.me.port, {initialize = init, send = send, receive = receive, finalize = final})
    
    -- Launch connection to each orther node (use the same function than server) (retry every 5 second)
    events.thread(function ()
        events.sleep(5)
        for i, n in pairs(job.nodes) do
            if n.port ~= job.me.port or n.ip ~= job.me.ip then
                print("Try to begin connection to "..n.ip..":"..n.port.." - index "..i)
                net.client(n, {initialize = init, send = send, receive = receive, finalize = final})
            end
        end
    end)
    
    -- Stop after 20 seconds
    events.sleep(20)
    print("Simple Network exit")

    events.exit()
end)

