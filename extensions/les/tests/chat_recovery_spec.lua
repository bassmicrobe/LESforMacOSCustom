-- SPDX-License-Identifier: MIT
package.path = package.path .. ";extensions/les/?.lua"

local function harness()
    local state = {requests = {}, callbacks = {}, scripts = {}}
    local ai = {chat = function(messages, callback)
        state.requests[#state.requests + 1] = messages
        state.callbacks[#state.callbacks + 1] = callback
    end}
    local environment = setmetatable({
        L = function(key) return key end,
        require = function(name)
            if name == "ai.openai" then return ai end
            return require(name)
        end,
    }, {__index = _G})
    environment._G = environment
    local chat = assert(loadfile("extensions/les/ai/chat.lua", "t", environment))()
    for i = 1, 100 do
        local name, value = debug.getupvalue(chat.toggle, i)
        if not name then break end
        if name == "handleSend" then state.send = value break end
    end
    assert(state.send)
    for i = 1, 100 do
        local name = debug.getupvalue(state.send, i)
        if not name then break end
        if name == "_webview" then
            debug.setupvalue(state.send, i, {evaluateJavaScript = function(_, script)
                state.scripts[#state.scripts + 1] = script
            end})
            break
        end
    end
    return state
end

describe("AI chat request recovery", function()
    it("does not submit a second billable request while one is pending", function()
        local state = harness()
        state.send("first")
        state.send("duplicate")
        assert.are.equal(1, #state.requests)
    end)

    it("does not retain a failed turn when retrying", function()
        local state = harness()
        state.send("retry this")
        state.callbacks[1](nil, "request failed")
        state.send("retry this")
        assert.are.equal(2, #state.requests)
        assert.are.equal(2, #state.requests[2]) -- system + one user turn
        assert.are.equal("retry this", state.requests[2][2].content)
    end)

    it("keeps completed turns in the next request", function()
        local state = harness()
        state.send("first")
        state.callbacks[1]("answer", nil)
        state.send("second")
        assert.same({"system", "user", "assistant", "user"}, {
            state.requests[2][1].role, state.requests[2][2].role,
            state.requests[2][3].role, state.requests[2][4].role,
        })
        assert.are.equal("answer", state.requests[2][3].content)
    end)
end)
