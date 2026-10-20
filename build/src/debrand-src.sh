#!/bin/sh
#
# debrand-src.sh -- remove upstream (pfSense / Netgate) branding and vendor
# service hooks from the renamed source trees.  Sourced by rename-src.sh,
# which calls debrand_pfsense (cwd = pfSense GUI/backend tree, after the
# rename) and debrand_freebsd (cwd = FreeBSD-src fork).
#
# Scope: user-visible text, logos, icons, menus, wizards, console banners,
# the installer notice, the boot loader, package manager prefixes, and code
# that contacts vendor servers.  Source file copyright headers, upstream bug
# tracker links in comments, documentation links and internal identifiers
# (PHP function names, namespaces, RADIUS attribute names, gettext domain)
# are deliberately left alone.
#
# Needs: N (product name), L (product label), PRODUCT_URL, and BR (path to
# the branding assets directory) set by the caller.
#

dlog() { echo ">>> debrand: $*"; }

# sedf 'expr' file...  -- in-place sed that fails loudly when a file is missing
sedf() {
	local _e="$1"; shift
	for _f in "$@"; do
		[ -f "$_f" ] || { echo "debrand: missing $_f" >&2; return 1; }
		sed -i '' -e "$_e" "$_f"
	done
}

debrand_pfsense() {
	local www=src/usr/local/www inc=src/etc/inc

	dlog "logo, icons and theme names"
	cp "$BR/www/logo.svg" "$www/logo.svg"
	cp "$BR/www/css/logo.css" "$www/css/logo.css"
	for f in favicon.ico favicon-16x16.png favicon-32x32.png android-chrome-192x192.png \
	    android-chrome-512x512.png mstile-150x150.png safari-pinned-tab.svg; do
		cp "$BR/www/$f" "$www/$f"
	done
	cp "$BR"/www/apple-touch/*.png "$www/apple-touch/"
	# Theme files carry the product name in the GUI theme selector.
	for t in pfSense pfSense-dark pfSense-BETA pfSense-dark-BETA; do
		[ -f "$www/css/$t.css" ] && git mv "$www/css/$t.css" "$www/css/$(echo "$t" | sed "s,pfSense,$N,").css"
	done
	grep -rIl 'pfSense\(-dark\)\{0,1\}\(-BETA\)\{0,1\}\.css' src | while read -r f; do
		sedf "s|pfSense\(-dark\)\{0,1\}\(-BETA\)\{0,1\}\.css|$N\1\2.css|g" "$f"
	done
	sedf "s/strpos(\$css, \"pfSense\")/strpos(\$css, \"$N\")/" "$inc/pfsense-utils.inc"
	sedf "s/startsWith(\"pfSense\")/startsWith(\"$N\")/" "$www/system.php" "$www/system_usermanager.php" "$www/system_user_settings.php"
	# Console banner art.
	git mv "src/usr/local/share/$N/ascii-art/pfsense-logo-small.txt" "src/usr/local/share/$N/ascii-art/$N-logo-small.txt"
	cp "$BR/ascii-art/armsense-logo-small.txt" "src/usr/local/share/$N/ascii-art/$N-logo-small.txt"
	sedf "s,ascii-art/pfsense-logo-small.txt,ascii-art/$N-logo-small.txt," "src/etc/$N-rc"

	dlog "package manager prefix"
	grep -rIl 'pfSense-pkg-' src --include='*.inc' --include='*.php' --include='*.xml' | while read -r f; do
		sedf "s/pfSense-pkg-/$N-pkg-/g" "$f"
	done

	dlog "header, help menu, footer"
	sedf '/text-transform:uppercase;letter-spacing:1px;">Community Edition<\/span>/d' "$www/head.inc"
	sedf '/\$system_menu\[\] = array(gettext("Register"), "\/system_register.php");/d' "$www/head.inc"
	sedf '/gettext("Paid Support")/d' "$www/head.inc"
	sedf "/strpos(g_get('product_label'), 'Plus') === false/,/^\t}/d" "$www/head.inc"
	sedf "s|\$help_menu\[\] = array(gettext(\"FreeBSD Handbook\"), \"https://redirects.netgate.com/fbsdhandbook\");|&\n\t\$help_menu[] = array(gettext(\"$L Project\"), \"$PRODUCT_URL\");|" "$www/head.inc"
	grep -q "$L Project" "$www/head.inc"
	# print_credit(): the footer on every page and the login page.
	awk -v L="$L" -v U="$PRODUCT_URL" '
	/^function print_credit\(\) \{/ {
		print; print "\tglobal $g;"; print "";
		print "\treturn \x27<a target=\"_blank\" href=\"" U "\">\x27 . g_get(\x27product_label\x27) . \x27</a>\x27 .";
		print "\t\t\x27 &copy; \x27 . g_get(\x27product_copyright_years\x27) . \x27 yadv labs. \x27 .";
		print "\t\t\x27<a target=\"_blank\" href=\"http://www.apache.org/licenses/LICENSE-2.0\">\x27 . gettext(\x27Apache License 2.0\x27) . \x27</a>\x27;";
		print "}"; skip = 1; next }
	skip && /^}/ { skip = 0; next }
	skip { next }
	{ print }' "$inc/auth.inc" > "$inc/auth.inc.new" && mv "$inc/auth.inc.new" "$inc/auth.inc"
	grep -q 'yadv labs' "$inc/auth.inc"
	sedf "s/'product_copyright_years' => '2004 - ' . \$present_year,/'product_copyright_years' => (\$present_year > 2026 ? '2026 - ' : '') . \$present_year,/" "$inc/globals.inc"
	sedf "s/'factory_shipped_password' => 'pfsense',/'factory_shipped_password' => '${DEFAULT_PASSWORD:?}',/" "$inc/globals.inc"
	grep -q "'factory_shipped_password' => '$DEFAULT_PASSWORD'" "$inc/globals.inc"
	# nginx error pages.
	for f in "$www/404.html" "$www/50x.html"; do
		awk -v L="$L" -v U="$PRODUCT_URL" '
		/<a target="_blank" href="https:\/\/pfsense.org">pfSense<\/a>/ {
			print "\t\t\t\t\t\t<a target=\"_blank\" href=\"" U "\">" L "</a> &copy; 2026 yadv labs.";
			print "\t\t\t\t\t\t<a target=\"_blank\" href=\"http://www.apache.org/licenses/LICENSE-2.0\">Apache License 2.0</a>.";
			skip = 1; next }
		skip && /View license<\/a>\./ { skip = 0; next }
		skip { next }
		{ print }' "$f" > "$f.new" && mv "$f.new" "$f"
		! grep -q 'netgate\|pfsense' "$f"
	done

	dlog "license notice and vendor services"
	cp "$BR/copynotice.inc" "$inc/copynotice.inc"
	cp "$BR/copyget.inc" "$inc/copyget.inc"
	git rm -qf "$www/system_register.php" "src/usr/local/$N/include/www/system_register.inc"
	git rm -qf "$www/widgets/widgets/netgate_services_and_support.widget.php"
	# Vendor package-signing fingerprints and the vendor CA certificate: not
	# used (repositories are armsense's own) and they identify the vendor.
	git rm -qf "src/usr/local/share/$N/keys/pkg/trusted/"* "src/usr/local/share/$N/ssl/netgate-ca.pem"
	mkdir -p "src/usr/local/share/$N/keys/pkg/trusted" "src/usr/local/share/$N/keys/pkg/revoked"
	touch "src/usr/local/share/$N/keys/pkg/trusted/.keep" "src/usr/local/share/$N/keys/pkg/revoked/.keep"
	sedf 's/Netgate Device ID/Device ID/g' "$www/widgets/widgets/system_information.widget.php" \
	    "src/usr/local/$N/include/www/status_output.inc" src/etc/rc.banner "$www/system_advanced_misc.php"
	sedf 's/Could not connect to Netgate servers\. Please try again later\./Could not reach the package repository. Please try again later./' "$inc/pkg-utils.inc"
	sedf 's/from the Netgate Installer/from the installer/g' src/etc/rc.bootup "$inc/config.console.inc"
	sedf "s|<i>Made with \&hearts; by</i> <strong>Netgate</strong>|<strong>$L</strong>|" \
	    src/usr/local/captiveportal/index.php "$inc/captiveportal.inc"
	sedf "s/\"pfSenseConfigurator\"/\"${N}Configurator\"/g" "$inc/config.lib.inc"

	dlog "wizards and remaining user-visible strings"
	local wiz="$www/wizards/setup_wizard.xml"
	sedf "s|<title>pfSense Setup</title>|<title>$L Setup</title>|" "$wiz"
	sedf "s|<p><h4>Welcome to pfSense® software!</h4></p>|<p><h4>Welcome to $L!</h4></p>|" "$wiz"
	sedf "s|initial configuration of pfSense\.|initial configuration of $L.|" "$wiz"
	sedf '/<p><strong>pfSense® software is developed and maintained by Netgate®<strong><\/p>/d' "$wiz"
	sedf "s|<p><a href=\"https://www.netgate.com/pfw1\" class=\"btn btn-info\" target=\"_blank\">Learn more</a></p>|<p><a href=\"$PRODUCT_URL\" class=\"btn btn-info\" target=\"_blank\">About $L</a></p>|" "$wiz"
	# Step 2 (vendor support advertisement) becomes a short project note.
	awk -v L="$L" -v U="$PRODUCT_URL" '
	/<title>Netgate® Global Support is available 24\/7<\/title>/ {
		print "\t<title>About " L "</title>"; next }
	/<p>Our 24\/7 worldwide team of support engineers/ {
		print "\t\t<p>" L " is a community-maintained, open source firewall and router distribution for arm64 systems, derived from the pfSense&reg; Community Edition code base and released under the Apache License 2.0.</p>";
		print "\t\t<p>Documentation written for pfSense software applies to most of what you will find here; the help links in the top menu point at it.</p>";
		print "\t\t<p>Bug reports and contributions are welcome on the project page.</p>";
		skip = 1; next }
	skip && /<p><a href="https:\/\/www.netgate.com\/pfw2" class="btn btn-info" target="_blank">Learn more<\/a><\/p>/ {
		print "\t\t<p><a href=\"" U "\" class=\"btn btn-info\" target=\"_blank\">Project page</a></p>"; skip = 0; next }
	skip { next }
	{ print }' "$wiz" > "$wiz.new" && mv "$wiz.new" "$wiz"
	sedf "s|the general pfSense parameters|the general $L parameters|" "$wiz"
	sedf "s|via pfSense setup wizard|via $L setup wizard|; s|of the pfSense setup wizard|of the $L setup wizard|" "$wiz"
	sedf "s|to reload pfSense with new changes|to reload $L with new changes|" "$wiz"
	sedf "s|<p><h4>Congratulations! pfSense is now configured\.</h4></p>|<p><h4>Congratulations! $L is now configured.</h4></p>|" "$wiz"
	# Final step: drop the vendor marketing block (from "Remember, we're here to help" to the end of the list).
	awk -v L="$L" -v U="$PRODUCT_URL" '
	/<p><h4>Remember, we.re here to help\.<\/h4><\/p>/ {
		print "\t\t<p><h4>Useful resources.</h4></p>";
		print "\t\t<p>";
		print "\t\t\t<ul>";
		print "\t\t\t\t<li><a target=\x27_blank\x27 href=\x27" U "\x27>" L " project page</a></li>";
		print "\t\t\t\t<li><a target=\x27_blank\x27 href=\x27https://docs.netgate.com/pfsense/en/latest/\x27>pfSense software documentation</a> (applies to most of " L ")</li>";
		print "\t\t\t</ul>";
		print "\t\t</p>";
		skip = 1; next }
	skip && /<\/ul>/ { skip = 2; next }
	skip == 2 && /<\/p>/ { skip = 0; next }
	skip { next }
	{ print }' "$wiz" > "$wiz.new" && mv "$wiz.new" "$wiz"
	! grep -q 'netgate.com/pfw' "$wiz"
	for f in "$www"/wizards/traffic_shaper_wizard_*.xml; do
		sedf "s|pfSense Traffic Shaper|$L Traffic Shaper|g; s|the pfSense traffic shaper|the $L traffic shaper|g" "$f"
	done
	sedf "s|(pfSense Software, FreeBSD, Linux, Windows 10)|($L, FreeBSD, Linux, Windows 10)|" "$inc/certs.inc"
	sedf "s|pfSense will use DNS servers|$L will use DNS servers|" "$www/vpn_openvpn_client.php"
	sedf "s|pfSense cannot continue without|$L cannot continue without|" src/etc/rc.bootup
	sedf "s|'pfSense Default',|'$L Default',|" "$www/interfaces.php"
	for f in src/etc/rc.initial "src/etc/$N-rc" "src/etc/$N-rc.shutdown" src/etc/rc.update_pkg_metadata; do
		sedf "s/read_global_var product_\(name\|label\) pfSense/read_global_var product_\1 $N/" "$f"
	done

	dlog "remaining user-visible 'Netgate' mentions:"
	grep -rIn --exclude='*.po' --exclude='*.pot' --exclude='*.mo' 'Netgate' src \
	    | grep -v -E 'Rubicon Communications|Copyright|part of pfSense|^src/etc/pfSense.obsoletedfiles|^src/etc/[a-z]*\.obsoletedfiles|gitsync|system\.inc:|upgrade_config\.inc|services_acb|docs\.netgate|redirects\.netgate|netgate-ca|copynotice\.inc|copyget\.inc|# ' \
	    | cut -c1-140 || true
}

debrand_freebsd() {
	dlog "boot loader brand and logo"
	cp "$BR/loader/brand-$N.lua" "stand/lua/brand-$N.lua"
	cp "$BR/loader/logo-${N}bw.lua" "stand/lua/logo-${N}bw.lua"
	grep -q "logo-${N}bw.lua" stand/lua/Makefile || \
	    sed -i '' -e "s,^\tbrand-$N.lua,\tbrand-$N.lua \\\\\\
\tlogo-${N}bw.lua," stand/lua/Makefile
	grep -q "logo-${N}bw.lua" stand/lua/Makefile
	sed -i '' -e "s,^loader_logo=\"pfSensebw\",loader_logo=\"${N}bw\"," stand/defaults/loader.conf
	grep -q "loader_logo=\"${N}bw\"" stand/defaults/loader.conf

	dlog "installer notice"
	awk -v notice="$BR/installer-notice.txt" '
	/^msg=\$\(cat <<EOD$/ { print; while ((getline line < notice) > 0) print line; skip = 1; next }
	skip && /^EOD$/ { skip = 0 }
	skip { next }
	{ print }' usr.sbin/bsdinstall/startbsdinstall > usr.sbin/bsdinstall/startbsdinstall.new \
	    && mv usr.sbin/bsdinstall/startbsdinstall.new usr.sbin/bsdinstall/startbsdinstall
	chmod 755 usr.sbin/bsdinstall/startbsdinstall
	grep -q 'yadv labs' usr.sbin/bsdinstall/startbsdinstall
	! grep -q 'Restricted Rights Legend' usr.sbin/bsdinstall/startbsdinstall
}
