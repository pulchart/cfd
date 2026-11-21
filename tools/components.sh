#!/bin/sh
# Emit the "components in this release" list, flagging each component
# whose version or date changed since the previous release tag.
#
# Usage:
#   tools/components.sh <md|plain> "PREFIX|name|version|date" ...
#
# Output is a single line with literal "\n" between bullets, ready for
# either GNU sed substitution (readme template) or awk -v (README.md);
# both turn "\n" into real newlines.
#
#   md     `name version (date)` _(new)_      (markdown, for README.md)
#   plain   name version (date) (new)         (plain text, for cfd.readme)
#
# Current versions are passed in by the Makefile (the source of truth).
# The previous release is read from that tag's Makefile via git; the
# "[$]" filter skips derived "X = $(Y)" lines so only literal source
# values are compared. Tools that used a single "X_VERSION = 1.37" line
# in older tags are handled by the X_VERSION fallback. ptable.library and
# lsptres come from the ptable submodule: their previous values are the
# dist/*.version stamps of the ptable commit that tag pinned (PTABLE names
# the checkout, default extern/ptable).
fmt=$1
shift

prev=$(git describe --tags --abbrev=0 --match 'v[0-9]*' --exclude '*-dev*' 2>/dev/null)
oldmk=$(git show "$prev:Makefile" 2>/dev/null)

old_val() {
	printf '%s\n' "$oldmk" | sed -n "s/^$1[[:space:]]*=[[:space:]]*//p" | grep -v '[$]' | head -1
}

# field $2 (1 version, 2 date) of the ptable stamp $1 at the previous tag's pin
old_ptable() {
	pin=$(git rev-parse -q --verify "$prev:extern/ptable" 2>/dev/null) || return
	git -C "${PTABLE:-extern/ptable}" show "$pin:dist/$1" 2>/dev/null | awk -v f="$2" '{print $f}'
}

out=
sep=
for entry in "$@"; do
	prefix=${entry%%|*}; rest=${entry#*|}
	name=${rest%%|*};    rest=${rest#*|}
	ver=${rest%%|*};     date=${rest#*|}

	ov=$(old_val "${prefix}_VERSION")
	[ -n "$ov" ] || ov="$(old_val "${prefix}_MAJOR").$(old_val "${prefix}_MINOR")$(old_val "${prefix}_VERSION_SUFFIX")"
	od=$(old_val "${prefix}_DATE")
	case $prefix in
	PLIB)    ov=$(old_ptable ptable.version 1);  od=$(old_ptable ptable.version 2) ;;
	LSPTRES) ov=$(old_ptable lsptres.version 1); od=$(old_ptable lsptres.version 2) ;;
	esac

	new=
	[ -n "$prev" ] && [ -n "$oldmk" ] &&
		[ "$ver ($date)" != "$ov ($od)" ] && new=1

	if [ "$fmt" = md ]; then
		line="- \`$name $ver ($date)\`${new:+ _(new)_}"
	else
		line="- $name $ver ($date)${new:+ (new)}"
	fi

	out="$out$sep$line"
	sep='\n'
done

printf '%s' "$out"
