--[[
Complete Raft implementation
Helped with https://web.stanford.edu/~ouster/cgi-bin/papers/raft-atc14
--]]
require("splay.base")
local json = require("json")
local urpc = require("splay.urpc")

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
        next_index = {}, -- Array 
        match_index = {} -- Array
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
rpc_timeout = 0.2
heartbeat_timeout = 0.6

-- Timeout variable (to check if timeout has been canceled)
rpc_time = {}
election_time = nil
heart_time = nil

local pers_file = io.open("pers.json", "r")
if pers_file ~= nil then
    persistent_state = json.decode(pers_file:read("*a"))
    pers_file.close()
end

volatile_state_leader = state_leader_init()

-- Utils functions
function save_persistent_state()
    pers_file = io.open("pers.json", "w+")
    pers_file:write(json.encode(persistent_state))
    pers_file.close()
end

function send_vote_request(node)
    last_log_index = #persistent_state.log
    last_log_term = 0
    if last_log_index > 0 then
        last_log_term = persistent_state.log[#persistent_state.log].term
    end
    local term, vote_granted = urpc.call(node, {
        "request_vote",  persistent_state.current_term, job.position, last_log_index, last_log_term
    }, rpc_timeout)
    if term == nil then 
        term, vote_granted = send_vote_request(node) 
    end -- Timeout occur retry
    return term, vote_granted
end

function send_append_entry(node_index, node, entry)
    local next_index = volatile_state_leader.next_index[i]
    local prev_log_index = next_index - 1
    local prev_log_term = 0
    if #persistent_state.log > 1 then
        local prev_log_term = persistent_state.log[next_index - 1].term
    end
    local term, success = urpc.call(node, {
        "append_entry", job.position, prev_log_index, prev_log_term, entry, volatile_state.commit_index
    }, rpc_timeout)
    if term == nil then  -- Timeout
        term, success = send_append_entry(node_index, node, entry)
    end
    return term, success
end

function heartbeat()
    for i, n in pairs(job.nodes) do
        if i ~= job.position then
            events.thread(function () send_append_entry(i, n, nil) end)
        end
    end
end

function become_leader()
    heartbeat()
    events.periodic(heartbeat_timeout, function() heartbeat() end)
    -- No client simulation for now
end

-- RCP functions
function append_entry(term, leader_id, prev_log_index, prev_log_term, entry, leader_commit)
    print("APPEND ENTRY FROM "..leader_id.." Term : "..term.." Entry : "..json.encode(entry))
    set_election_timeout()
    local success = false
    if prev_log_index > 1 and  then

    end
    
    if success then
        save_persistent_state() -- Save persistant state
    end
    return persistent_state.current_term, success
end

function request_vote(term, candidate_id, prev_log_index, prev_log_term)
    print("REQUEST VOTE FROM "..candidate_id.." Term : "..term)
    set_election_timeout()
    local vote_granted = nil

    if success then
        save_persistent_state() -- Save persistant state
    end
    return persistent_state.current_term, persistent_state.voted_for
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
    persistent_state.current_term = persistent_state.current_term + 1
    persistent_state.voted_for = job.position
    save_persistent_state()
    set_election_timeout()
    local nb_vote = 0
    for i, n in pairs(job.nodes) do
        if i ~= job.position then
            events.thread(function ()
                local term, vote_granted = send_vote_request(node)
                if vote_granted == true then
                    nb_vote = nb_vote + 1
                    if nb_vote > majority_threshold then -- Become the leader
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

    -- Election manage 
    set_election_timeout()
    events.exit()
end)

