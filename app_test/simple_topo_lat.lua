--[[
WITH this topology and 2 slayds 
<?xml version="1.0" encoding="ISO-8859-1"?>
<topology>
	<vertices>
		<vertex int_idx="1" role="virtnode" int_vn="1" />
		<vertex int_idx="2" role="virtnode" int_vn="2" />
	</vertices>
	<edges>
		<edge int_idx="1" int_src="1" int_dst="2" specs="client-stub" int_delayms="250" />
		<edge int_idx="2" int_src="2" int_dst="1" specs="client-stub" int_delayms="1000" />
	</edges>
	<specs>
		<client-stub dbl_plr="0" dbl_kbps="10000" int_delayms="5" int_qlen="10" />
	</specs>
</topology>
]]--

print("SIMPLE_TOPO.LUA START")
require("splay.base")

local events=require("splay.events")
local rpc=require("splay.rpc")
local net = require("splay.net")
local misc = require("splay.misc")

local rtt = 0
local t_end = 0

function print_server(data, ip, port)
    print("<<< "..ip..":"..port.." : "..data)
    if data == "hello" then
        u.s:sendto("world", ip, port)
    else
        t_end = misc.time()
    end
end
print("Start UDP server")
u = net.udp_helper(job.me.port, print_server)

events.run(function()

    print("Wait 2 seconds")
    events.sleep(2)
    print("Start send hello")

    local start = misc.time()
    for i, n in pairs(job.nodes) do
        if i ~= job.position then
            print(">>> "..n.ip..":"..n.port.." : hello")
            u.s:sendto("hello", n.ip, n.port)
        end
    end

    events.sleep(4)

    if t_end == 0 then
        local start = misc.time()
        for i, n in pairs(job.nodes) do
            if i ~= job.position then
                print(">>> "..n.ip..":"..n.port.." : hello")
                u.s:sendto("hello", n.ip, n.port)
            end
        end

        events.sleep(4)
    end

    final_time = t_end - start
    print("Time to n1 -> hello -> n2 -> world -> n1 : "..final_time)
    print("FINAL RTT : "..final_time.." sec")

    events.kill(u.server)
end)

print("SIMPLE_TOPO.LUA EXIT")
