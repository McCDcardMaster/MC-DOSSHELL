local menu = require("api")

local myItems = {
	"Open F5",
	"Run...",
    "-",
    "Copy...",
    "Delete",
    "-",
    "Exit"
}
	
menu.draw(myItems, 5, 5)