-- ============================================
-- Установщик MC-DOS для ComputerCraft
-- Загружает dosshell.lua из репозитория GitHub
-- ============================================

-- Параметры
local REPO_URL = "https://raw.githubusercontent.com/McCDcardMaster/MC-DOSSHELL/main/dosshell.lua"
local INSTALL_DIR = "/DOS"
local SHELL_PATH = INSTALL_DIR .. "/DOSSHELL.lua"

local w, h = term.getSize()

if not http then
    error("HTTP API Not Enable! Please Enable it in settings Mod")
end

local function drawHeader()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.setCursorPos(1, 1)
    term.clearLine()
    local title = "Minecraft MC-DOS Setup"
    term.setCursorPos(math.floor((w - #title)/2) + 1, 1)
    term.write(title)
end

local function drawFooter(text)
    term.setCursorPos(1, h)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write(text or " ENTER=Continue  F3=Exit")
end

local function centerText(y, text, bg, fg)
	term.setPaletteColor(colors.blue, 0x1e1d8f)
    term.setBackgroundColor(bg or colors.blue)
    term.setTextColor(fg or colors.white)
    term.setCursorPos(math.floor((w - #text)/2) + 1, y)
    term.write(text)
end

-- Первый экран
term.setBackgroundColor(colors.blue)
term.clear()
drawHeader()
centerText(3, "Welcome to MC-DOS Setup", colors.blue, colors.yellow)
centerText(6, "This will install MC-DOS on your computer.")
centerText(7, "Files will be saved to " .. INSTALL_DIR)
centerText(9, "Press ENTER to start...")
drawFooter()

while true do
    local _, key = os.pullEvent("key")
    if key == keys.enter then break
    elseif key == keys.f3 then 
        term.setBackgroundColor(colors.black)
        term.clear()
        term.setCursorPos(1,1)
        return 
    end
end

-- Установка
term.setBackgroundColor(colors.blue)
term.clear()
drawHeader()
centerText(5, "Downloading: DOSSHELL from GitHub...")

-- Имитация копирования ЛОЛ
local files = {"IO.SYS", "MCDOS.SYS", "COMMAND.COM", "DOSSHELL.EXE", "CONFIG.SYS"}
for i, f in ipairs(files) do
    term.setCursorPos(2, h-3)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.yellow)
    term.write("Copying: " .. f)
    
    -- Прогресс-бар
    term.setCursorPos(2, h-2)
    term.setBackgroundColor(colors.lightGray)
    term.write(string.rep(" ", w-4))
    term.setCursorPos(2, h-2)
    term.setBackgroundColor(colors.blue)
    term.write(string.rep(" ", math.floor((i/#files)*(w-4))))
    
    sleep(0.6)
end

if not fs.exists(INSTALL_DIR) then 
    fs.makeDir(INSTALL_DIR) 
end

local success = false
local response, err = http.get(REPO_URL, nil, true)

if response then
    local responseCode = response.getResponseCode()
    if responseCode == 200 then
        local f = fs.open(SHELL_PATH, "w")
        f.write(response.readAll())
        f.close()
        response.close()
        success = true
    else
        response.close()
        err = "HTTP " .. responseCode
    end
end

if not success then
    -- Если не скачалось
    term.setBackgroundColor(colors.red)
    term.clear()
    centerText(4, "FAILED TO DOWNLOAD!", colors.red, colors.white)
    centerText(6, "Error: " .. (err or "404 Not Found"))
    centerText(8, "URL: " .. REPO_URL)
    centerText(10, "Check your internet or file name.")
    drawFooter(" Press any key to exit")
    os.pullEvent("key")
    return
end

-- Создание автозагрузки
local startup = fs.open("/startup.lua", "w")
startup.write('shell.run("' .. SHELL_PATH .. '")\n')
startup.close()

-- ЗАВЕРШЕНИЕ
term.setBackgroundColor(colors.blue)
term.clear()
drawHeader()
centerText(5, "Setup Complete!", colors.blue, colors.yellow)
centerText(7, "MC-DOS is now installed.")
centerText(9, "Press ENTER to reboot.")
drawFooter(" ENTER=Reboot")

while true do
    local _, key = os.pullEvent("key")
    if key == keys.enter then 
        os.reboot() 
    end
end
