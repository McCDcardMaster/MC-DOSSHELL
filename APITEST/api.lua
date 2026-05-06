local menu = {}

function menu.draw(items, startX, startY)
    local menuWidth = 0
    -- Самый длинный текст чтобы меню подстроилось под размер
    for _, item in ipairs(items) do
        if #item > menuWidth then menuWidth = #item end
    end
    menuWidth = menuWidth + 2 -- Запас для пробелов по бокам

    local count = #items
    
    -- Тень
    term.setBackgroundColor(colors.lightGray)
    for i = 1, count do
        term.setCursorPos(startX + menuWidth, startY + i)
        term.write(" ")
    end
    term.setCursorPos(startX + 1, startY + count)
    term.write(string.rep(" ", menuWidth))

    -- Пункты меню
    for i, item in ipairs(items) do
        term.setCursorPos(startX, startY + i - 1)
        
        if item == "-" then
            -- Разделитель
            term.setBackgroundColor(colors.white)
            term.setTextColor(colors.lightGray)
            term.write(string.rep("-", menuWidth))
        else
            -- Текст
            term.setBackgroundColor(colors.white)
            term.setTextColor(colors.black)
            local line = " " .. item
            term.write(line .. string.rep(" ", menuWidth - #line))
        end
    end
end


return menu