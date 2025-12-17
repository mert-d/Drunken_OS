--Configuratio
local PROTOCOL_NAME                 = "auth.secure.v1"
local VENDOR_REGISTRY_PATH          = "/vendors.jsonl"
local AUTH_LOG_FILE_PATH            = "/auth.log.jsonl"
local REGISTRY_HOT_RELOAD_MILLIS    = 5 * 1000

local CODE_LENGTH_DIGITS            = 6
local CODE_TIME_TO_LIVE_MILLIS      = 5 * 60 * 1000
local MAX_VERIFY_ATTEMPTS_PER_CODE  = 5

--Dependencies
local secure = require("secure")

--Server state
local vendor_cache_by_id = {}
local vendor_last_loaded_millis = 0
local pending_requests_by_id = {}

--Utilities
local function current_time_millis()
  return os.epoch("utc")
end

local function open_any_wireless_modem()
  for _, side_name in ipairs({ "left","right","top","bottom","front","back" }) do
    if peripheral.getType(side_name) == "modem" then
      rednet.open(side_name)
    end
  end
end

local function random_digit_string(length_digits)
  secure.seed_rng()
  local digits = "0123456789"
  local buffer = {}
  for index = 1, length_digits do
    local random_index = math.random(#digits)
    buffer[index] = digits:sub(random_index, random_index)
  end
  return table.concat(buffer)
end

local function append_log_line(event_table)
  event_table.timestamp_ms = current_time_millis()
  local ok_serialize, json_line = pcall(textutils.serializeJSON, event_table)
  if not ok_serialize then return end
  local file_mode = fs.exists(AUTH_LOG_FILE_PATH) and "a" or "w"
  local file_handle = fs.open(AUTH_LOG_FILE_PATH, file_mode)
  if not file_handle then return end
  file_handle.write(json_line)
  file_handle.write("\n")
  file_handle.close()
end

local function load_vendor_registry_file()
  local vendor_map = {}
  if not fs.exists(VENDOR_REGISTRY_PATH) then
    append_log_line({ level = "warn", event = "vendor_registry_missing", path = VENDOR_REGISTRY_PATH })
    return vendor_map
  end
  local file_handle = fs.open(VENDOR_REGISTRY_PATH, "r")
  while true do
    local json_line = file_handle.readLine()
    if not json_line then break end
    if json_line:match("%S") then
      local ok_parse, record = pcall(textutils.unserializeJSON, json_line)
      if ok_parse and type(record) == "table" then
        local vendor_id = record.vendorId or record.vendorID or record.client_id
        local vendor_name = record.vendorName or vendor_id
        local shared_secret = record.sharedSecret
        local is_enabled = record.enabled ~= false
        if vendor_id and shared_secret and is_enabled then
          vendor_map[vendor_id] = {
            vendorName   = vendor_name,
            sharedSecret = shared_secret,
            enabled      = true,
          }
        end
      end
    end
  end
  file_handle.close()
  return vendor_map
end

local function get_vendor_record_by_id(vendor_id)
  local now_millis = current_time_millis()
  if (now_millis - vendor_last_loaded_millis) > REGISTRY_HOT_RELOAD_MILLIS then
    vendor_cache_by_id        = load_vendor_registry_file()
    vendor_last_loaded_millis = now_millis
  end
  return vendor_cache_by_id[vendor_id]
end


--Tellraw
local function tellraw_player_basic(player_username, code_text, ttl_millis)
  local message_text = ("=== Auth Token ===\nDo not share! Code: %s\n(Expires in %d min)")
                      :format(code_text, math.floor((ttl_millis or 0) / 60000))
  local message_json = textutils.serializeJSON({ text = message_text })
  local command_ok = commands.exec(("tellraw %s %s"):format(player_username, message_json))
  return command_ok
end

local function tellraw_player_exact(player_username, code_text, ttl_millis)
  local minutes = math.max(1, math.floor((ttl_millis or 0) / 60000))

  local function build(hoverKey)
    return {
      "",
      { text = "===Auth Token===", bold = true, color = "aqua" },
      { text = "\n\n", bold = true },
      { text = "Do Not Share With Anyone", bold = true, color = "red" },
      { text = "\n\n", bold = true },
      { text = "Hover Over To Get Code", bold = true, color = "green",
        clickEvent = { action = "copy_to_clipboard", value = code_text },
        hoverEvent = { action = "show_text", [hoverKey] = code_text }
      },
      { text = "\n\n", bold = true },
      { text = "Expires in ", bold = true, color = "red" },
      { text = (tostring(minutes) .. " Minutes"), bold = true, color = "gold" },
      { text = "\n\n", bold = true },
      { text = "===Auth Token===", bold = true, color = "aqua" },
    }
  end

  local json = textutils.serializeJSON(build("contents"))
  local ok = commands.exec(("tellraw %s %s"):format(player_username, json))
  if not ok then
    json = textutils.serializeJSON(build("value"))
    ok = commands.exec(("tellraw %s %s"):format(player_username, json))
  end
  return ok
end


local dm_player_with_code = tellraw_player_exact

--Startup
open_any_wireless_modem()
print(("Auth server is listening on protocol '%s' | Computer ID %d")
  :format(PROTOCOL_NAME, os.getComputerID()))
vendor_cache_by_id = load_vendor_registry_file()
vendor_last_loaded_millis = current_time_millis()

--Main loop
while true do
  local sender_computer_id, raw_outer_message = rednet.receive(PROTOCOL_NAME)

  local is_envelope_deserialized, outer_envelope = pcall(textutils.unserialize, raw_outer_message)
  if not is_envelope_deserialized or type(outer_envelope) ~= "table" then
    append_log_line({ level = "warn", event = "bad_outer_envelope", sender = sender_computer_id })
    rednet.send(sender_computer_id, textutils.serialize({ error = "bad_outer" }), PROTOCOL_NAME)
  else
    local vendor_id = tostring(outer_envelope.client_id or outer_envelope.vendorID or "")
    local vendor_record = get_vendor_record_by_id(vendor_id)

    if not vendor_record then
      append_log_line({ level = "warn", event = "unknown_vendor", vendorId = vendor_id, sender = sender_computer_id })
      rednet.send(sender_computer_id, textutils.serialize({ error = "unknown_client_id" }), PROTOCOL_NAME)
    else
      local reply_header_for_mac = { client_id = vendor_id, version = "v1" }
      local decrypted_payload, open_error = secure.open(vendor_record.sharedSecret, reply_header_for_mac, outer_envelope.packet)

      if not decrypted_payload then
        append_log_line({
          level = "warn", event = "decrypt_or_mac_failed", vendorId = vendor_id,
          vendorName = vendor_record.vendorName, sender = sender_computer_id, detail = open_error
        })
        rednet.send(sender_computer_id, textutils.serialize({ client_id = vendor_id, error = "open_failed", detail = open_error }), PROTOCOL_NAME)

      else
        local reply_payload_table

        if decrypted_payload.type == "request_code" then
          local request_id       = decrypted_payload.request_id or secure.random_hex(12)
          local player_username  = decrypted_payload.username
          local generated_code   = random_digit_string(CODE_LENGTH_DIGITS)

          pending_requests_by_id[request_id] = {
            code = generated_code,
            player_username = player_username,
            expires_millis = current_time_millis() + CODE_TIME_TO_LIVE_MILLIS,
            attempt_count = 0,
            client_metadata = decrypted_payload,
          }

          local dm_sent_ok = dm_player_with_code(player_username, generated_code, CODE_TIME_TO_LIVE_MILLIS)

          reply_payload_table = {
            ok = dm_sent_ok and true or false,
            type = "request_code_reply",
            request_id = request_id,
            expires_in_ms = CODE_TIME_TO_LIVE_MILLIS,
            timestamp_ms = current_time_millis(),
          }

          append_log_line({
            level = "info", event = "request_code",
            vendorId = vendor_id, vendorName = vendor_record.vendorName,
            username = player_username, request_id = request_id, dm_sent = dm_sent_ok
          })

        elseif decrypted_payload.type == "verify_code" then
          local request_id = decrypted_payload.request_id
          local record_for_request = pending_requests_by_id[request_id]
          local verify_ok = false
          local failure_reason = nil

          if not record_for_request then
            failure_reason = "not_found"
          else
            record_for_request.attempt_count = (record_for_request.attempt_count or 0) + 1
            if record_for_request.attempt_count > MAX_VERIFY_ATTEMPTS_PER_CODE then
              failure_reason = "too_many_attempts"
              pending_requests_by_id[request_id] = nil
            elseif record_for_request.expires_millis < current_time_millis() then
              failure_reason = "expired"
              pending_requests_by_id[request_id] = nil
            elseif tostring(decrypted_payload.code_entered) ~= tostring(record_for_request.code) then
              failure_reason = "mismatch"
            else
              verify_ok = true
              pending_requests_by_id[request_id] = nil
            end
          end

          reply_payload_table = {
            ok = verify_ok,
            type = "verify_code_reply",
            request_id = request_id,
            reason = failure_reason,
            timestamp_ms = current_time_millis(),
          }

          append_log_line({
            level = verify_ok and "info" or "warn",
            event = "verify_code",
            vendorId = vendor_id, vendorName = vendor_record.vendorName,
            request_id = request_id,
            username = record_for_request and record_for_request.player_username or nil,
            result = verify_ok and "ok" or "fail",
            reason = failure_reason
          })

        else
          reply_payload_table = { ok = false, error = "unknown_type", timestamp_ms = current_time_millis() }
          append_log_line({ level = "warn", event = "unknown_type", vendorId = vendor_id, payload_type = tostring(decrypted_payload.type) })
        end

        local sealed_packet = secure.seal(vendor_record.sharedSecret, reply_header_for_mac, reply_payload_table)
        rednet.send(sender_computer_id, textutils.serialize({ client_id = vendor_id, packet = sealed_packet }), PROTOCOL_NAME)
      end
    end
  end
end
