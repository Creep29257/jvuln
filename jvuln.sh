#!/bin/sh
# jvuln - package inventory + known vulnerabilities for a FreeBSD host and its jails.
#
# Scans the host and every jail with pkg(8), checks them against the FreeBSD
# vuxml database, and writes ONE static HTML page. No daemon, no open port:
# where the page lives (and who can read it) is up to you, see jvuln.conf.
#
# Jails are found automatically: Bastille layout if present, otherwise the
# running jails reported by jls(8) (works with iocage, ezjail, plain jail.conf...).
#
# Usage: jvuln.sh [-c config] [-o output.html]
# Needs: pkg(8), root (to read jail pkg databases), network on the host only.
#
# License: BSD 2-clause.
set -u
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
JVULN_VERSION="0.2"

# --- Configuration --------------------------------------------------------
# Precedence: command line > environment > config file > built-in default.
usage() { echo "usage: jvuln.sh [-c config] [-o output.html]" >&2; exit 2; }
CONF="${JVULN_CONF:-/usr/local/etc/jvuln.conf}"
CLI_OUT=""
while getopts c:o: o; do
	case $o in c) CONF=$OPTARG ;; o) CLI_OUT=$OPTARG ;; *) usage ;; esac
done
# The config file is plain sh (VAR=value). Remember what the environment set,
# source the file, then let the environment win again.
_e_BASTILLE="${BASTILLE:-}"
_e_MGMT_JAIL="${MGMT_JAIL:-}"
_e_VULNDB="${VULNDB:-}"
_e_OUT="${OUT:-}"
_e_LANG_UI="${LANG_UI:-}"
_e_JAIL_SOURCE="${JAIL_SOURCE:-}"
_e_INCLUDE_HOST="${INCLUDE_HOST:-}"
_e_EXCLUDE_JAILS="${EXCLUDE_JAILS:-}"
_e_ONLY_JAILS="${ONLY_JAILS:-}"
_e_TITLE="${TITLE:-}"
_e_FILE_MODE="${FILE_MODE:-}"
_e_FILE_OWNER="${FILE_OWNER:-}"
case "$CONF" in */*) ;; *) CONF="./$CONF" ;; esac   # "." searches PATH otherwise
[ -r "$CONF" ] && . "$CONF"
[ -n "$_e_BASTILLE" ] && BASTILLE=$_e_BASTILLE
[ -n "$_e_MGMT_JAIL" ] && MGMT_JAIL=$_e_MGMT_JAIL
[ -n "$_e_VULNDB" ] && VULNDB=$_e_VULNDB
[ -n "$_e_OUT" ] && OUT=$_e_OUT
[ -n "$_e_LANG_UI" ] && LANG_UI=$_e_LANG_UI
[ -n "$_e_JAIL_SOURCE" ] && JAIL_SOURCE=$_e_JAIL_SOURCE
[ -n "$_e_INCLUDE_HOST" ] && INCLUDE_HOST=$_e_INCLUDE_HOST
[ -n "$_e_EXCLUDE_JAILS" ] && EXCLUDE_JAILS=$_e_EXCLUDE_JAILS
[ -n "$_e_ONLY_JAILS" ] && ONLY_JAILS=$_e_ONLY_JAILS
[ -n "$_e_TITLE" ] && TITLE=$_e_TITLE
[ -n "$_e_FILE_MODE" ] && FILE_MODE=$_e_FILE_MODE
[ -n "$_e_FILE_OWNER" ] && FILE_OWNER=$_e_FILE_OWNER

LANG_UI="${LANG_UI:-en}"                      # en | fr
JAIL_SOURCE="${JAIL_SOURCE:-auto}"            # auto | bastille | jls
BASTILLE="${BASTILLE:-/usr/local/bastille}"   # only used with Bastille
MGMT_JAIL="${MGMT_JAIL:-}"                    # Bastille jail that receives the page (optional)
VULNDB="${VULNDB:-/var/db/pkg/vuln.xml}"
INCLUDE_HOST="${INCLUDE_HOST:-yes}"           # yes | no
EXCLUDE_JAILS="${EXCLUDE_JAILS:-}"            # space-separated sh patterns, e.g. "test-* old"
ONLY_JAILS="${ONLY_JAILS:-}"                  # if set: whitelist of jail names
TITLE="${TITLE:-jvuln - $(hostname)}"
FILE_MODE="${FILE_MODE:-644}"
FILE_OWNER="${FILE_OWNER:-}"                  # e.g. root:wheel
if [ -z "${OUT:-}" ]; then
	if [ -n "$MGMT_JAIL" ]; then
		OUT="$BASTILLE/jails/$MGMT_JAIL/root/usr/local/share/jvuln/index.html"
	else
		OUT="/var/db/jvuln/index.html"
	fi
fi
[ -n "$CLI_OUT" ] && OUT=$CLI_OUT

# --- UI strings -----------------------------------------------------------
case "$LANG_UI" in
fr) L_HTML=fr; L_GEN="Généré le"; L_DB="base vuxml du"
    L_SCOPE="couvre les paquets pkg uniquement (ni noyau/base, ni logiciels installés hors pkg)."
    L_SUMMARY="Synthèse"; L_TARGET="Cible"; L_RELEASE="Release"; L_PKGS="Paquets"; L_VULNS="Vulnérables"
    L_UNREADABLE="? (pkg illisible)"; L_VPKG="Paquet installé"; L_ISSUE="Problème"; L_ADVISORY="Avis"
    L_NONE="Aucune vulnérabilité connue."; L_INV="Inventaire complet"; L_PKG="Paquet"; L_VER="Version"
    L_ORIGIN="Origine"; L_CROSS="Vue croisée par paquet"; L_TGTS="Cibles"; L_VERSIONS="Versions installées"
    L_DBFAIL="échec du téléchargement (base possiblement périmée)"; L_DONE="écrit"; L_TGT="cibles"
    L_KERNEL="noyau"
    L_ATTN="À surveiller"; L_ATTNHELP="Paquets vulnérables, ou présents en plusieurs versions (cible en retard)."
    L_NOATTN="Rien à signaler : aucun paquet vulnérable ni en version divergente."
    L_VULNIN="Vulnérable dans"; L_ALLPKGS="Tous les paquets"; L_FILTER="Filtrer (nom, version, cible)…" ;;
*)  L_HTML=en; L_GEN="Generated"; L_DB="vuxml database from"
    L_SCOPE="covers pkg packages only (not the base system/kernel, nor software installed outside pkg)."
    L_SUMMARY="Summary"; L_TARGET="Target"; L_RELEASE="Release"; L_PKGS="Packages"; L_VULNS="Vulnerable"
    L_UNREADABLE="? (pkg unreadable)"; L_VPKG="Installed package"; L_ISSUE="Issue"; L_ADVISORY="Advisory"
    L_NONE="No known vulnerability."; L_INV="Full inventory"; L_PKG="Package"; L_VER="Version"
    L_ORIGIN="Origin"; L_CROSS="Cross-view by package"; L_TGTS="Targets"; L_VERSIONS="Installed versions"
    L_DBFAIL="download failed (database may be stale)"; L_DONE="written"; L_TGT="targets"
    L_KERNEL="kernel"
    L_ATTN="Needs attention"; L_ATTNHELP="Vulnerable packages, or packages installed in several versions (a target is behind)."
    L_NOATTN="Nothing to report: no vulnerable package and no diverging version."
    L_VULNIN="Vulnerable in"; L_ALLPKGS="All packages"; L_FILTER="Filter (name, version, target)..." ;;
esac

TMP=$(mktemp -d /tmp/jvuln.XXXXXX) || exit 1
trap 'rm -rf "$TMP"' EXIT INT TERM

esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

# --- 1. Vulnerability database ---------------------------------------------
# Fetched ONCE on the host and reused for every jail: jails need no network.
# (pkg audit exits 1 when it finds vulnerabilities: that is not a failure.)
DBSTATE="ok"
pkg audit -F >/dev/null 2>&1 || [ $? -eq 1 ] || DBSTATE="$L_DBFAIL"
[ -f "$VULNDB" ] || { echo "jvuln: $VULNDB not found" >&2; exit 1; }
DBDATE=$(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$VULNDB")

# --- 2. Targets ---------------------------------------------------------------
# $TMP/jails.list: one "name<TAB>root path" per jail.
: >"$TMP/jails.list"
if [ "$JAIL_SOURCE" = auto ]; then
	[ -d "$BASTILLE/jails" ] && JAIL_SOURCE=bastille || JAIL_SOURCE=jls
fi
if [ "$JAIL_SOURCE" = bastille ]; then
	for d in "$BASTILLE"/jails/*/; do
		[ -d "${d}root" ] && printf '%s\t%s\n' "$(basename "$d")" "${d}root" >>"$TMP/jails.list"
	done
