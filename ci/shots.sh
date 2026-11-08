#!/bin/bash
# Installs the simulator build and captures the v3 screens (sample data on the phone only).
U="$1"
BID=com.alsiddiq.app
t() { local s=$1; shift; perl -e 'alarm shift; exec @ARGV' "$s" "$@"; } # macOS has no timeout(1)
echo "boot $(date +%T)"
t 120 xcrun simctl boot "$U" || true
t 600 xcrun simctl bootstatus "$U" -b || echo "bootstatus did not finish"
echo "booted $(date +%T)"
t 30 xcrun simctl status_bar "$U" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 || true
APP=$(find dd/Build/Products -name "AlSiddiq.app" -maxdepth 3 | head -1)
t 180 xcrun simctl install "$U" "$APP"
echo "installed $(date +%T)"
mkdir -p shots
shot() { # name who route wait
  t 20 xcrun simctl terminate "$U" $BID 2>/dev/null || true
  t 60 xcrun simctl launch "$U" $BID -AppleLanguages "(ar)" -AppleLocale ar_SA -forceDemo "${FORCE_DEMO:-YES}" -autoLogin "$2" -startRoute "$3" > /dev/null
  sleep "${4:-6}"
  t 30 xcrun simctl io "$U" screenshot "shots/$1.png" > /dev/null 2>&1
  echo "shot $1"
}
splash() {
  # a normal launch (no autoLogin) shows the full splash animation
  t 20 xcrun simctl terminate "$U" $BID 2>/dev/null || true
  t 60 xcrun simctl launch "$U" $BID -AppleLanguages "(ar)" -AppleLocale ar_SA -forceDemo YES -holdSplash 8 > /dev/null
  sleep 0.4; t 30 xcrun simctl io "$U" screenshot "shots/00a_splash_start.png" > /dev/null 2>&1
  sleep 2.5; t 30 xcrun simctl io "$U" screenshot "shots/00b_splash.png" > /dev/null 2>&1
  echo "shot splash"
}
splash
shot 00_password none home 10
shot 01_viewer_home viewer home 8
shot 02_viewer_settings viewer viewer_settings
shot 03_role_login_admin viewer role_login/admin
shot 04_role_login_teachers viewer role_login/teacher
shot 05_viewer_students viewer students
shot 06_viewer_student viewer student/s1
shot 07_admin_home admin home 8
shot 08_admin_panel admin more
shot 09_admin_passwords admin passwords
shot 10_admin_teachers admin teachers
shot 11_admin_circles admin circles
shot 12_teacher_home teacher home 8
shot 13_teacher_circle teacher circle/c2
shot 14_teacher_record teacher record/s2
shot 15_teacher_attendance teacher attendance/c3
shot 16_teacher_report teacher circle_report/c1
shot 17_teacher_student_edit teacher student_edit/s1
xcrun simctl spawn "$U" log show --last 5m --predicate 'process == "AlSiddiq" AND messageType == fault' > shots/faults.txt 2>/dev/null || true
ls -la shots
