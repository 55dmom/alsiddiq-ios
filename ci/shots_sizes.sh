#!/bin/bash
# Extra screen sizes: iPhone SE (375 pt, the smallest iOS 16+ phone) and a 6.7" phone. Sample data on the phone only.
MAIN="$1"
BID=com.alsiddiq.app
t() { local s=$1; shift; perl -e 'alarm shift; exec @ARGV' "$s" "$@"; }
mkdir -p shots
RT=$(xcrun simctl list devices -j | python3 -c "import json,sys;u=sys.argv[1];d=json.load(sys.stdin)['devices'];print([k for k,v in d.items() if any(x['udid']==u for x in v)][0])" "$MAIN")
APP=$(find dd/Build/Products -name "AlSiddiq.app" -maxdepth 3 | head -1)
t 30 xcrun simctl shutdown "$MAIN" 2>/dev/null || true
devtype() { xcrun simctl list devicetypes -j | python3 -c "import json,sys,re;p=sys.argv[1];t=[x['identifier'] for x in json.load(sys.stdin)['devicetypes'] if re.search(p,x['name'])];print(t[-1] if t else '')" "$1"; }
U=""
up() { # pattern label
  [ -n "$U" ] && { t 30 xcrun simctl shutdown "$U" 2>/dev/null || true; }
  local TYPE; TYPE=$(devtype "$1")
  echo "runtime $RT type $TYPE"
  [ -n "$TYPE" ] || { echo "no device type for $1"; U=""; return 1; }
  U=$(xcrun simctl create "CI $2" "$TYPE" "$RT")
  t 120 xcrun simctl boot "$U" || true
  t 600 xcrun simctl bootstatus "$U" -b || echo "bootstatus did not finish"
  t 30 xcrun simctl status_bar "$U" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 || true
  t 180 xcrun simctl install "$U" "$APP"
  echo "up $2 $U"
}
shot() { # name who route wait
  [ -n "$U" ] || return 0
  t 20 xcrun simctl terminate "$U" $BID 2>/dev/null || true
  t 60 xcrun simctl launch "$U" $BID -AppleLanguages "(ar)" -AppleLocale ar_SA -forceDemo YES -autoLogin "$2" -startRoute "$3" $EXTRA > /dev/null
  sleep "${4:-6}"
  t 30 xcrun simctl io "$U" screenshot "shots/$1.png" > /dev/null 2>&1
  echo "shot $1"
}
if up "^iPhone SE" "iPhone SE"; then
  shot 50_se_admin_home admin home 10
  shot 51_se_teacher_home teacher home 8
  shot 52_se_viewer_home viewer home 8
  shot 53_se_tools_tab admin tools 9
  EXTRA="-ciScrollTools YES" shot 55_se_tools_tab_grid admin tools 10
  EXTRA="-ciScrollTools YES" shot 56_se_password_tools none home 11
  EXTRA="-openTool mushaf -ciMushafPage 1" shot 60_se_mushaf_p1 viewer home 12
  EXTRA="-openTool mushaf -ciMushafPage 3" shot 61_se_mushaf_p3 viewer home 12
  EXTRA="-openTool mushaf -ciMushafPage 552" shot 62_se_mushaf_p552 viewer home 12
  EXTRA="-openTool hifz -ciHifzMode recite -ciReciteDemo 5" shot 63_se_hifz_recite viewer home 11
  xcrun simctl spawn "$U" log show --last 5m --predicate 'process == "AlSiddiq" AND messageType == fault' > shots/faults_se.txt 2>/dev/null || true
fi
if up "^iPhone 1[4-9] Plus$" "6.7in"; then
  xcrun simctl list devices | grep "CI 6.7in" > shots/device_67.txt || true
  EXTRA="-openTool mushaf -ciMushafPage 1" shot 70_67_mushaf_p1 viewer home 12
  EXTRA="-openTool mushaf -ciMushafPage 3" shot 71_67_mushaf_p3 viewer home 12
  EXTRA="-openTool mushaf -ciMushafPage 552" shot 72_67_mushaf_p552 viewer home 12
  EXTRA="-openTool mushaf -ciMushafPage 3 -alsalmi.mushaf.scale 1.4" shot 73_67_mushaf_p3_bigger viewer home 12
  shot 74_67_tools_tab viewer tools 9
fi
ls -la shots | tail -12
