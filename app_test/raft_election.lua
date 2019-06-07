--[[
Raft implementation - Only the leader election sub-problem
Based on with https://web.stanford.edu/~ouster/cgi-bin/papers/raft-atc14
--]]

---- Init

require("splay.base")
local json = require("json")
local urpc = require("splay.urpc")

-- Overwrite the print to show the job position (node index)
do
	local p = print
	print = function(...)
		p(job.position.." : "..(...)) 
	end
end

majority_threshold = #job.nodes / 2
thread_heartbeat = nil

volatile_state = {
    state = "follower", -- follower, candidate or leader
}

-- Save in stable storage (here just a file)
persistent_state = { 
    current_term = 0,
    voted_for = nil,
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

---- Utils functions

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
    set_election_timeout()

    -- If I was leader but obviously not anymore - remove pediodic heartbeat
    if thread_heartbeat ~= nil then 
        events.kill(thread_heartbeat)
    end
end

local inc = 0
function uprc_call_timeout(node, data, timeout) 
    inc = inc + 1 -- Unique name for each rpc
    local name = "urpc.call:"..inc
    local ok = false
    local term, res = nil, false
    local function call()
        term, res = urpc.call(node, data, timeout*10)
        ok = true
        events.fire(name)
    end
    local function timeout_rec()
        events.thread(function()
            events.sleep(timeout)
            if (ok == false) then 
                call()
                timeout_rec()
            end
        end)
    end
    call()
    timeout_rec()
    events.wait(name, timeout*10) -- After 9 retry stop anyway -> return nil, false
    return term, res
end

function send_vote_request(node, node_index)
    print("Send vote request to node "..json.encode(node_index))

    local term, vote_granted = uprc_call_timeout(node, {
        "request_vote", persistent_state.current_term, job.position
    }, rpc_timeout)
    return term, vote_granted
end

function send_append_entry(node_index, node, entry)
    print("Send append entry ("..json.encode(entry)..") to node "..node_index)

    local term, success = uprc_call_timeout(node, {
        "append_entry", persistent_state.current_term, job.position, entry
    }, rpc_timeout)
    return term, success
end

function heartbeat()
    for i, n in pairs(job.nodes) do
        if i ~= job.position then
            events.thread(function ()
                term, success = send_append_entry(i, n, nil) 
                if term ~= nil and term > persistent_state.current_term then
                    stepdown(term)
                end
            end)
        end
    end
end

function become_leader()
    print("I Become the LEADER !")
    volatile_state.state = "leader"
    -- cancelled timout election
    election_time = misc.time()
    -- trigger the heartbeart directly and periodically
    heartbeat()
    thread_heartbeat = events.periodic(heartbeat_timeout, function() heartbeat() end)
    -- No client simulation for now (because no replication log)
end

---- RPC functions

-- Append Entry RPC function used by leader for the heartbeat 
-- (avoiding new election) - entry == nil means heartbeat
-- Also normally used for log replication (not present here)
function append_entry(term, leader_id, entry)
    print("RPC Append entry FROM "..leader_id.." Term : "..term.." Entry : "..json.encode(entry))
    if term > persistent_state.current_term then
        stepdown(term)
    end
    set_election_timeout() -- reset the election timeout
    volatile_state.state = "follower" -- if candidate, return in follower state
    
    if entry == nil then
        -- HEARTBEAT
        return persistent_state.current_term, true
    else
        -- NORMAL Entry (Log replication feature - not present here) 
        return persistent_state.current_term, false
    end
end

-- Vote Request RPC function, called by candidate to get votes
function request_vote(term, candidate_id)
    print("RPC Request Vote FROM "..candidate_id.." Term : "..term)

    -- It the candidate is late - don't grant the vote
    if term < persistent_state.current_term then
        return persistent_state.current_term, false
    elseif term > persistent_state.current_term then
        stepdown(term)
    end

    local vote_granted = false

    -- Condition to grant the vote :
    --  (If the node doesn't already grant the vote to and other)
    if (persistent_state.voted_for == nil or persistent_state.voted_for == candidate_id) then
        -- Save the candidate vote
        persistent_state.voted_for = candidate_id
        save_persistent_state()
        vote_granted = true
        set_election_timeout() -- reset the election timeout
    end
    return persistent_state.current_term, vote_granted
end

---- Timeout/Trigger functions

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

function trigger_election_timeout()
    print("Election Trigger -> term+1, become candidate")
    volatile_state.state = "candidate"
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
                print("Vote Request result "..json.encode(term)..", "..json.encode(vote_granted).." from "..i)
                if vote_granted == true then
                    nb_vote = nb_vote + 1
                    -- If the majority grant the vote -> become the leader
                    if nb_vote > majority_threshold and volatile_state.state == "candidate" then 
                        become_leader()
                    end
                end
                if term ~= nil and term > persistent_state.current_term then
                    stepdown(term)
                end
            end)
        end
    end
end

---- Main

-- Init the UDP RPC server
urpc.server(job.me)

events.run(function()
    
    set_election_timeout() -- set the election timeout

    -- After 100 second the node will exit no matter what
    events.sleep(100)
    events.exit()
end)