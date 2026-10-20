#!/bin/sh
#
# prepare-ports.sh -- prepare the pfSense FreeBSD-ports fork for an independent
# arm64 build:
#   1. drop/replace the ports that fetch closed components from gitlab.netgate.com
#   2. rename the pfSense ports to ${PRODUCT_NAME} (same logic as
#      poudriere_rename_ports() in tools/builder_common.sh, using git mv, plus
#      a content rewrite for the core ports whose scripts embed the name)
#
# (Re)creates the 'armsense' branch from the pinned upstream branch, so it is
# idempotent.  Runs inside the build VM.
#
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../armsense.conf"
N=$PRODUCT_NAME
NU=$(echo "$N" | tr '[:lower:]' '[:upper:]')

log() { echo ">>> $*"; }

git -C "$SRC_PORTS" config user.name armsense
git -C "$SRC_PORTS" config user.email "$PRODUCT_EMAIL"
cd "$SRC_PORTS"
log "ports: resetting branch armsense from $PORTS_BRANCH"
# phase2-poudriere.sh rewrites DISTVERSION of the meta ports in place; drop
# such working-tree edits before switching branches.
git reset -q --hard
git clean -qfd
git checkout -q -B armsense "$PORTS_BRANCH"

###########################################################################
log "1. closed components"

# security/pfSense-system: fetched the GUI source from gitlab.netgate.com and
# depended on the closed if_pppoe kernel module.  Use the tarball produced by
# rename-src.sh (pre-placed in DISTDIR) and fall back to the mpd5 PPPoE path.
M=security/pfSense-system/Makefile
sed -i '' -e '/if_pppoe-kmod>=0:net\/if_pppoe-kmod/d' "$M"
awk '
/^USE_GITLAB=/ {
	print "# armsense: source tarball produced by overlay/src/rename-src.sh, pre-placed in DISTDIR"
	print "MASTER_SITES=\t# empty"
	print "DISTNAME=\t'"$N"'-src-${PFSENSE_COMMITHASH}"
	print "MASTER_SITE_BACKUP="
	print "NO_CHECKSUM=yes"
	skip = 1; next
}
skip && /^NO_CHECKSUM=yes/ { skip = 0; next }
skip { next }
{ print }' "$M" > "$M.new" && mv "$M.new" "$M"
grep -q "^DISTNAME=.*PFSENSE_COMMITHASH" "$M"
! grep -q 'GITLAB\|if_pppoe' "$M"

# net/kea: drop the token-gated Netgate patch; build stock Kea.
sed -i '' -e '/^PATCHFILES+=.*netgate.diff/d' net/kea/Makefile
awk '/^pre-fetch:/ { skip = 1; next } skip && /^$/ { skip = 0; next } skip { next } { print }' \
    net/kea/Makefile > net/kea/Makefile.new && mv net/kea/Makefile.new net/kea/Makefile
sed -i '' -e '/netgate.diff/d' net/kea/distinfo
! grep -q 'gitlab\|netgate' net/kea/Makefile net/kea/distinfo

# sysutils/pfSense-repoc and security/pfSense-gnid: closed binaries, replaced by stand-ins.
for p in sysutils/pfSense-repoc security/pfSense-gnid; do
	git rm -q -r "$p"
	mkdir -p "$p"
	cp -R "$HERE/stubs/$(basename "$p")/." "$p/"
done

# Default configuration: hostname (console banner, GUI titles), dashboard
# widgets without the vendor support widget, theme file name.
C=sysutils/pfSense-default-config/files/config.xml
xml ed -L -P -u '/pfsense/system/hostname' -v "$N" "$C"
xml ed -L -P -u '/pfsense/widgets/sequence' -v 'system_information:col1:show,disks:col1:show,interfaces:col2:show' "$C"
if grep -q '<webguicss>pfSense' "$C"; then
	sed -i '' -e "s,<webguicss>pfSense,<webguicss>$N," "$C"
fi
xml ed -L -P -u "/pfsense/system/user[name='admin']/bcrypt-hash" -v "${DEFAULT_PASSWORD_HASH:?}" "$C"
grep -q "<hostname>$N</hostname>" "$C"
grep -q -F "<bcrypt-hash>$DEFAULT_PASSWORD_HASH</bcrypt-hash>" "$C"
! grep -q 'netgate_services' "$C"

# security/pfSense-ce: the DRM kernel modules are only relevant on amd64.
cp "$HERE/pfSense-ce.Makefile" security/pfSense-ce/Makefile

