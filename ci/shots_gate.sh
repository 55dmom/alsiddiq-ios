#!/bin/bash
# Short pass: the opening (password) screen on an iPhone SE and a 6.7" phone, plus a few SE screens of the v3.8 changes
# (home header, settings, admin page, tools tab, teacher attendance, budget).
# Sample data on the phone only. The full passes stay in ci/shots.sh and ci/shots_sizes.sh.
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
  # the first device type of the list ("a|b|c") that this runtime can create
  local TYPE="" P
  U=""
  IFS='|' read -ra PATS <<< "$1"
  for P in "${PATS[@]}"; do
    TYPE=$(devtype "$P")
    [ -n "$TYPE" ] || { echo "no device type for $P"; continue; }
    U=$(xcrun simctl create "CI $2" "$TYPE" "$RT" 2>/dev/null) && [ -n "$U" ] && break
    echo "runtime $RT cannot create $TYPE"; U=""
  done
  [ -n "$U" ] || { echo "no small device for $1"; return 1; }
  echo "runtime $RT type $TYPE" | tee -a shots/device_small.txt
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
if up "^iPhone SE \\(3rd|^iPhone SE|^iPhone 13 mini|^iPhone 12 mini|^iPhone 16e|^iPhone 17e" "iPhone SE"; then
  shot L1_se_password none home 11
  shot L3_se_admin_home_header admin home 10
  shot L4_se_viewer_settings viewer viewer_settings 8
  shot L5_se_admin_page admin more 8
  EXTRA="-ciScrollTools NO" shot L6_se_tools_tab viewer tools 9
  EXTRA="-ciV38Demo YES" shot L7_se_teacher_attendance admin teacher_attendance 9
  EXTRA="-ciV38Demo YES -ciTimeSheet YES" shot L11_se_teacher_time_sheet admin teacher_attendance 10
  EXTRA="-ciV39Contact YES" shot L12_se_password_contact none home 11
  EXTRA="-ciV39Contact YES" shot L13_se_admin_switch admin more 9
  EXTRA="-ciV38Demo YES" shot L8_se_budget admin budget 9
  EXTRA="-ciV38Demo YES" shot L9_se_subscriptions_admin admin subscriptions 9
  EXTRA="-ciV38Demo YES" shot M1_se_subscriptions_teacher teacher subscriptions 9
  EXTRA="-ciV38Demo YES" shot M2_se_circles_thumbs admin circles 9
  EXTRA="-ciV38Demo YES" shot M3_se_circle_banner teacher circle/c1 10
  shot M4_se_teacher_home teacher home 9
  EXTRA="-ciV38Demo YES" shot M5_se_circle_edit_teachers admin circle_edit/c1 9
  EXTRA="-ciV38Demo YES" shot M6_se_announcements_photo admin announcements 10
  EXTRA="-ciV38Demo YES" shot M7_se_viewer_home viewer home 10
  shot M8_se_admin_home admin home 9
fi
if up "^iPhone 1[4-9] Plus$|^iPhone 1[4-9] Pro Max$" "6.7in"; then
  xcrun simctl list devices | grep "CI 6.7in" > shots/device_67.txt || true
  shot L0_67_warmup none home 20   # the first launch on a fresh device is slow (run 25 caught the springboard)
  shot L2_67_password none home 12
fi
ls -la shots | tail -8
