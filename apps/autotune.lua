--[[
    apps/autotune.lua
    Drunken OS - Flight Dynamics & PID Autotuner (Otomatik PID & Dinamik Stabilite Hesaplayıcı)
    
    Kullanım:
      tune              -> Canlı gemi fiziğini okur, optimal PID ve motor dengesini hesaplayıp uygular.
      tune --apply      -> Doğrudan hesaplar, uygular ve kaydeder.
      tune --calc-only  -> Sadece ekranda analiz ve değerleri gösterir, uygulamaz.
]]

local BUS_PROTOCOL = "DRUNKEN_AVIONICS_BUS"

local function printCentered(y, text, textColor, bgColor)
    local w, _ = term.getSize()
    local x = math.max(1, math.floor((w - #text) / 2) + 1)
    term.setCursorPos(x, y)
    if term.isColor and term.isColor() then
        if textColor then term.setTextColor(textColor) end
        if bgColor then term.setBackgroundColor(bgColor) end
    end
    term.write(text)
end

local function drawHeader(title)
    term.clear()
    local w, _ = term.getSize()
    term.setCursorPos(1, 1)
    if term.isColor and term.isColor() then
        term.setBackgroundColor(colors.blue)
        term.setTextColor(colors.white)
        term.write(string.rep(" ", w))
        printCentered(1, title, colors.white, colors.blue)
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
    else
        printCentered(1, "=== " .. title .. " ===")
    end
end

local function run(args)
    args = args or {}
    local calcOnly = false
    local autoApply = false
    local isSafeCalib = false
    for _, a in ipairs(args) do
        if a == "--calc-only" then calcOnly = true end
        if a == "--apply" or a == "-y" then autoApply = true end
        if a == "--safe" or a == "--calibrate" then isSafeCalib = true end
    end

    drawHeader("DRUNKEN OS - AVIONICS PID AUTOTUNER")

    local okAt, Autotune = pcall(require, "lib.avx.autotune")
    if not okAt or type(Autotune) ~= "table" then okAt, Autotune = pcall(require, "avx.autotune") end
    if not okAt or type(Autotune) ~= "table" then
        if fs and fs.exists and (fs.exists("/lib/avx/autotune.lua") or fs.exists("lib/avx/autotune.lua")) then
            local path = fs.exists("/lib/avx/autotune.lua") and "/lib/avx/autotune.lua" or "lib/avx/autotune.lua"
            local okDf, resDf = pcall(dofile, path)
            if okDf and type(resDf) == "table" then Autotune = resDf; okAt = true end
        end
    end

    if not okAt or not Autotune then
        print("\n [HATA] Autotune modulu (lib/avx/autotune.lua) yuklenemedi!")
        return
    end

    local fc = _G._fc
    local params = nil

    if fc then
        params = Autotune.calculate(fc)
    else
        -- Check if connected via Rednet to Computer #15
        local modem = peripheral.find("modem")
        if modem and rednet then
            if not rednet.isOpen() then
                for _, n in ipairs(peripheral.getNames()) do
                    if peripheral.getType(n) == "modem" then rednet.open(n) end
                end
            end
            print("\n [AG] Ucus Bilgisayari (FCC) araniyor...")
            rednet.broadcast({ type = "AVIONICS_CMD", cmd = "GET_AUTOTUNE_PARAMS" }, BUS_PROTOCOL)
            local sender, msg = rednet.receive(BUS_PROTOCOL, 2.0)
            if msg and type(msg) == "table" and msg.type == "AVIONICS_AUTOTUNE_RES" and msg.params then
                params = msg.params
                print(" [AG] FCC ID #" .. tostring(sender) .. " ile eslesildi!")
            end
        end

        if not params then
            -- Fallback: calculate directly from _G.sublevel or physical model
            params = Autotune.calculate(nil)
        end
    end

    if not params then
        print("\n [HATA] Gemi fiziksel parametreleri hesaplanamadi!")
        return
    end

    local isColor = term.isColor and term.isColor()
    local cTitle = isColor and colors.yellow or colors.white
    local cVal   = isColor and colors.cyan or colors.white
    local cLabel = isColor and colors.lightGray or colors.white
    local cGood  = isColor and colors.green or colors.white

    local function renderScreen()
        drawHeader("DRUNKEN OS - AVIONICS PID AUTOTUNER")

        term.setCursorPos(2, 3)
        term.setTextColor(cTitle)
        term.write("1. GEMI FIZIKSEL VERILERI:")

        term.setCursorPos(4, 4)
        term.setTextColor(cLabel); term.write("Kutle (Mass): "); term.setTextColor(cVal); term.write(string.format("%.1f kg", params.mass))
        if params.hasRealSublevel then
            term.setTextColor(cGood); term.write(" [Sable Canli]")
        else
            term.setTextColor(colors.gray or colors.white); term.write(" [Model Fallback]")
        end

        term.setCursorPos(4, 5)
        term.setTextColor(cLabel); term.write("Eylemsizlik (Ixx Pitch): "); term.setTextColor(cVal); term.write(string.format("%.2e kg*m2", params.Ixx))

        term.setCursorPos(4, 6)
        term.setTextColor(cLabel); term.write("Eylemsizlik (Izz Roll) : "); term.setTextColor(cVal); term.write(string.format("%.2e kg*m2", params.Izz))

        term.setCursorPos(2, 8)
        term.setTextColor(cTitle)
        term.write("2. HESAPLANAN DOLDURMA & STABILITE (POLE-PLACEMENT PID):")

        term.setCursorPos(4, 9)
        term.setTextColor(cLabel); term.write("YUNUSLAMA (PITCH): ")
        term.setTextColor(cVal)
        term.write(string.format("Kp: %-5.2f  Ki: %-4.2f  Kd: %-5.2f  (w_x Damp: %-4.2f)",
                   params.pitch.kp, params.pitch.ki, params.pitch.kd, params.pitch.dampWx or 6.0))

        term.setCursorPos(4, 10)
        term.setTextColor(cLabel); term.write("YALPALAMA (ROLL) : ")
        term.setTextColor(cVal)
        term.write(string.format("Kp: %-5.2f  Ki: %-4.2f  Kd: %-5.2f  (w_z Damp: %-4.2f)",
                   params.roll.kp, params.roll.ki, params.roll.kd, params.roll.dampWz or 4.2))

        term.setCursorPos(4, 11)
        term.setTextColor(cLabel); term.write("IRTIFA    (ALT)  : ")
        term.setTextColor(cVal)
        term.write(string.format("Kp: %-5.2f  Ki: %-4.2f  Kd: %-5.2f  (v_y Damp: %-4.2f)",
                   params.alt.kp, params.alt.ki, params.alt.kd, params.alt.dampVy or 1.5))

        term.setCursorPos(2, 13)
        term.setTextColor(cTitle)
        term.write("3. MOTOR TORK & HOVER DENGE GUCU:")

        term.setCursorPos(4, 14)
        term.setTextColor(cLabel); term.write("On/Arka Tork Orani (gammaFront): "); term.setTextColor(cVal); term.write(string.format("%.3f", params.gammaFront))

        term.setCursorPos(4, 15)
        term.setTextColor(cLabel); term.write("Hover Taban Sinyali (hoverBase): "); term.setTextColor(cVal); term.write(string.format("%.1f / 15", params.hoverBaseSig))
        if params.pitchSign or params.rollSign then
            term.setTextColor(cGood)
            term.write(string.format("  [Pitch:%+d Roll:%+d]", params.pitchSign or 1, params.rollSign or 1))
        end

        term.setCursorPos(2, 17)
        term.setTextColor(isColor and colors.yellow or colors.white)
        term.write("[ENTER/C] Uygula   [P] Guvenli Kalibrasyon   [S] Kaydet   [Q] Cikis")
    end

    local function doSafeCalibration()
        term.setCursorPos(1, 18)
        term.clearLine()
        term.setCursorPos(1, 19)
        term.clearLine()

        term.setCursorPos(2, 18)
        term.setTextColor(isColor and colors.yellow or colors.white)
        term.write(">> GUVENLI KALIBRASYON BASLATILIYOR... <<")

        if fc then
            -- Yerel FCC uzerinde calisiyor
            local success = Autotune.runSafeCalibration(fc, function(logText)
                term.setCursorPos(2, 18)
                term.clearLine()
                term.setTextColor(cVal)
                term.write(tostring(logText):sub(1, 48))
            end)
            term.setCursorPos(2, 18)
            term.clearLine()
            if success then
                local a = fc.adaptive or {}
                params.pitchSign = a.pitchSign
                params.rollSign  = a.rollSign
                params.hoverBaseSig = a.hoverBase or params.hoverBaseSig
                term.setTextColor(cGood)
                term.write(string.format("[BASARILI] Pitch:%+d Roll:%+d Hover:%.1f", a.pitchSign or 1, a.rollSign or 1, a.hoverBase or 9.0))
            else
                term.setTextColor(colors.red or colors.white)
                term.write("[HATA] Kalibrasyon basarisiz! 4 motor baglantisini kontrol edin.")
            end
        else
            -- Uzak FCC (Computer #15) Rednet Uzerinden
            local modem = peripheral.find("modem")
            if not modem or not rednet or not rednet.isOpen() then
                term.setCursorPos(2, 18)
                term.setTextColor(colors.red or colors.white)
                term.write("[HATA] Modem bulunamadi veya Rednet acik degil!")
            else
                term.setCursorPos(2, 18)
                term.clearLine()
                term.setTextColor(cLabel)
                term.write("FCC'ye baglaniliyor, mikro-darbe baslatildi...")
                rednet.broadcast({ type = "AVIONICS_CMD", cmd = "SAFE_CALIBRATE" }, BUS_PROTOCOL)

                local startTime = os.clock()
                local completed = false
                local lastRes = nil

                while (os.clock() - startTime) < 8.0 do
                    local sender, msg, proto = rednet.receive(BUS_PROTOCOL, 0.4)
                    if proto == BUS_PROTOCOL and type(msg) == "table" then
                        if msg.type == "AVIONICS_CALIBRATE_PROGRESS" then
                            term.setCursorPos(2, 18)
                            term.clearLine()
                            term.setTextColor(cVal)
                            term.write(tostring(msg.msg or ""):sub(1, 48))
                        elseif msg.type == "AVIONICS_SAFE_CALIBRATE_RES" then
                            completed = true
                            lastRes = msg
                            break
                        end
                    end
                end

                term.setCursorPos(2, 18)
                term.clearLine()
                if completed and lastRes then
                    if lastRes.success then
                        term.setTextColor(cGood)
                        local a = lastRes.adaptive or {}
                        params.pitchSign = a.pitchSign
                        params.rollSign  = a.rollSign
                        params.hoverBaseSig = a.hoverBase or params.hoverBaseSig
                        term.write(string.format("[BASARILI] Pitch:%+d Roll:%+d Hover:%.1f",
                            a.pitchSign or 1, a.rollSign or 1, a.hoverBase or 9.0))
                    else
                        term.setTextColor(colors.red or colors.white)
                        term.write("[HATA] FCC kalibrasyonu basarisiz bildirdi!")
                    end
                else
                    term.setTextColor(colors.red or colors.white)
                    term.write("[ZAMAN ASIMI] FCC'den yanit alinamadi (Computer #15)!")
                end
            end
        end

        term.setCursorPos(2, 19)
        term.setTextColor(cTitle)
        term.write("Devam etmek icin bir tusa basin...")
        os.pullEvent("key")
        renderScreen()
    end

    if isSafeCalib then
        renderScreen()
        doSafeCalibration()
        return
    end

    renderScreen()

    if autoApply then
        if fc then
            Autotune.apply(fc, params, true)
            term.setCursorPos(2, 18)
            term.setTextColor(cGood)
            term.write("[BASARILI] Yeni PID ve denge degerleri FC uzerine uygulandi ve kaydedildi!")
        end
        return
    end

    if calcOnly then
        term.setCursorPos(2, 18)
        term.setTextColor(cLabel)
        term.write("Hesaplama tamamlandi (--calc-only). Cikmak icin bir tusa basin...")
        os.pullEvent("key")
        return
    end

    while true do
        local _, key = os.pullEvent("key")
        if key == keys.enter or key == keys.c then
            if fc then
                Autotune.apply(fc, params, true)
                term.setCursorPos(2, 18)
                term.clearLine()
                term.setTextColor(cGood)
                term.write(">> PID VE STATIK DENGE UYGULANDI VE KAYDEDILDI! <<   ")
            else
                local modem = peripheral.find("modem")
                if modem and rednet and rednet.isOpen() then
                    rednet.broadcast({ type = "AVIONICS_CMD", cmd = "AUTOTUNE" }, BUS_PROTOCOL)
                    term.setCursorPos(2, 18)
                    term.clearLine()
                    term.setTextColor(cGood)
                    term.write(">> AG UZERINDEN FCC'YE UYGULAMA KOMUTU GONDERILDI! <<")
                else
                    term.setCursorPos(2, 18)
                    term.clearLine()
                    term.setTextColor(colors.orange or colors.white)
                    term.write(">> Yerel FC bulunamadi, sadece config'e kaydedildi. <<")
                    Autotune.apply(nil, params, true)
                end
            end
            term.setCursorPos(2, 19)
            term.setTextColor(cTitle)
            term.write("Devam etmek icin bir tusa basin...")
            os.pullEvent("key")
            renderScreen()
        elseif key == keys.p then
            doSafeCalibration()
        elseif key == keys.s then
            Autotune.apply(fc, params, true)
            term.setCursorPos(2, 18)
            term.clearLine()
            term.setTextColor(cGood)
            term.write(">> DEGERLER /avionics_iomap.cfg DOSYASINA KAYDEDILDI! <<")
            term.setCursorPos(2, 19)
            term.setTextColor(cTitle)
            term.write("Devam etmek icin bir tusa basin...")
            os.pullEvent("key")
            renderScreen()
        elseif key == keys.q then
            break
        end
    end

    term.setCursorPos(1, 19)
    if isColor then term.setTextColor(colors.white) end
end

if ... then
    run({ ... })
else
    run({})
end
