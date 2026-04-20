#!/bin/sh
# Zabbix Low-Level Discovery — avastab [SEVERITY] [SERVICE] kombinatsioonid
# app.log failist. Väljund on JSON massiiv, mida Zabbix discovery rule
# loeb ja kasutab item prototüüpide loomiseks.
#
# Näide väljund:
#   [{"{#SEVERITY}":"ERROR","{#SERVICE}":"payment"},{"{#SEVERITY}":"WARN","{#SERVICE}":"auth"}]

LOG=/var/log/app/app.log

if [ ! -f "$LOG" ]; then
  echo "[]"
  exit 0
fi

tail -n 5000 "$LOG" 2>/dev/null \
  | grep -oE '\[(INFO|WARN|ERROR)\] \[[a-z]+\]' \
  | sort -u \
  | awk '
    BEGIN { printf "[" }
    NR > 1 { printf "," }
    {
      sev = $1
      svc = $2
      gsub(/[\[\]]/, "", sev)
      gsub(/[\[\]]/, "", svc)
      printf "{\"{#SEVERITY}\":\"%s\",\"{#SERVICE}\":\"%s\"}", sev, svc
    }
    END { print "]" }
  '
