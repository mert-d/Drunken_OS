--[[
    Unit Test: Utils & String Algorithms
    Verifies word wrapping, paragraph preservation, splitting, and trimming.
]]

package.path = "./?.lua;" .. package.path
local utils = require("lib.utils")

local function assert_eq(actual, expected, desc)
    if actual ~= expected then
        error(string.format("FAILED [%s]:\n  Expected: %s\n  Actual:   %s", desc, tostring(expected), tostring(actual)), 2)
    end
    print("  PASS: " .. desc)
end

print("=== Running Utils & wordWrap Tests ===")

-- 1. Trim tests
assert_eq(utils.trim("  hello world  "), "hello world", "Trim outer spaces")
assert_eq(utils.trim(""), "", "Trim empty string")
assert_eq(utils.trim(nil), "", "Trim nil")

-- 2. Split tests
local parts = utils.split("a,b,c", ",")
assert_eq(#parts, 3, "Split 3 elements count")
assert_eq(parts[1], "a", "Split element 1")
assert_eq(parts[2], "b", "Split element 2")
assert_eq(parts[3], "c", "Split element 3")

local emptyTokens = utils.split("line1\n\nline2", "\n")
assert_eq(#emptyTokens, 3, "Split consecutive newlines count")
assert_eq(emptyTokens[2], "", "Split empty middle token")

-- 3. wordWrap tests
local wrapped = utils.wordWrap("Short line", 20)
assert_eq(#wrapped, 1, "Short line does not wrap")
assert_eq(wrapped[1], "Short line", "Short line content")

local multi = utils.wordWrap("First line.\n\nSecond paragraph has enough words to wrap nicely.", 15)
assert_eq(multi[1], "First line.", "First paragraph content")
assert_eq(multi[2], "", "Empty line paragraph preservation")
assert_eq(multi[3]:sub(1, 1) ~= " ", true, "Line 3 no leading space")

-- Oversized single word
local longWord = utils.wordWrap("Supercalifragilistic", 8)
assert_eq(#longWord, 3, "Oversized word splits cleanly")
assert_eq(longWord[1], "Supercal", "Oversized chunk 1")
assert_eq(longWord[2], "ifragili", "Oversized chunk 2")
assert_eq(longWord[3], "stic", "Oversized chunk 3")

print(">>> All Utils tests passed successfully!\n")
return true
