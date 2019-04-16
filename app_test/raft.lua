--[[

Raft leader election implementation

--]]

-- FOR local test - without splay
--[[ socket = require("socket")
rs = require("splay.restricted_socket")
rs.init(settings)
socket = rs.wrap(socket)
package.loaded['socket.core'] = socket

job = {}
job.me = {ip = '127.0.0.1', port= tonumber(arg[1])}
--job.nodes = {{ip= '127.0.0.1', port= 15001 }, {ip= '127.0.0.1', port= 15002 },{ip= '127.0.0.1', port= 15003 },{ip= '127.0.0.1', port= 15004 },{ip= '127.0.0.1', port= 15005 }}
job.nodes = {{ip= '127.0.0.1', port= 15001 }, {ip= '127.0.0.1', port= 15002 }, {ip= '127.0.0.1', port= 15003 }} ]]

print("Begin Raft : I am "..job.me.ip..":"..job.me.port)

require("splay.base")
local math = require("math")
local net = require("splay.net")
local misc = require("splay.misc")

-- Index in the list of nodes -> Send to other of nodes.
job_index = -1
for k, n in pairs(job.nodes) do
    if (job.me.ip == n.ip and job.me.port == n.port) then
        job_index = k
        break
    end
end
if (job_index == -1) then
    error("Can't find me in the nodes array")
end
print("I am the job number "..job_index)

-- Minimal timeout for each purpose in second
election_timeout = 2.0
rpc_timeout = 0.3
heartbeat_timeout = 0.8

-- Constant msg send and receive between nodes
vote_msg = {req = "VOTEREQ", rep = "VOTEREP"}
heartbeat_msg = "HEARTBEAT"

-- State of this node
state = {
    term = 0,
    voteFor = nil, -- index in the node list
    state = "follower", -- follower, candidat, or leader
    leader = nil, --  {ip = ip, port = port} of the leader
    votes = {}
}

-- sockets table of each connected node (nil == cot connected to)
sockets = {}

-- Timeout variable (if x_time < misc.time() then trigger the corresponded timeout)
rpc_time = {}
election_time = nil
heart_time = nil

-- helper functions
function is_leader(job_index)
    return state.leader == job_index
end

function set_contains(set, key)
    return set[key] ~= nil
end

function stepdown(term)
    print("Stepdown")
    state.term = tonumber(term)
    state.state = "follower"
    state.voteFor = nil
    set_election_timeout()
end

-- Timeout functions
function set_election_timeout()
    election_time = misc.time()
    local time = election_time
    events.thread(function ()
        events.sleep(((math.random() + 1.0) * election_timeout))
        -- if the timeout is not cancelled
        if (time == election_time) then
            trigger_election_timeout()
        end
    end)
end

function set_rpc_timeout(node_index)
    rpc_time[node_index] = misc.time()
    local time = rpc_time[node_index]
    events.thread(function ()
        events.sleep((math.random() * 0.2) + rpc_timeout)
        -- if the timeout is not cancelled
        if (time == rpc_time[node_index] and sockets[node_index] ~= nil) then
            trigger_rpc_timeout(sockets[node_index])
        end
    end)
end

function set_heart_timeout()
    heart_time = misc.time()
    local time = heart_time
    events.thread(function ()
        events.sleep(heartbeat_timeout)
        -- if the timeout is not cancelled
        if (time == heart_time and is_leader(job_index)) then
            trigger_heart_timeout()
        end
    end)
end

-- Trigger functions
function trigger_rpc_timeout(s)
    local ip, port = s:getpeername()
    if (state.state == "candidate") then
        print("Send new rpc timeout for "..ip..":"..port.." - index "..s.job_index)
        set_rpc_timeout(s.job_index)
        s:send(vote_msg.req.." "..state.term.."\n")
    end
end