else
	# Running jails only: jls -n prints "name=<n> path=<p>" per jail.
	jls -n name path 2>/dev/null | sed -n 's/^name=\([^ ]*\) path=\(.*\)$/\1\t\2/p' >>"$TMP/jails.list"
fi

TARGETS=""
[ "$INCLUDE_HOST" = yes ] && TARGETS="host"
while IFS="	" read -r j root; do
	skip=0
	for pat in $EXCLUDE_JAILS; do case "$j" in $pat) skip=1 ;; esac; done
	if [ -n "$ONLY_JAILS" ]; then
		skip=1; for w in $ONLY_JAILS; do [ "$j" = "$w" ] && skip=0; done
	fi
	[ $skip -eq 1 ] && continue
	# No pkg database = not a pkg-managed FreeBSD jail (Linux jail, empty jail...): skip.
	[ -d "$root/var/db/pkg" ] || continue
	TARGETS="$TARGETS $j"
	printf '%s\t%s\n' "$j" "$root" >"$TMP/root.$j"
done <"$TMP/jails.list"
[ -n "$TARGETS" ] || { echo "jvuln: no target found" >&2; exit 1; }

# --- 3. Scan one target -> $TMP/<t>.{meta,pkgs,raw,vuln} ------------------------
scan() {
	t="$1"
	if [ "$t" = host ]; then
		PKG="pkg"
		rel="$(freebsd-version -u) ($L_KERNEL $(freebsd-version -k))"
	else
		root=$(cut -f2 "$TMP/root.$t"); PKG="pkg -r $root"
		rel=""
		if [ "$JAIL_SOURCE" = bastille ]; then
			# Thin jail: userland comes from releases/<X> through nullfs (see fstab).
			r=$(sed -n 's#.*/releases/\([^/ ]*\).*#\1#p' "$BASTILLE/jails/$t/fstab" 2>/dev/null | head -1)
			rel="$r"
			[ -n "$r" ] && [ -x "$BASTILLE/releases/$r/bin/freebsd-version" ] &&
				rel="$r -> $("$BASTILLE/releases/$r/bin/freebsd-version" -u 2>/dev/null)"
		fi
		[ -n "$rel" ] || rel=$(jls -j "$t" -n osrelease 2>/dev/null | sed 's/^osrelease=/'"$L_KERNEL"' /')
		[ -n "$rel" ] || rel="?"
	fi
	echo "$rel" >"$TMP/$t.meta"
	$PKG query '%n|%v|%o' 2>/dev/null | sort >"$TMP/$t.pkgs"
	$PKG audit -f "$VULNDB" >"$TMP/$t.raw" 2>&1
	# One record per advisory: pkg<TAB>description<TAB>CVEs<TAB>link
	awk '
	function flush() { if (pk != "") printf "%s\t%s\t%s\t%s\n", pk, desc, cve, www; pk=""; desc=""; cve=""; www="" }
	/ is vulnerable:$/ { flush(); pk=$1; next }
	pk == "" { next }
	/^  CVE: /  { cve = cve (cve==""?"":" ") $2; next }
	/^  WWW: /  { if (www=="") www=$2; next }
	/^  [^ ]/   { sub(/^  +/,""); desc = desc (desc==""?"":" ; ") $0; next }
	END { flush() }' "$TMP/$t.raw" >"$TMP/$t.vuln"
}
for t in $TARGETS; do scan "$t"; done

