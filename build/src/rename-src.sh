#!/bin/sh
#
# rename-src.sh -- apply the armsense product rename.
#
#   sh rename-src.sh pfsense   rename inside the pfSense GUI/backend source tree
#                              and produce the source tarball consumed by the
#                              security/<product>-system port
#   sh rename-src.sh freebsd   rename the literal hooks in the FreeBSD-src fork
#   sh rename-src.sh           both
#
# Each part (re)creates an 'armsense' branch from the pinned upstream branch,
# so the script is idempotent.  Runs inside the build VM.
#
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../armsense.conf"
N=$PRODUCT_NAME
L=$PRODUCT_LABEL
BR=$HERE/../branding
. "$HERE/debrand-src.sh"

log() { echo ">>> $*"; }
gitid() { git -C "$1" config user.name armsense; git -C "$1" config user.email "$PRODUCT_EMAIL"; }
mv_() { if [ -e "$1" ]; then git mv "$1" "$2"; else log "note: $1 not present"; fi; }

rename_pfsense() {
	log "pfsense: resetting branch armsense from $PFSENSE_BRANCH"
	gitid "$SRC_PFSENSE"
	cd "$SRC_PFSENSE"
	# Drop leftovers of an interrupted run before re-cutting the branch.
	git reset -q --hard
	git clean -qfd
	git checkout -q -B armsense "$PFSENSE_BRANCH"

	# Files and directories whose names carry the product name.  The PHP
	# code derives these paths from $g['product_name'] (e.g.
	# "/etc/{$product_name}-ddb.conf"), so the names must follow the rename.
	mv_ src/etc/pfSense-rc                      src/etc/$N-rc
	mv_ src/etc/pfSense-rc.shutdown             src/etc/$N-rc.shutdown
	mv_ src/etc/pfSense-devd.conf               src/etc/$N-devd.conf
	mv_ src/etc/pfSense-ddb.conf                src/etc/$N-ddb.conf
	mv_ src/etc/pfSense.obsoletedfiles          src/etc/$N.obsoletedfiles
	mv_ src/usr/local/sbin/pfSense-dhclient-script src/usr/local/sbin/$N-dhclient-script
	mv_ src/usr/local/share/pfSense             src/usr/local/share/$N
	mv_ src/usr/local/pfSense                   src/usr/local/$N
	ln -sfn src/usr/local/$N/include/vendor vendor && git add vendor

	# Product identity.  xml_rootobj stays 'pfsense' on purpose so existing
	# pfSense config.xml backups keep importing.
	sed -i '' \
	    -e "s/'product_name' => 'pfSense'/'product_name' => '$N'/" \
	    -e "s/'product_label' => 'pfSense'/'product_label' => '$L'/" \
	    -e "s|'product_label_html' => 'Netgate pfSense<sup>&#174;</sup>'|'product_label_html' => '$L'|" \
	    src/etc/inc/globals.inc
	grep -q "'product_name' => '$N'" src/etc/inc/globals.inc

	# The few literal path references that do not go through product_name.
	sed -i '' -e "s,/usr/local/share/pfSense,/usr/local/share/$N,g" \
	    src/etc/$N-rc src/etc/inc/pfsense-utils.inc
	sed -i '' -e "s,/usr/local/pfSense/include,/usr/local/$N/include,g" src/etc/rc.php_ini_setup
	sed -i '' -e "s,/usr/local/sbin/pfSense-dhclient-script,/usr/local/sbin/$N-dhclient-script,g" \
	    src/etc/inc/interfaces.inc src/usr/local/www/status_interfaces.php
	sed -i '' -e "s,/etc/pfSense.obsoletedfiles,/etc/$N.obsoletedfiles,g" src/etc/phpshellsessions/gitsync
	sed -i '' -e "s,pfSense-upgrade,$N-upgrade,g" src/usr/local/www/pkg_mgr_install.php src/etc/inc/pkg-utils.inc
	sed -i '' -e "s,\['placeholder' => 'pfSense'\],['placeholder' => '$N']," src/usr/local/www/system.php
	# The PHP extension is built as ${N}.so by the renamed devel/php-${N}-module port.
	sed -i '' -e 's/^PHPMODULES="$PHPMODULES pfSense"$/PHPMODULES="$PHPMODULES '"$N"'"/' src/etc/rc.php_ini_setup
	grep -q "PHPMODULES=\"\$PHPMODULES $N\"" src/etc/rc.php_ini_setup
	# The module verification loop removes every php.ini line containing a
	# module name that failed to load; with a module named after the product
	# that would also delete the include_path line.  Only drop extension= lines.
	sed -i '' -e 's|/usr/bin/grep -v "\$EXT" /usr/local/etc/php.ini|/usr/bin/grep -v -i "^extension=\${EXT}\\.so" /usr/local/etc/php.ini|' src/etc/rc.php_ini_setup
	grep -q 'grep -v -i "^extension=' src/etc/rc.php_ini_setup

	debrand_pfsense

	log "pfsense: remaining literal references (expect only comments/obsoleted lists):"
	grep -rIn -- '/usr/local/share/pfSense\|/usr/local/pfSense\|/etc/pfSense-\|/etc/pfSense\.\|pfSense-upgrade\|pfSense-repoc\|pfSense-dhclient' src \
	    | grep -v '\.po:\|\.pot:\|\.obsoletedfiles:' || true

	git add -A
	git commit -q -m "armsense: rename product from pfSense to $N" || true
	PFSENSE_COMMIT=$(git rev-parse HEAD)
	log "pfsense: branch armsense at $PFSENSE_COMMIT"

	# Source tarball for security/<product>-system (replaces Netgate's GitLab fetch).
	mkdir -p "$DISTFILES"
	tb="$DISTFILES/$N-src-$PFSENSE_COMMIT.tar.gz"
	git archive --format=tar.gz --prefix="$N-src-$PFSENSE_COMMIT/" -o "$tb" armsense
	tar -tzf "$tb" | grep -q "^$N-src-$PFSENSE_COMMIT/src/etc/inc/globals.inc$"
	echo "$PFSENSE_COMMIT" > "$A/pfsense-commit"
	log "pfsense: tarball $tb"
}