function trigger_election_timeout()
    if (state.state == "follower" or state.state == "candidate") then 
        set_election_timeout()
        state.term = state.term + 1
        state.state = "candidate"
        state.voteFor = job_index
        state.votes = {}
        state.votes[job_index] = true
        for k, s in pairs(sockets) do
            rpc_time[s.job_index] = nil
            trigger_rpc_timeout(s)
        end
    end
end

function trigger_heart_timeout()
    state.term = state.term + 1
    for k, s in pairs(sockets) do
        if s ~= nil then
            s:send(heartbeat_msg.." "..state.term.."\n")
        end
    end
    set_heart_timeout()
end

-- Socket fonctions
function send(s)
    set_rpc_timeout(s)
    while events.yield() do
        events.sleep(3)
    end
end

function receive(s)
    local ip, port = s:getpeername()
    while events.yield() do
        local data, err = s:receive("*l")
        if data == nil then
            print("ERROR : "..err)
            return false
        else
            print("I receive "..data.." From "..ip..":"..port)
            local table_d = misc.split(data, " ")
            if table_d[1] == vote_msg.rep then
                -- VOTE REP
                local term, vote = tonumber(table_d[2]), tonumber(table_d[3])
                if term > state.term then
                    stepdown(term)
                end
                if term == state.term and state.state == "candidate" then
                    if vote == job_index then
                        state.votes[s.job_index] = true
                        print("I have received one vote from "..s.job_index.." | cnt = "..misc.size(state.votes))
                    end
                    rpc_time[s.job_index] = nil
                    if misc.size(state.votes) > misc.size(job.nodes) /2 then
                        print("I become the leader")
                        state.state = "leader"
                        state.leader = job_index
                        trigger_heart_timeout()
                    end
                end
            elseif table_d[1] == vote_msg.req then
                -- VOTE REQ
                local term = tonumber(table_d[2])
                if term > state.term then
                    stepdown(term)
                end
                if term == state.term and (state.voteFor == nil or state.voteFor == s.job_index) then
                    state.voteFor = s.job_index
                    set_election_timeout()
                end
                s:send(vote_msg.rep.." "..state.term.." "..state.voteFor.."\n")
            elseif table_d[1] == heartbeat_msg then
                -- HEARBEAT
                set_election_timeout()
                state.term = tonumber(table_d[2])
            else
                print("Warning : unkown message"..table_d[1])
            end
        end
    end
end

function init(s, connect)
    -- if connect == true => client 
    -- If this function returns false, The connection will be closed immediatly
    local ip, port = s:getpeername()
    if connect then
        s:send(job_index.."\n")
        local d = s:receive()

        s.job_index = tonumber(d)

        print("connection to: "..ip..":"..port.." - index = "..s.job_index)
    else
        local d = s:receive()
        s:send(job_index.."\n")

        s.job_index = tonumber(d)

        print("connection from: "..ip..":"..port.." - index = "..s.job_index)
    end
    if  sockets[s.job_index] ~= nil then
        print("I am already connect to "..s.job_index )
        error("Already connect in a other socket")
    else
        print("Save socket "..s.job_index.." in the table")
        sockets[s.job_index] = s
    end
end

function final(s)
    local ip, port = s:getpeername()
    print("Closing: "..ip..":"..port.." - index "..s.job_index)
    sockets[s.job_index] = nil
end

events.run(function()
    -- Accept connection from other nodes
    net.server(job.me.port, {initialize = init, send = send, receive = receive, finalize = final})
    
    -- Launch connection to each orther node (use the same function than server) (retry every 5 second)
    events.thread(function ()
        while events.yield() do
            for i, n in pairs(job.nodes) do
                if sockets[i] == nil and i ~= job_index then
                    print("Try to begin connection to "..n.ip..":"..n.port.." - index "..i)
                    net.client(n, {initialize = init, send = send, receive = receive, finalize = final})
                end
            end
            events.sleep(5)
        end
    end)

    -- Election manage 
    set_election_timeout()
    
    -- Stop after 20 seconds
    events.sleep(20)
    print("Raft exit")
    events.exit()
end)

