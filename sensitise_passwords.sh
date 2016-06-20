#!/bin/sh

# Replace actual passwords with dummies.
NR="1"
rgrep "$(printf '\t')password$(printf '\t')" * | \
	sed 's@.*\t@@' | sort | uniq | \
	while read passwd; do
		[ -z "${passwd}" ] && continue

		new_pass="secret$(printf "%0.2d" "${NR}")"
		NR="$(expr "${NR}" + 1)"

		rgrep "${passwd}" * | \
			sed 's@:.*@@' | sort | uniq | \
			while read file; do
				[ "${file}" = "$(basename "${0}")" ] && continue
				cat "${file}" | \
					sed "s@${passwd}@${new_pass}@" > \
					"${file}.new"
				mv "${file}.new" "${file}"
		done
done

# Replace my domainname with a dummy.
rgrep "$(domainname)" * | \
	sed 's@:.*@@' | sort | uniq | \
	while read file; do
		echo "${file}" | grep -q "\.git" && continue

		cat "${file}" | \
			sed "s@$(domainname)@domain\.tld@" > \
			"${file}.new"
		mv "${file}.new" "${file}"
done

# Replace my hostname with a dummy.
rgrep "$(hostname)" * | \
	sed 's@:.*@@' | sort | uniq | \
	while read file; do
		echo "${file}" | grep -q "\.git" && continue

		cat "${file}" | \
			sed "s@$(hostname)@server@" > \
			"${file}.new"
		mv "${file}.new" "${file}"
done
