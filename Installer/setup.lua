-- URL вашего репозитория (raw-ссылка для скачивания контента)
local githubUrl = "https://githubusercontent.com"

-- Функция для скачивания файла
local function downloadFile(url, path)
    local response = http.get(url)
    if response then
        local content = response.readAll()
        response.close()
        local file = fs.open(path, "w")
        file.write(content)
        file.close()
        return true
    else
        return false
    end
end

-- 2. Процесс установки
term.setBackgroundColor(colors.blue)
term.clear()
drawHeader()
centerText(10, "Connecting to GitHub...")

if not http then
    centerText(12, "Error: HTTP API is disabled in config!", colors.blue, colors.red)
    return
end

fs.makeDir("/DOS")

-- Процесс имитации и реальной загрузки
local steps = {"IO.SYS", "MCDOS.SYS", "COMMAND.COM", "DOSSHELL.lua", "CONFIG.SYS"}
for i, step in ipairs(steps) do
    term.setCursorPos(2, h-3)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.yellow)
    term.write("Installing: " .. step)
    
    if step == "DOSSHELL.lua" then
        local success = downloadFile(githubUrl, "/DOS/DOSSHELL.lua")
        if not success then
            term.setCursorPos(2, h-4)
            term.setTextColor(colors.red)
            term.write("Failed to download DOSSHELL.lua!")
            sleep(2)
        end
    else
        -- Создаем пустые системные файлы для вида
        local f = fs.open("/DOS/"..step, "w")
        f.write("-- MC-DOS System File")
        f.close()
    end

    -- Прогресс-бар
    term.setCursorPos(2, h-2)
    term.setBackgroundColor(colors.lightGray)
    term.write(string.rep(" ", w-4))
    term.setCursorPos(2, h-2)
    term.setBackgroundColor(colors.blue)
    term.write(string.rep(" ", math.floor((i/#steps)*(w-4))))
    sleep(0.4)
end

-- Автозагрузка
local s = fs.open("/startup.lua", "w")
s.write("shell.run('/DOS/DOSSHELL.lua')")
s.close()
