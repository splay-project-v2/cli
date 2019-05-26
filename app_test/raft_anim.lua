--[[
Complete Raft implementation
Helped with https://web.stanford.edu/~ouster/cgi-bin/papers/raft-atc14
--]]
require("splay.base")
local json = require("json")
local urpc = require("splay.urpc")

print("ANIM START "..job.position)

function aUpdateState()
    print("ANIM STATE "..job.position.." : "..volatile_state.state.." : "..persistent_state.current_term)
end

function aReceiveData(from, data)
    print("ANIM RDATA "..job.position.." <- "..math.floor(from).." : uuid : "..data)
end

function aSendData(to, data)
    print("ANIM SDATA "..job.position.." -> "..math.floor(to).." : uuid : "..data)
end


majority_threshold = misc.size(job.nodes) / 2

volatile_state = {
    commit_index = 0,
    last_applied = 0,
    state = "follower" -- follower, candidate or leader
}

function state_leader_init()
    local next_index_tmp = {}
    local match_index_tmp = {}
    for i, n in pairs(job.nodes) do
        next_index_tmp[i] = #persistent_state.log + 1
        match_index_tmp[i] = 0
    end
    return  {
        next_index = next_index_tmp, -- Array 
        match_index = match_index_tmp -- Array
    }
end

-- Save in storage before rpc response (in file - it is a trick)
persistent_state = { 
    current_term = 0,
    voted_for = nil,
    log = {} -- Array of {term = associated_term, data = <change_state>}
}

-- Minimal timeout for each purpose in second
election_timeout = 1.5
rpc_timeout = 0.4
heartbeat_timeout = 0.8

-- Timeout variable (to check if timeout has been canceled)
rpc_time = {}
election_time = nil
heart_time = nil
filename_persistent = "pers"..job.ref..".json"
local pers_file = io.open(filename_persistent, "r")
if pers_file ~= nil then
    persistent_state = json.decode(pers_file:read("*a"))
    pers_file:close()
end

volatile_state_leader = state_leader_init()

-- Utils functions
function save_persistent_state()
    pers_file = io.open(filename_persistent, "w+")
    pers_file:write(json.encode(persistent_state))
    pers_file:close()
end

function send_vote_request(node, node_index)
    aSendData(node_index, "SEND VOTE REQUEST")
    print("Send request to "..json.encode(node))

    last_log_index = #persistent_state.log
    last_log_term = 0
    if last_log_index > 0 then
        last_log_term = persistent_state.log[#persistent_state.log].term
    end
    local term, vote_granted = urpc.call(node, {
        "request_vote", persistent_state.current_term, job.position, last_log_index, last_log_term
    }, rpc_timeout)
    if term == nil then -- Timeout occur retry
        print("RPC Timeout occured")
        term, vote_granted = send_vote_request(node, node_index) 
    end 
    aReceiveData(node_index, "RECEIVED VOTE REQUEST")
    return term, vote_granted
end

function send_append_entry(node_index, node, entry)
    aSendData(node_index, "SEND APPEND ENTRY")
    print("Send append entry to "..json.encode(node).." my volatile leader state "..json.encode(volatile_state_leader))
    local next_index = volatile_state_leader.next_index[node_index]
    local prev_log_index = next_index - 1
    local prev_log_term = 0
    if #persistent_state.log > 1 then
        local prev_log_term = persistent_state.log[next_index - 1].term
    end
    local term, success = urpc.call(node, {
        "append_entry", persistent_state.current_term, job.position, prev_log_index, prev_log_term, entry, volatile_state.commit_index
    }, rpc_timeout)
    if term == nil then  -- Timeout
        term, success = send_append_entry(node_index, node, entry)
    end
    aReceiveData(node_index, "RECEIVED APPEND ENTRY")
    return term, success
end

function heartbeat()
    -- CRASH POINT 1 2 3 : RECOVERY 0.5 : RANDOM 0.2
    for i, n in pairs(job.nodes) do
        if i ~= job.position then
            events.thread(function () 
                send_append_entry(i, n, nil) 
            end)
        end
    end
end

function become_leader()
    print("I AM THE LEADER NOW")
    volatile_state.state = "leader"
    aUpdateState()
    -- cancelled timout election
    election_time = misc.time()
    heartbeat()
    events.periodic(heartbeat_timeout, function() heartbeat() end)
    -- No client simulation for now
end

-- RCP functions
function append_entry(term, leader_id, prev_log_index, prev_log_term, entry, leader_commit)
    aReceiveData(leader_id, " RCP APPEND ENTRY")

    print("APPEND ENTRY FROM "..leader_id.." Term : "..term.." Entry : "..json.encode(entry))
    volatile_state.state = "follower"
    aUpdateState()
    set_election_timeout()
    -- HEARTBEAT
    if entry == nil then
        aSendData(leader_id, "SEND RESULT REQUEST VOET")
        return persistent_state.current_term, true
    end
    local success = false
    if success then
        save_persistent_state() -- Save persistant state
    end
    aSendData(leader_id, "SEND RESULT APPEND ENTRY")
    return persistent_state.current_term, success
end

function request_vote(term, candidate_id, last_log_index, last_log_term)
    aReceiveData(candidate_id, " RCP REQUEST VOTE")

    print("REQUEST VOTE FROM "..candidate_id.." Term : "..term)
    
    if term < persistent_state.current_term then
        aSendData(candidate_id, "SEND RESULT REQUEST VOET")
        return persistent_state.current_term, false
    end
    local vote_granted = false
    if ((persistent_state.voted_for == nil or persistent_state.voted_for == candidate_id) 
        and last_log_index >= #persistent_state.log) or term > persistent_state.current_term then
        persistent_state.voted_for = candidate_id
        save_persistent_state() -- Save persistant state

        vote_granted = true
        set_election_timeout()
    end
    aSendData(candidate_id, "SEND RESULT REQUEST VOET")
    return persistent_state.current_term, vote_granted
end

-- Timeout functions
function set_election_timeout()
    election_time = misc.time()
    local time = election_time
    events.thread(function ()
        events.sleep(((math.random() + 1.0) * election_timeout))
        -- if the timeout is not cancelled
        if (time == election_time) then trigger_election_timeout() end
    end)
end

-- Trigger functions
function trigger_election_timeout()
    print("ELECTION TRIGGER - BECOME CANDIDATE")
    volatile_state.state = "candidate"
    persistent_state.current_term = persistent_state.current_term + 1
    persistent_state.voted_for = job.position
    aUpdateState()
    save_persistent_state()
    set_election_timeout()
    local nb_vote = 1
    for i, n in pairs(job.nodes) do
        if i ~= job.position then
            events.thread(function ()
                local term, vote_granted = send_vote_request(n, i)
                print("Vote Request result "..term.." : "..json.encode(vote_granted).." from "..json.encode(n))
                if vote_granted == true then
                    nb_vote = nb_vote + 1
                    if nb_vote > majority_threshold and volatile_state.state ~= "leader" then -- Become the leader
                        become_leader()
                    end
                end
            end)
        end
    end
end

-- UDP RPC server
urpc.server(job.me)

-- Main
events.run(function()

    aUpdateState()
    
    -- Election manage 
    set_election_timeout()

    events.sleep(10)

    print("ANIM EXIT "..job.position)

    events.exit()
end)

