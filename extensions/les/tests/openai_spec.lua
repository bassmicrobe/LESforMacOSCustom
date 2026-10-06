-- SPDX-License-Identifier: MIT

local json = require("dkjson")

local function makeClient(options)
    options = options or {}
    local state = { results = {}, requests = 0 }
    local environment = setmetatable({
        settingsManager = { openaikey = { value = "test-key" } },
        hs = {
            json = {
                encode = options.encode or json.encode,
                decode = options.decode or function(body)
                    local value, _, err = json.decode(body)
                    if err then error(err) end
                    return value
                end,
            },
            http = {
                asyncPost = function(_, _, _, callback)
                    if options.startError then error(options.startError) end
                    state.requests = state.requests + 1
                    state.respond = callback
                end,
            },
        },
    }, { __index = _G })
    local client = assert(loadfile("extensions/les/ai/openai.lua", "t", environment))()
    function state.send()
        client.chat({ { role = "user", content = "Suggest a bass sound" } }, function(reply, err)
            state.results[#state.results + 1] = { reply = reply, err = err }
        end)
    end
    return state
end

describe("AI request completion", function()
    it("delivers a successful response once", function()
        local state = makeClient()
        state.send()
        state.respond(200, '{"choices":[{"message":{"content":"Try a sine wave"}}]}')
        assert.are.same({ { reply = "Try a sine wave" } }, state.results)
    end)

    it("releases callers from loading for malformed success responses", function()
        for _, body in ipairs({
            '{"choices":true}',
            '{"choices":[true]}',
            '{"choices":[{"message":42}]}',
            '{"choices":[{"message":{"content":false}}]}',
            '{"choices":[]}',
            'not json',
        }) do
            local state = makeClient()
            state.send()
            state.respond(200, body)
            assert.are.equal(1, #state.results, body)
            assert.is_nil(state.results[1].reply)
            assert.is_string(state.results[1].err)
        end
    end)

    it("reports HTTP failures even when the upstream error has an unexpected shape", function()
        for _, body in ipairs({
            '{"error":true}',
            '{"error":{"message":{}}}',
            '{"error":"Service unavailable"}',
            'not json',
        }) do
            local state = makeClient()
            state.send()
            state.respond(503, body)
            assert.are.equal(1, #state.results, body)
            assert.is_nil(state.results[1].reply)
            assert.matches("503", state.results[1].err, 1, true)
        end
    end)

    it("reports transport errors", function()
        local state = makeClient()
        state.send()
        state.respond(-1, "offline")
        assert.are.equal(1, #state.results)
        assert.is_nil(state.results[1].reply)
        assert.is_string(state.results[1].err)
    end)

    it("never returns upstream error messages that may contain credentials or user data", function()
        for _, status in ipairs({ 400, 401, 403, 404, 429, 500 }) do
            local state = makeClient()
            state.send()
            state.respond(status, json.encode({ error = {
                message = "Incorrect API key: test-key; user payload: private project name",
                code = "unrecognized-test-key",
                type = "unrecognized-private-project-name",
            } }))
            assert.are.equal(1, #state.results)
            local err = state.results[1].err
            assert.is_string(err)
            assert.matches(tostring(status), err, 1, true)
            assert.is_nil(err:find("test-key", 1, true))
            assert.is_nil(err:find("private project name", 1, true))
            assert.is_nil(err:find("unrecognized", 1, true))
        end
    end)

    it("distinguishes quota failures using a recognized error code without echoing the message", function()
        for _, apiError in ipairs({
            { code = "insufficient_quota" },
            { code = "credit_balance_exhausted" },
            { code = "organization_spend_limit_exceeded" },
            { code = "project_spend_limit_exceeded" },
            { code = "organization_usage_limit_exceeded" },
            { type = "insufficient_quota" },
        }) do
            local state = makeClient()
            state.send()
            state.respond(429, json.encode({ error = {
                code = apiError.code,
                type = apiError.type,
                message = "test-key has exceeded its budget",
            } }))
            assert.matches("429", state.results[1].err, 1, true)
            assert.matches("利用上限", state.results[1].err, 1, true)
            assert.is_nil(state.results[1].err:find("test-key", 1, true))
        end
    end)

    it("does not expose credential-bearing transport, encoding, or decoding failures", function()
        local cases = {
            { state = makeClient({ encode = function() error("encoding failed: test-key") end }) },
            { state = makeClient({ startError = "transport failed: test-key" }) },
            { state = makeClient({ decode = function() error("decoding failed: test-key") end }), status = 429 },
            { state = makeClient(), status = -1 },
        }
        for _, case in ipairs(cases) do
            local state = case.state
            state.send()
            if state.respond then
                state.respond(case.status, '{"error":{"message":"test-key was rejected"}}')
            end
            assert.are.equal(1, #state.results)
            assert.is_string(state.results[1].err)
            assert.is_nil(state.results[1].err:find("test-key", 1, true))
        end
    end)

    it("reports encoding failures without sending a request", function()
        for _, encode in ipairs({
            function() error("cannot encode") end,
            function() return nil end,
        }) do
            local state = makeClient({ encode = encode })
            state.send()
            assert.are.equal(0, state.requests)
            assert.are.equal(1, #state.results)
            assert.is_string(state.results[1].err)
        end
    end)

    it("reports a request that could not start", function()
        local state = makeClient({ startError = true })
        state.send()
        assert.are.equal(1, #state.results)
        assert.is_string(state.results[1].err)
    end)
end)
