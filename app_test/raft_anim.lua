--[[

Raft leader election implementation with anim log (see tools)

--]]

function aUpdateState(state, term)
    print("ANIM STATE "..job.position.." : "..state.." : "..term)
end

function aConnected(to)
    print("ANIM CONNETED "..job.position.." : "..to)
end

function aDisconnected(to)
    print("ANIM DISCONNETED "..job.position.." : "..to)
end

function aReceiveData(socket)
    local data, err = socket:receive("*l")
    if (data ~= nil) then
        s_data = misc.split(data)
        uuid = s_data[1]
        s_data[1] = ""
        data = string.sub(table.concat(s_data ," "), 2)
        print("ANIM RDATA "..job.position.." <- "..socket.job_index.." : "..uuid.." : "..data)
    end
    
    return data, err
end

function aSendData(socket, data)
    local uuid = misc.random_string(20)
    print("ANIM SDATA "..job.position.." -> "..socket.job_index.." : "..uuid.." : "..data)
    socket:send(uuid.." "..data.."\n")
end

print("ANIM START "..job.position)

require("splay.base")
local math = require("math")
local net = require("splay.net")
local misc = require("splay.misc")

-- Index in the list of nodes -> Send to other of nodes.
job_index = job.position

-- Minimal timeout for each purpose in second
election_timeout = 1.5
rpc_timeout = 0.2
heartbeat_timeout = 0.6

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

aUpdateState("follower", 0)

-- sockets table of each connected node (nil == cot connected to)
sockets = {}

-- Timeout variable (to check if timeout has been canceled)
rpc_time = {}
election_time = nil
heart_time = nil

-- helper functions
function set_contains(set, key)
    return set[key] ~= nil
end

function stepdown(term)
    state.term = tonumber(term)
    state.state = "follower"
    aUpdateState(state.state, state.term)
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
        if (time == heart_time and state.leader == job_index) then
            trigger_heart_timeout()
        end
    end)
end

-- Trigger functions
function trigger_rpc_timeout(s)
    local ip, port = s:getpeername()
    if (state.state == "candidate") then
        set_rpc_timeout(s.job_index)
        aSendData(s, vote_msg.req.." "..state.term)
    end
end

function trigger_election_timeout()
    if (state.state == "follower" or state.state == "candidate") then 
        set_election_timeout()
        state.term = state.term + 1
        state.state = "candidate"
        aUpdateState(state.state, state.term)
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
            aSendData(s,heartbeat_msg.." "..state.term)
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
        local data, err = aReceiveData(s)
        if data == nil then
            print("ERROR : "..err)
            return false
        else
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
                    end
                    rpc_time[s.job_index] = nil
                    if misc.size(state.votes) > misc.size(job.nodes) /2 then
                        state.state = "leader"
                        aUpdateState(state.state, state.term)
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
                aSendData(s,vote_msg.rep.." "..state.term.." "..state.voteFor)
            elseif table_d[1] == heartbeat_msg then
                -- HEARBEAT
                set_election_timeout()
                state.term = tonumber(table_d[2])
            else
                print("Warning : unkown message -> "..table_d[1])
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
        aConnected(s.job_index)
    else
        local d = s:receive()
        s:send(job_index.."\n")
        s.job_index = tonumber(d)
        aConnected(s.job_index)
    end
    if  sockets[s.job_index] ~= nil then
        error("Already connect to "..s.job_index.." in a other socket")
    else
        sockets[s.job_index] = s
    end
end

function final(s)
    local ip, port = s:getpeername()
    aDisconnected(s.job_index)
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
    
    -- Stop after 10 seconds
    events.sleep(20)
    print("ANIM EXIT "..job.position)
    events.exit()
end)
