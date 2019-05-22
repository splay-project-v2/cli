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
    last_applied = 0
}
volatile_state_leader = {
    next_index = {}, -- Array 
    match_index = {} -- Array
}

-- Save in storage before rpc response (in file - it is a trick)
persistent_state = { 
    current_term = 0,
    voted_for = nil,
    log = {}
}

local pers_file = io.open("pers.json", "r")
if pers_file ~= nil then
    persistent_state = json.decode(pers_file:read("*a"))
    pers_file.close()
end

-- Utils functions
function save_persistent_state()
    pers_file = io.open("pers.json", "w+")
    pers_file:write(json.encode(persistent_state))
    pers_file.close()
end

-- RCP functions
function append_entry(term, leader_id, prev_log_index, prev_log_term, entry, leader_commit)
    print("APPEND ENTRY FROM "..leader_id)
    local success = false


    if success then
        save_persistent_state() -- Save persistant state
    end
    return persistent_state.current_term, success
end

function request_vote(term, leader_id, prev_log_index, prev_log_term)
    print("REQUEST VOTE")
    local vote_granted = nil

    if success then
        save_persistent_state() -- Save persistant state
    end
    return persistent_state.current_term, persistent_state.voted_for
end

-- Minimal timeout for each purpose in second
election_timeout = 1.5
rpc_timeout = 0.2
heartbeat_timeout = 0.6

-- Timeout variable (to check if timeout has been canceled)
rpc_time = {}
election_time = nil
heart_time = nil

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
                res = urpc.call(n, {"append_entry", 5, job.position})
                if res == true then
                    nb_vote = nb_vote + 1
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

