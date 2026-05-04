local w, h = term.getSize()
local currentPath = ""
local selectedList = "dirs"
local selDir, selFile = 1, 1
local dirs, files = {}, {}
local mouseX, mouseY = 1, 1
local lastClickTime, lastClickButton = 0, 0

-- Функция для обновления списков папок и файлов
local function refresh()
    dirs, files = { ".." }, {}
    local all = fs.list(currentPath)
    table.sort(all)
    for _, name in ipairs(all) do
        local fullPath = fs.combine(currentPath, name)
        if fs.isDir(fullPath) then
            table.insert(dirs, name)
        else
            table.insert(files, name)
        end
    end
    if selDir > #dirs then selDir = 1 end
    if selFile > #files then selFile = 1 end
end

local function draw()
    term.setBackgroundColor(colors.white)
    term.clear()
    
    -- Синий заголовок
    term.setCursorPos(1, 1)
	term.setPaletteColor(colors.blue, 0x1e1d8f)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.clearLine()
    local title = "   MC-DOS Shell "
    term.setCursorPos(math.floor((w - #title) / 2), 1)
    term.write(title)
    
    -- Верхнее меню
    term.setCursorPos(1, 2)
    term.setBackgroundColor(colors.white)
    term.setTextColor(colors.black)
    term.clearLine()
    term.write(" File  Options  View  Tree  Help")
    
    -- Путь и диски
    term.setCursorPos(1, 3)
    local displayPath = " C:\\" .. currentPath:gsub("/", "\\")
    term.write(displayPath)
	
    term.setBackgroundColor(colors.lightGray)
    term.setTextColor(colors.black)
    term.setCursorPos(1, 5)
    term.clearLine()
    term.setCursorPos(3, 5)
    term.write("Directory Tree")
    local split = math.floor(w/2)
    term.setCursorPos(split + 3, 5)
    term.write("Files")

    -- Тут Рамки
    term.setBackgroundColor(colors.gray)
    for i = 6, h-1 do
        term.setCursorPos(1, i); term.write(" ")
        term.setCursorPos(split, i); term.write(" ")
        term.setCursorPos(w, i); term.write(" ")
    end
    term.setCursorPos(1, h-1); term.write(string.rep(" ", w))

    -- Тут Папки
    for i, name in ipairs(dirs) do
        if i > h-8 then break end
        term.setCursorPos(2, i + 5)
        if selectedList == "dirs" and i == selDir then
            term.setBackgroundColor(colors.gray); term.setTextColor(colors.white)
        else
            term.setBackgroundColor(colors.white); term.setTextColor(colors.black)
        end
        local text = "-[+] " .. name
        term.write(string.sub(text .. string.rep(" ", split), 1, split - 2))
    end

    -- Тут Файлы
    for i, name in ipairs(files) do
        if i > h-8 then break end
        term.setCursorPos(split + 1, i + 5)
        if selectedList == "files" and i == selFile then
            term.setBackgroundColor(colors.gray); term.setTextColor(colors.white)
        else
            term.setBackgroundColor(colors.white); term.setTextColor(colors.black)
        end
        local text = " " .. name
        term.write(string.sub(text .. string.rep(" ", w), 1, w - split - 1))
    end

    -- Нижняя линия
    term.setCursorPos(1, h)
    term.setBackgroundColor(colors.lightGray)
    term.setTextColor(colors.black)
    term.clearLine()
    term.write(" F3=Exit  Tab=Switch  Enter=Open/Run")

    -- Мышка
    term.setCursorPos(mouseX, mouseY)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.yellow)
    term.write("+")
    term.setCursorBlink(false)
end

local function executeAction()
    if selectedList == "dirs" then
        local target = dirs[selDir]
        if target == ".." then
            currentPath = fs.getDir(currentPath)
            if currentPath == "." then currentPath = "" end
        else
            currentPath = fs.combine(currentPath, target)
        end
        selDir, selFile = 1, 1
        refresh()
    else
        if #files > 0 then
            local fullPath = "/" .. fs.combine(currentPath, files[selFile])
            term.setBackgroundColor(colors.black); term.setTextColor(colors.white)
            term.clear(); term.setCursorPos(1, 1)
            shell.run(fullPath)
            print("\nPress any key to return...")
            os.pullEvent("key")
            refresh()
        end
    end
end

refresh()
local updateTimer = os.startTimer(0.05)

while true do
    draw()
    local event, p1, p2, p3 = os.pullEvent()
    
    -- Обновление координат мыши
    if event == "mouse_move" or event == "mouse_click" or event == "mouse_drag" then
        mouseX, mouseY = p2, p3
        
        if event == "mouse_click" then
            local split = math.floor(w/2)
            local clickedRow = mouseY - 5
            local isDoubleClick = (os.epoch("utc") - lastClickTime < 500) and (lastClickButton == p1)
            
            if mouseY >= 6 and mouseY <= h-2 then
                if p2 < split then
                    selectedList = "dirs"
                    if dirs[clickedRow] then selDir = clickedRow end
                else
                    selectedList = "files"
                    if files[clickedRow] then selFile = clickedRow end
                end
                
                if isDoubleClick then executeAction() end
                lastClickTime = os.epoch("utc")
                lastClickButton = p1
            end
        end
		
    elseif event == "timer" and p1 == updateTimer then
        updateTimer = os.startTimer(0.05)

    -- Управление клавиатурой
    elseif event == "key" then
        if p1 == keys.tab then
            selectedList = (selectedList == "dirs") and "files" or "dirs"
        elseif p1 == keys.up then
            if selectedList == "dirs" then selDir = math.max(1, selDir - 1)
            else selFile = math.max(1, selFile - 1) end
        elseif p1 == keys.down then
            if selectedList == "dirs" then selDir = math.min(#dirs, selDir + 1)
            else selFile = math.min(#files, selFile + 1) end
        elseif p1 == keys.enter then
            executeAction()
        elseif p1 == keys.f3 then
            term.setBackgroundColor(colors.black); term.setTextColor(colors.white)
            term.clear(); term.setCursorPos(1, 1)
            break
        end
    end
end