rename_freebsd() {
	log "freebsd: resetting branch armsense from $FREEBSD_BRANCH"
	gitid "$SRC_FREEBSD"
	cd "$SRC_FREEBSD"
	git reset -q --hard
	git clean -qfd
	git checkout -q -B armsense "$FREEBSD_BRANCH"

	# /etc/rc and /etc/rc.shutdown hand over to the product rc scripts by name.
	sed -i '' -e "s,/etc/pfSense-rc,/etc/$N-rc,g" libexec/rc/rc libexec/rc/rc.shutdown
	grep -q "/etc/$N-rc" libexec/rc/rc

	# Installer.
	sed -i '' \
	    -e "s,pfSense_Install,${N}_Install,g" \
	    -e "s,OSNAME=pfSense,OSNAME=$N," \
	    -e "s,ROOTPASS_PLAIN=pfsense,ROOTPASS_PLAIN=$N," \
	    -e "s,ZFSBOOT_POOL_NAME=pfSense,ZFSBOOT_POOL_NAME=$N," \
	    -e "s,pfSense Installer,$L Installer,g" \
	    -e "s,Welcome to pfSense!,Welcome to $L!," \
	    -e "s,\"Install pfSense\",\"Install $L\"," \
	    -e "s,Installation of pfSense complete,Installation of $L complete," \
	    usr.sbin/bsdinstall/startbsdinstall
	sed -i '' -e "s,pfSense Installer,$L Installer,g" usr.sbin/bsdinstall/scripts/fix_fstab
	sed -i '' -e "s,loader.conf.pfSense,loader.conf.$N,g; s,loader.conf.local.pfSense,loader.conf.local.$N,g" \
	    usr.sbin/bsdinstall/scripts/config
	sed -i '' -e "s,^OSNAME=pfSense,OSNAME=$N," release/conf/pfSense_installer_src.conf

	# Loader menu branding.
	if [ ! -f stand/lua/brand-$N.lua ]; then
		cat > stand/lua/brand-$N.lua <<EOB
--
-- $L loader brand
--
return {
	graphic = {
		"                                        ",
		"   $L                                 ",
		"   FreeBSD based firewall / router      ",
		"                                        ",
	},
}
EOB
		sed -i '' -e "s,^\tbrand-pfSense.lua,\tbrand-pfSense.lua \\\\\\
\tbrand-$N.lua," stand/lua/Makefile
	fi
	sed -i '' -e "s,^loader_brand=\"pfSense\",loader_brand=\"$N\"," \
	    -e "s,Welcome to pfSense,Welcome to $L," stand/defaults/loader.conf

	# Kernel configuration (also installed by phase1-base.sh; keep it in the branch).
	install -m 644 "$HERE/../kernel/$N" "sys/arm64/conf/$N"

	debrand_freebsd

	git add -A
	git commit -q -m "armsense: rename product hooks from pfSense to $N" || true
	log "freebsd: branch armsense at $(git rev-parse --short HEAD)"
	git --no-pager show --stat HEAD | tail -12
}

case "${1:-all}" in
pfsense) rename_pfsense ;;
freebsd) rename_freebsd ;;
all) rename_pfsense; rename_freebsd ;;
*) echo "usage: $0 [pfsense|freebsd|all]"; exit 1 ;;
esac