# --- 4. HTML ------------------------------------------------------------------------
mkdir -p "$(dirname "$OUT")" || exit 1
H="$TMP/out.html"
E='function e(s){gsub(/&/,"\\&amp;",s);gsub(/</,"\\&lt;",s);gsub(/>/,"\\&gt;",s);return s}'
{
cat <<HTML
<!DOCTYPE html><html lang="$L_HTML"><head><meta charset="utf-8">
<title>$(printf %s "$TITLE" | esc)</title>
<style>
body{font:14px/1.4 sans-serif;margin:2em;color:#222}
table{border-collapse:collapse;margin:.5em 0 1.5em}
td,th{border:1px solid #bbb;padding:3px 8px;text-align:left;vertical-align:top}
th{background:#eee}.bad{background:#fdd;font-weight:bold}.ok{background:#dfd}
code{font-size:12px}details{margin:.5em 0}.muted{color:#666}h3{margin:.8em 0 .2em}
</style></head><body>
<h1>$(printf %s "$TITLE" | esc)</h1>
<p>$L_GEN $(date '+%Y-%m-%d %H:%M') · $L_DB $DBDATE ($(printf %s "$DBSTATE" | esc)) · $L_SCOPE</p>
<h2>$L_SUMMARY</h2>
<table><tr><th>$L_TARGET</th><th>$L_RELEASE</th><th>$L_PKGS</th><th>$L_VULNS</th></tr>
HTML
for t in $TARGETS; do
	np=$(wc -l <"$TMP/$t.pkgs" | tr -d ' ')
	# count distinct vulnerable packages, not advisories
	nv=$(cut -f1 "$TMP/$t.vuln" | sort -u | wc -l | tr -d ' ')
	cls=ok; [ "$nv" -gt 0 ] && cls=bad
	[ "$np" -eq 0 ] && { cls=bad; nv="$L_UNREADABLE"; }
	printf '<tr><td><a href="#t-%s">%s</a></td><td>%s</td><td>%s</td><td class="%s">%s</td></tr>\n' \
		"$t" "$(printf %s "$t" | esc)" "$(esc <"$TMP/$t.meta")" "$np" "$cls" "$nv"
done
echo '</table>'

for t in $TARGETS; do
	printf '<h2 id="t-%s">%s</h2>\n' "$t" "$(printf %s "$t" | esc)"
	if [ -s "$TMP/$t.vuln" ]; then
		echo "<table><tr><th>$L_VPKG</th><th>$L_ISSUE</th><th>CVE</th><th>$L_ADVISORY</th></tr>"
		awk -F'\t' "$E"'
		{ link = ($4 ~ /^https:\/\/vuxml\.FreeBSD\.org\//) ? "<a href=\"" $4 "\">vuxml</a>" : e($4)
		  printf "<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n", e($1), e($2), e($3), link }' "$TMP/$t.vuln"
		echo '</table>'
	else
		echo "<p class=\"ok\">$L_NONE</p>"
	fi
	echo "<details><summary>$L_INV</summary><table><tr><th>$L_PKG</th><th>$L_VER</th><th>$L_ORIGIN</th></tr>"
	awk -F'|' "$E"'
	{ printf "<tr><td>%s</td><td>%s</td><td>%s</td></tr>\n", e($1), e($2), e($3) }' "$TMP/$t.pkgs"
	echo '</table></details>'
done

# Cross-view: pivot of the inventories, one row per package, versions grouped.
# Names of vulnerable packages (pkg-version -> pkg) with their target.
: >"$TMP/vnames"
for t in $TARGETS; do
	cut -f1 "$TMP/$t.vuln" | sed 's/-[^-]*$//' | sort -u | awk -v t="$t" '{ printf "%s\t%s\n", $0, t }' >>"$TMP/vnames"
done
# Rows are written as "<flag><TAB><html row>"; flag 1 = needs attention.
for t in $TARGETS; do
	awk -F'|' -v t="$t" '{ printf "%s\t%s\t%s\n", $1, $2, t }' "$TMP/$t.pkgs"
done | sort | awk -F'\t' -v vf="$TMP/vnames" "$E"'
FILENAME == vf { vt[$1] = vt[$1] (vt[$1] == "" ? "" : ", ") $2; next }
function flush(   flag, vcell) {
	if (p == "") return
	flag = (nv > 1 || (p in vt)) ? 1 : 0
	vcell = (p in vt) ? " class=\"bad\">" e(vt[p]) : ">"
	printf "%d\t<tr class=\"r\"><td>%s</td><td%s>%s</td><td>%d</td><td%s</td></tr>\n", flag, e(p), (nv > 1 ? " class=\"bad\"" : ""), l, nt, vcell
}
$1 != p { flush(); p = $1; v = ""; l = ""; nv = 0; nt = 0 }
{
	if ($2 != v) { v = $2; nv++; l = l (l == "" ? "" : "<br>") "<b>" e($2) "</b>: " e($3) }
	else l = l ", " e($3)
	nt++
}
END { flush() }' "$TMP/vnames" - >"$TMP/cross.rows"   # vnames first, then stdin
HEAD="<tr><th>$L_PKG</th><th>$L_VERSIONS</th><th>$L_TGTS</th><th>$L_VULNIN</th></tr>"

echo "<h2>$L_CROSS</h2><h3>$L_ATTN</h3><p class=\"muted\">$L_ATTNHELP</p>"
if grep -q '^1	' "$TMP/cross.rows"; then
	echo "<table>$HEAD"; sed -n 's/^1	//p' "$TMP/cross.rows"; echo '</table>'
else
	echo "<p class=\"ok\">$L_NOATTN</p>"
fi
echo "<details id=\"alld\"><summary>$L_ALLPKGS ($(wc -l <"$TMP/cross.rows" | tr -d ' '))</summary>"
echo "<p><input id=\"f\" size=\"40\" placeholder=\"$L_FILTER\"></p><table id=\"all\">$HEAD"
cut -f2- "$TMP/cross.rows"
echo '</table></details>'
cat <<'JS'
<script>
document.getElementById('f').oninput=function(){
 var q=this.value.toLowerCase();
 document.getElementById('alld').open=true;
 var r=document.querySelectorAll('#all tr.r');
 for(var i=0;i<r.length;i++)r[i].style.display=r[i].textContent.toLowerCase().indexOf(q)<0?'none':'';
};
</script>
</body></html>
JS
} >"$H"

# --- 5. Atomic write ---------------------------------------------------------------
cp "$H" "$OUT.new" && chmod "$FILE_MODE" "$OUT.new" || exit 1
[ -n "$FILE_OWNER" ] && chown "$FILE_OWNER" "$OUT.new"
mv "$OUT.new" "$OUT"
echo "jvuln: $OUT $L_DONE ($(echo $TARGETS | wc -w | tr -d ' ') $L_TGT)"
