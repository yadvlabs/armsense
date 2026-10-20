--
-- SPDX-License-Identifier: Apache-2.0
--
-- armsense boot loader logo
--

local drawer = require("drawer")

local armsensebw = {
"         _______________         ",
"        /               \\        ",
"       |   ___________   |       ",
"       |  |  _______  |  |       ",
"       |  | |  ___  | |  |       ",
"       |  | | |   | | |  |       ",
"       |  | | |___| | |  |       ",
"       |  | |_______| |  |       ",
"       |  |___________|  |       ",
"        \\               /        ",
"         \\             /         ",
"          \\           /          ",
"           \\_________/           ",
"                                 ",
}

drawer.addLogo("armsensebw", {
	graphic = armsensebw,
	shift = {x = 2, y = -2},
})

return true
