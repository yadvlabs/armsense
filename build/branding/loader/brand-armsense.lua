--
-- SPDX-License-Identifier: Apache-2.0
--
-- armsense boot loader brand
--

local drawer = require("drawer")

local armsense = {
"",
" __ _  _ _  _ __   ___  ___  _ _   ___  ___",
"/ _` || '_|| '  \\ (_-< / -_)| ' \\ (_-< / -_)",
"\\__,_||_|  |_|_|_|/__/ \\___||_||_|/__/ \\___|",
"",
}

drawer.addBrand("armsense", {
	graphic = armsense,
})

return true
