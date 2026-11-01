-- apps/blackbox.lua
-- Drunken OS - Flight Data Recorder (Kara Kutu) Terminal Viewer & Exporter

local tArgs = { ... }
local cmd = tArgs[1] or ""

local TXT_LOG = "/flight_log.txt"
local CSV_LOG = "/flight_log.csv"

local function printHeader()
    if term.isColor and term.isColor() then
        term.setTextColor(colors.cyan)
    end
    print("==================================================")
    print("  DRUNKEN OS - FLIGHT RECORDER (KARA KUTU)")
    print("==================================================")
    if term.isColor and term.isColor() then
        term.setTextColor(colors.white)
    end
end

if cmd == "-c" or cmd == "--clear" then
    if fs.exists(TXT_LOG) then fs.delete(TXT_LOG) end
    if fs.exists(CSV_LOG) then fs.delete(CSV_LOG) end
    printHeader()
    print("Kara kutu kayitlari temizlendi! (/flight_log.txt)")
    return
end

if cmd == "-p" or cmd == "--pastebin" then
    printHeader()
    if not fs.exists(TXT_LOG) then
        print("HATA: Henuz bir ucus kaydi yok! (/flight_log.txt bulunamadi)")
        return
    end
    if not http then
        print("HATA: ComputerCraft HTTP erisimi devre disi!")
        return
    end
    local f = fs.open(TXT_LOG, "r")
    local data = f.readAll()
    f.close()

    print("Pastebin'e yukleniyor...")
    local resp = http.post("https://pastebin.com/api/api_post.php",
        "api_option=paste&api_dev_key=0ec2eb25b4204c3b9e4f80079f87c028&api_paste_code=" ..
        textutils.urlEncode(data) .. "&api_paste_name=DrunkenOS_FlightLog.txt&api_paste_private=1"
    )
    if resp then
        local pasteCode = resp.readAll()
        resp.close()
        if term.isColor and term.isColor() then term.setTextColor(colors.lime) end
        print("BASARILI! Pastebin Linki: " .. tostring(pasteCode))
        if term.isColor and term.isColor() then term.setTextColor(colors.yellow) end
        print("Bu kodu veya linki sohbete yapistirabilirsiniz!")
    else
        print("HATA: Pastebin yuklemesi basarisiz oldu.")
    end
    return
end

if not fs.exists(TXT_LOG) then
    printHeader()
    print("Henuz kaydedilmis ucus verisi bulunmuyor.")
    print("Kokpitte veya FCC'de ucusa basladiginizda")
    print("otomatik olarak /flight_log.txt dosyasina kaydedilir.")
    print("\nKullanim:")
    print("  blackbox          : Son ucus kayitlarini gosterir")
    print("  blackbox -p       : Pastebin'e yukleyip kod verir")
    print("  blackbox -c       : Kayitlari temizler")
    return
end

local f = fs.open(TXT_LOG, "r")
local lines = {}
while true do
    local l = f.readLine()
    if not l then break end
    table.insert(lines, l)
end
f.close()

-- Terminal display with pagination or latest lines
printHeader()
local w, h = term.getSize()
local maxDisplay = math.max(5, h - 5)
local startIdx = math.max(1, #lines - maxDisplay + 1)

for i = startIdx, #lines do
    local line = lines[i]
    if term.isColor and term.isColor() then
        if line:find("ANTI-DIVE") or line:find("ASIRI") then
            term.setTextColor(colors.red)
        elseif line:find("YUNUSLAMA") or line:find("YATIS") then
            term.setTextColor(colors.orange)
        elseif line:find("HIZLI-ILERI") then
            term.setTextColor(colors.yellow)
        elseif line:find("TERAZI") or line:find("HOVER") then
            term.setTextColor(colors.lime)
        else
            term.setTextColor(colors.lightGray)
        end
    end
    print(line:sub(1, w))
end

if term.isColor and term.isColor() then term.setTextColor(colors.cyan) end
print(string.format("\nDosya: %s (%d satir) | Pastebin: blackbox -p", TXT_LOG, #lines))
