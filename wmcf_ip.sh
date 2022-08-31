#!/bin/sh

# CF_TEST_URL="https://[YOUR_DOMAIN]/dl/128M"
CF_TEST_URL="${CF_TEST_URL:-https://speed.cloudflare.com/__down?bytes=1000000000}"
CF_DOMAIN=$(echo "$CF_TEST_URL" | awk -F'/' '{print $3}')
CF_IP_DIR="/tmp/cloudflare_ip"
CF_RESULT_FILE="/tmp/cloudflare_result.txt"

fetch_cf_ips() {
	DL_CF_IP_TO="/tmp/cf_ips.zip"
	mkdir -p "$CF_IP_DIR"
	rm -rf "$CF_IP_DIR"/*
	curl -kL -o "$DL_CF_IP_TO" https://github.com/ip-scanner/cloudflare/archive/refs/heads/daily.zip && unzip -j -d "$CF_IP_DIR" "$DL_CF_IP_TO" && return 0
	return 1
}

result_append() {
	[ -z "$CF_RESULT" ] && CF_RESULT="$1" || CF_RESULT=$(cat <<-EOF
	$CF_RESULT
	$1
	EOF
	)
}

convert_speed() {
	# echo "$1" 1>&2
	echo "$1" | grep -Eq "^[0-9]" || {
		echo "0,0.0Byte" && return 1
	}
	echo "$1" | awk 'BEGIN{UNIT="Byte"; TIMES=0} {
		if ($0~/g|G/) {UNIT="GB"; TIMES=1024*1024} else if ($0~/m|M/) {UNIT="MB"; TIMES=1024} else if ($0~/k|K/) {UNIT="KB"; TIMES=1}
		gsub(/[a-zA-Z]+/, "", $0);
		VALUE=$0
		TOTAL_KB=VALUE*TIMES
		if (VALUE >= 1024) {
			VALUE=$0/1024;
			if (UNIT=="GB") {UNIT="TB"} else if (UNIT=="MB") {UNIT="GB"} else if (UNIT=="KB") {UNIT="MB"}
		}
		printf ("%s,%.1f%s\n", TOTAL_KB, VALUE, UNIT);
	}'
	return 0
}

speedtest_cf_ip() {
	echo "$1" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$' || return 1
	ipset list whitelist >/dev/null 2>&1 && IPSET_LIST="whitelist"
	[ -z "$IPSET_LIST" ] || ipset add $IPSET_LIST $1 >/dev/null 2>&1
	TEST_RESULT=$(curl --resolve "$CF_DOMAIN:443:$1" --connect-timeout 1 -m ${CF_TIMEOUT:-20} -o /dev/null "$CF_TEST_URL" 2>&1)
	[ -z "$IPSET_LIST" ] || ipset del $IPSET_LIST $1 >/dev/null 2>&1
	eval $(echo "$TEST_RESULT" | tr '\r' '\n' | grep -E '[-0-9]+:[-0-9]+:[-0-9]+' | tail -n1 | awk '{gsub(/^\s+/, "", $0); gsub(/\s+/, " ", $0); print $0}' | awk '{print "SPEED_AVERAGE=\""$7"\"; SPEED_CURR=\""$NF"\""}')	
	SPEED_AVERAGE_TMP=$(convert_speed "$SPEED_AVERAGE")
	SPEED_AVERAGE_KB=$(echo "$SPEED_AVERAGE_TMP" | awk -F',' '{print $1}')
	SPEED_AVERAGE_HUMAN=$(echo "$SPEED_AVERAGE_TMP" | awk -F',' '{print $2}')
	SPEED_RESULT="OK"
	echo "$SPEED_AVERAGE_KB" | grep -Eq '[1-9]' || SPEED_RESULT="ERR"
	# [ "$SPEED_AVERAGE_KB" -gt 0 ] || SPEED_RESULT="ERR"
	if [ "$SPEED_RESULT" = "OK" ]; then
		result_append "$SPEED_AVERAGE_KB|$SPEED_AVERAGE_HUMAN|$1|$CF_AREA_CURR"
		echo "SUCCESS  $1	$SPEED_AVERAGE_HUMAN	($CF_AREA_CURR)"
	else
		echo "FAIL     $1	N/A	($CF_AREA_CURR)"
	fi
}

speedtest_cf_ips() {
	CF_IP_LIST=$(ls "$CF_IP_DIR"/*)
	echo "$1" | grep -Eq '^([0-9]{1,3}\.){1,3}\*' && {
		CF_IP_REGEX=$(echo "$1" | awk '{gsub(/\*/,".*", $0); print $0}')
		CF_IP_LIST=$(grep -Enr "$CF_IP_REGEX" "$CF_IP_DIR")
		echo "RESULT   IP_ADDRESS	SPEED	LOCATION"
		while read CF_IP
		do
			[ -z "$CF_IP" ] || {
				CF_AREA_CURR=$(echo "$CF_IP" | awk -F':' '{print $1}' | awk -F'/' '{gsub(/\.txt$/,"",$NF); print $NF}')
				CF_IP=$(echo "$CF_IP" | awk -F':' '{print $3}')
				speedtest_cf_ip "$CF_IP"
			}
		done <<-EOF
		$CF_IP_LIST
		EOF
		return 0
	}
	[ -z "$1" ] || CF_IP_LIST=$(echo "$CF_IP_LIST" | grep -Ei "$1")
	[ -z "$2" ] || CF_IP_LIST=$(echo "$CF_IP_LIST" | grep -Ei "$2")
	[ -z "$CF_IP_LIST" ] && {
		echo "[ERR] Not match any list file." && return 1
	}
	echo "RESULT   IP_ADDRESS	SPEED	LOCATION"
	while read LIST_FILE
	do
		# echo "$LIST_FILE"
		CF_AREA_CURR=$(echo "$LIST_FILE" | awk -F'/' '{gsub(/\.txt$/,"",$NF); print $NF}')
		while read CF_IP
		do
			speedtest_cf_ip "$CF_IP"
		done <<-EOF
		$(cat "$LIST_FILE")
		EOF
	done <<-EOF
	$CF_IP_LIST
	EOF
	echo "$CF_RESULT" > "$CF_RESULT_FILE"
}

if [ "$#" = "0" -o -z "$1" ]; then
	cat <<-EOF
	eg. $0 update(up) / result / list(ls)
	eg. $0 [CLOUDFLARE_IP]
	eg. $0 139.15.*
	eg. $0 Alibaba 香港
	EOF
elif [ "$1" = "update" -o "$1" = "up" ]; then
	fetch_cf_ips
elif [ "$1" = "result" ]; then
	cat "$CF_RESULT_FILE" 2>/dev/null
elif [ "$1" = "list" -o "$1" = "ls" ]; then
	ls $CF_IP_DIR 2>/dev/null
elif echo "$1" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
	speedtest_cf_ip "$@"
else
	speedtest_cf_ips "$@"
fi
