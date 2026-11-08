#!/bin/bash
# iPhone SE width (375 pt): the 6-tab bottom bar on the smallest screen iOS 16+ runs on. Sample data on the phone only.
MAIN="$1"
BID=com.alsiddiq.app
t() { local s=$1; shift; perl -e 'alarm shift; exec @ARGV' "$s" "$@"; }
mkdir -p shots
RT=$(xcrun simctl list devices -j | python3 -c "import json,sys;u=sys.argv[1];d=json.load(sys.stdin)['devices'];print([k for k,v in d.items() if any(x['udid']==u for x in v)][0])" "$MAIN")
TYPE=$(xcrun simctl list devicetypes -j | python3 -c "import json,sys;t=[x['identifier'] for x in json.load(sys.stdin)['devicetypes'] if 'iPhone SE' in x['name']];print(t[-1] if t else '')")
echo "runtime $RT type $TYPE"
[ -n "$TYPE" ] || { echo "no iPhone SE device type"; exit 0; }
t 30 xcrun simctl shutdown "$MAIN" 2>/dev/null || true
U=$(xcrun simctl create "CI iPhone SE" "$TYPE" "$RT")
echo "SE $U"
t 120 xcrun simctl boot "$U" || true
t 600 xcrun simctl bootstatus "$U" -b || echo "bootstatus did not finish"
t 30 xcrun simctl status_bar "$U" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 || true
APP=$(find dd/Build/Products -name "AlSiddiq.app" -maxdepth 3 | head -1)
t 180 xcrun simctl install "$U" "$APP"
shot() { # name who route wait
  t 20 xcrun simctl terminate "$U" $BID 2>/dev/null || true
  t 60 xcrun simctl launch "$U" $BID -AppleLanguages "(ar)" -AppleLocale ar_SA -forceDemo YES -autoLogin "$2" -startRoute "$3" $EXTRA > /dev/null
  sleep "${4:-6}"
  t 30 xcrun simctl io "$U" screenshot "shots/$1.png" > /dev/null 2>&1
  echo "shot $1"
}
shot 50_se_admin_home admin home 10
shot 51_se_teacher_home teacher home 8
shot 52_se_viewer_home viewer home 8
shot 53_se_tools_tab admin tools 8
shot 54_se_password none home 8
xcrun simctl spawn "$U" log show --last 5m --predicate 'process == "AlSiddiq" AND messageType == fault' > shots/faults_se.txt 2>/dev/null || true
ls -la shots | tail -8
