--[[
Raft implementation - Only the leader election sub-problem
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

majority_threshold = #job.nodes / 2

volatile_state = {
    state = "follower", -- follower, candidate or leader
    commit_index -- used for log replication
}

-- Save in storage before rpc response (in file - it is a trick for persistency)
persistent_state = { 
    current_term = 0,
    voted_for = nil,
    log = {} -- Array of {term = associated_term, data = <change_state>}
}

-- Timeout for each purpose in second
election_timeout = 1.5 -- random: [election_timeout, 2 * election_timeout]
rpc_timeout = 0.5
heartbeat_timeout = 0.6

-- Timeout variable (to check if timeout has been canceled)
election_time = nil

-- File to save the persistent state
filename_persistent = "pers"..job.ref..".json"
local pers_file = io.open(filename_persistent, "r")
if pers_file ~= nil then
    persistent_state = json.decode(pers_file:read("*a"))
    pers_file:close()
end

-- Utils functions
function save_persistent_state()
    pers_file = io.open(filename_persistent, "w+")
    pers_file:write(json.encode(persistent_state))
    pers_file:close()
end

-- If someone have a bigger term -> stepdown (request or response)
function stepdown(term)
    print("Stepdown : "..term.." > "..persistent_state.current_term)
    persistent_state.current_term = tonumber(term)
    persistent_state.voted_for = nil
    save_persistent_state()
    volatile_state.state = "follower"
    aUpdateState()
    set_election_timeout()
end

function send_vote_request(node, node_index)
    aSendData(node_index, "SEND VOTE REQUEST")

    -- Here not really used because only election
    last_log_index = #persistent_state.log
    last_log_term = 0
    if last_log_index > 0 then
        last_log_term = persistent_state.log[#persistent_state.log].term
    end

    local term, vote_granted = urpc.call(node, {
        "request_vote", persistent_state.current_term, job.position, last_log_index, last_log_term
    }, rpc_timeout)
    if term == nil then -- Timeout occur retry
        print("RPC VOTE REQUEST Timeout retried - resend")
        term, vote_granted = send_vote_request(node, node_index) 
    end 
    aReceiveData(node_index, "RECEIVED VOTE REQUEST")
    return term, vote_granted
end

function send_append_entry(node_index, node, entry)
    aSendData(node_index, "SEND APPEND ENTRY")

    -- Used only for log replication
    -- local next_index = volatile_state_leader.next_index[node_index]
    local next_index = 1 -- No log replication then hardcoded
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
    -- CRASH POINT 1 2 3 4 5 : RECOVERY 0.5 : AFTER 2
    if volatile_state.state == "leader" then 
        for i, n in pairs(job.nodes) do
            if i ~= job.position then
                events.thread(function ()
                    term, success = send_append_entry(i, n, nil) 
                    if term > persistent_state.current_term then
                        stepdown(term)
                    end
                end)
            end
        end
    end
end

function become_leader()
    volatile_state.state = "leader"
    aUpdateState()
    -- cancelled timout election
    election_time = misc.time()
    -- trigger the heartbeart directly and periodically
    heartbeat()
    events.periodic(heartbeat_timeout, function() heartbeat() end)

    -- No client simulation for now (because no replication log)
end

-- RCP functions

-- Append Entry RPC function used by leader for the heartbeat (avoiding new election) - entry == nil means heartbeat
-- Also normally used for log replication (not present here)
function append_entry(term, leader_id, prev_log_index, prev_log_term, entry, leader_commit)
    aReceiveData(leader_id, " RCP APPEND ENTRY")
    if term > persistent_state.current_term then
        stepdown(term)
    end
    -- reset the election timeout (avoiding new election)
    set_election_timeout()
    volatile_state.state = "follower" -- if candidate, return in follower state
    
    -- HEARTBEAT
    if entry == nil then
        aSendData(leader_id, "SEND RESULT APPEND ENTRY")
        return persistent_state.current_term, true
    else
        -- NORMAL Entry (Log replication feature - not present here) 
        aSendData(leader_id, "SEND RESULT APPEND ENTRY")
        return persistent_state.current_term, false
    end
end

-- Vote Request RPC function, called by candidate to get votes
function request_vote(term, candidate_id, last_log_index, last_log_term)
    aReceiveData(candidate_id, " RCP REQUEST VOTE")
    
    -- It the candidate is late - don't grant the vote
    if term < persistent_state.current_term then
        aSendData(candidate_id, "SEND RESULT REQUEST VOET")
        return persistent_state.current_term, false
    elseif term > persistent_state.current_term then
        stepdown(term)
    end

    local vote_granted = false

    -- Condition to grant the vote :
    --  (If the node doesn't already grant the vote to and other) and 
    --  (log of the candidate is updated - not usefull if only election)
    if ((persistent_state.voted_for == nil or persistent_state.voted_for == candidate_id) 
        and last_log_index >= #persistent_state.log) then
        -- Save the candidate vote
        persistent_state.voted_for = candidate_id
        save_persistent_state()
        vote_granted = true
        set_election_timeout() -- reset the election timeout
    end
    aSendData(candidate_id, "SEND RESULT REQUEST VOET")
    return persistent_state.current_term, vote_granted
end

-- Timeout function
function set_election_timeout()
    election_time = misc.time()
    local time = election_time
    events.thread(function ()
        -- Randomize the sleeping time = [election_timeout, 2 * election_timeout] 
        events.sleep(((math.random() + 1.0) * election_timeout))
        -- if the timeout is not cancelled -> trigger election
        if (time == election_time) then trigger_election_timeout() end
    end)
end

-- Trigger function
function trigger_election_timeout()
    print("Election Trigger - upgrade term and become candidate ")
    volatile_state.state = "candidate"
    aUpdateState()
    persistent_state.current_term = persistent_state.current_term + 1
    persistent_state.voted_for = job.position
    save_persistent_state()
    -- If conflict in this election, and new election can be trigger
    set_election_timeout()
    local nb_vote = 1
    for i, n in pairs(job.nodes) do
        if i ~= job.position then
            events.thread(function ()
                local term, vote_granted = send_vote_request(n, i)
                print("Vote Request result "..term.." : "..json.encode(vote_granted).." from "..json.encode(i).." - "..json.encode(n))
                if vote_granted == true then
                    nb_vote = nb_vote + 1
                    -- If the majority grant the vote -> become the leader
                    if nb_vote > majority_threshold and volatile_state.state == "candidate" then 
                        become_leader()
                    end
                end
                if term > persistent_state.current_term then
                    stepdown(term)
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

    -- After 100 second the node will exit no matter what
    events.sleep(100)
    events.exit()
end)