# sysutils/pfSense-repo: pkg >= 2.0.6 wants ABI + OSVERSION in pkg.conf (ALTABI
# is deprecated) and OSVERSION must be the build's __FreeBSD_version, otherwise
# pkg rejects our packages as "newer FreeBSD version".  Ship a .osversion file
# next to .abi (Netgate's repoc 'osversion' feature) and use it at install
# time.  Also disable the FreeBSD.org repositories under their current names.
M=sysutils/pfSense-repo/Makefile
awk '
/^\.include <bsd\.port\.post\.mk>/ {
	print "# armsense: ship the build OSVERSION next to .abi"
	print ".for b in DEVEL NEXT RELEASE PREVIOUS"
	print ". if defined(PKG_REPO_BRANCH_${b}) && !empty(PKG_REPO_BRANCH_${b})"
	print "PLIST_FILES+=\t${DATADIR}/pkg/repos/${PKG_REPO_FILENAME_${b}}.osversion"
	print ". endif"
	print ".endfor"
	print ""
	print "post-build:"
	print ".for b in DEVEL NEXT RELEASE PREVIOUS"
	print ". if defined(PKG_REPO_BRANCH_${b}) && !empty(PKG_REPO_BRANCH_${b})"
	print "\techo \"${OSVERSION}\" > ${WRKSRC}/${PKG_REPO_FILENAME_${b}}.osversion"
	print ". endif"
	print ".endfor"
	print ""
	print "post-install:"
	print ".for b in DEVEL NEXT RELEASE PREVIOUS"
	print ". if defined(PKG_REPO_BRANCH_${b}) && !empty(PKG_REPO_BRANCH_${b})"
	print "\t${INSTALL_DATA} ${WRKSRC}/${PKG_REPO_FILENAME_${b}}.osversion ${STAGEDIR}${DATADIR}/pkg/repos"
	print ". endif"
	print ".endfor"
	print ""
}
{ print }' "$M" > "$M.new" && mv "$M.new" "$M"
grep -q 'osversion' "$M"
PI=sysutils/pfSense-repo/files/pkg-install.in
awk '
/^ALTABI=\$\(cat / { next }
/^echo "ALTABI=\$\{ALTABI\}" >> \$\{PKG_CONF\}/ {
	print "if [ -f ${REAL_CONF%%.conf}.osversion ]; then"
	print "\techo \"OSVERSION=$(cat ${REAL_CONF%%.conf}.osversion)\" >> ${PKG_CONF}"
	print "fi"
	next
}
{ print }' "$PI" > "$PI.new" && mv "$PI.new" "$PI"
grep -q 'OSVERSION=' "$PI" && ! grep -q 'ALTABI' "$PI"
RC=sysutils/pfSense-repo/files/pfSense-repo.conf
sed -i '' -e 's/^FreeBSD: { enabled: no }$/FreeBSD: { enabled: no }\
FreeBSD-ports: { enabled: no }\
FreeBSD-ports-kmods: { enabled: no }\
FreeBSD-base: { enabled: no }/' "$RC"
grep -q 'FreeBSD-base' "$RC"

git add -A
git commit -q -m "armsense: replace components fetched from gitlab.netgate.com"

###########################################################################
log "2. rename pfSense ports to $N"

for d in $(find . -mindepth 2 -maxdepth 2 -type d -name '*pfSense*' | sed 's,^\./,,' | sort); do
	nd=$(echo "$d" | sed "s,pfSense,$N,")
	git mv "$d" "$nd"
	for f in Makefile pkg-descr pkg-plist pkg-message; do
		[ -f "$nd/$f" ] || continue
		sed -i '' -e "s,pfSense,$N,g" \
		    -e "s,https://www.pfsense.org,$PRODUCT_URL,g" \
		    -e "/^MAINTAINER=/ s,^.*$,MAINTAINER=	$PRODUCT_EMAIL," "$nd/$f"
	done

	# PHP module.  The pfSense builder's special case predates the split into
	# *_arginfo.h / *_private.h headers and the lowercase module entry, so this
	# is a superset of its edits: the extension is built as ${N}.so (loaded by
	# rc.php_ini_setup), header includes follow the renamed files, and the
	# internal pfsense_module_entry / PHP function names stay as they are.
	# The extension name reported by 'php -m' must match the entry in
	# rc.php_ini_setup's PHPMODULES, so it is renamed as well.
	case "$(basename "$nd")" in
	php*-$N-module)
		sed -i '' -e "s,PHP_PFSENSE,PHP_${NU},g" \
		    -e "s,PFSENSE_SHARED_LIBADD,${NU}_SHARED_LIBADD,g" \
		    -e "s,HAVE_PFSENSE,HAVE_${NU},g" \
		    -e "s,pfSense,$N,g" \
		    -e "s,pfsense,$N,g" "$nd/files/config.m4"
		for f in "$nd"/files/*.c "$nd"/files/*.h; do
			[ -f "$f" ] || continue
			sed -i '' -e "s,COMPILE_DL_PFSENSE,COMPILE_DL_${NU},g" \
			    -e "s,#include \"php_pfSense.h\",#include \"php_$N.h\"," \
			    -e "s,#include \"pfSense_arginfo.h\",#include \"${N}_arginfo.h\"," \
			    -e "s,#include \"pfSense_private.h\",#include \"${N}_private.h\"," \
			    -e "/\/\* Extension name \*\//s,\"pfSense\",\"$N\"," "$f"
		done
		;;
	esac

	if [ -d "$nd/files" ]; then
		find "$nd/files" -depth -name '*pfSense*' | while read -r fd; do
			git mv "$fd" "$(dirname "$fd")/$(basename "$fd" | sed "s,pfSense,$N,")"
		done
	fi
done

# Category Makefile listing the devel ports.
sed -i '' -e "s,pfSense,$N,g" devel/Makefile

# Core ports whose shipped scripts embed the product name in paths and
# command names.  (Package ports and the default config.xml are left alone:
# they use $g['product_name'] at run time, and the config root must stay
# <pfsense> for backup compatibility.)
for d in sysutils/$N-upgrade sysutils/$N-repo security/$N-system \
    sysutils/$N-Status_Monitoring sysutils/$N-repoc; do
	[ -d "$d/files" ] || continue
	grep -rIl 'pfSense' "$d/files" | grep -v 'config\.xml$' | while read -r f; do
		sed -i '' -e "s,pfSense,$N,g" "$f"
	done
done
# Composer autoloader: only the install path moves; the PHP namespace prefix
# 'pfSense\' is part of the GUI code and must stay.
grep -rIl '/usr/local/pfSense' devel/$N-composer-deps/files | while read -r f; do
	sed -i '' -e "s,/usr/local/pfSense,/usr/local/$N,g" "$f"
done
grep -q "^    'pfSense.* => array('//usr/local/$N/include')" devel/$N-composer-deps/files/composer/autoload_psr4.php

# The -system packing list names every file of the GUI source tree.  The
# generic rename above would also rename entries for files whose names we
# deliberately keep (theme CSS/JS, gettext catalogs), so regenerate the list
# from the renamed source tarball instead, deriving the exec modes from the
# tree and keeping any directory directives of the original.
tb=$(ls -t "$DISTFILES"/$N-src-*.tar.gz | head -1)
[ -f "$tb" ] || { log "no source tarball in $DISTFILES; run rename-src.sh pfsense first"; exit 1; }
plist=security/$N-system/pkg-plist
tmp=$(mktemp -d /tmp/plist.XXXXXX)
tar -xzf "$tb" -C "$tmp"
grep -E '^@(dir|sample|owner|group|mode)' "$plist" > "$tmp/directives" || true
(cd "$tmp"/$N-src-*/src && find etc usr \( -type f -o -type l \) | LC_ALL=C sort | while read -r f; do
	case "$f" in
	usr/local/*) e=${f#usr/local/} ;;
	*) e=/$f ;;
	esac
	if [ -x "$f" ] && [ ! -L "$f" ]; then echo "@(,,755) $e"; else echo "$e"; fi
done) > "$plist"
cat "$tmp/directives" >> "$plist"
rm -rf "${tmp:?}"
log "regenerated $plist: $(wc -l < "$plist" | tr -d ' ') entries"

git add -A
git commit -q -m "armsense: rename pfSense ports to $N"

###########################################################################
log "3. summary"
git --no-pager log --oneline -3
echo "renamed port directories: $(find . -mindepth 2 -maxdepth 2 -type d -name "*$N*" | wc -l | tr -d ' ')"
echo "leftover pfSense-named directories: $(find . -mindepth 2 -maxdepth 2 -type d -name '*pfSense*' | wc -l | tr -d ' ')"
for p in security/$N security/$N-system security/$N-ce sysutils/$N-repo sysutils/$N-upgrade \
    sysutils/$N-repoc security/$N-gnid devel/php-$N-module net/kea; do
	printf '%-32s ' "$p"; (cd "$p" && make -V PKGNAME 2>/dev/null) || echo "(make -V failed; check on a FreeBSD host)"
done
