#!/bin/bash
# Installs the simulator build and captures the main screens of every role (demo data).
U="$1"
BID=com.alsiddiq.app
xcrun simctl boot "$U" || true
xcrun simctl bootstatus "$U" -b
xcrun simctl status_bar "$U" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 || true
APP=$(find dd/Build/Products -name "AlSiddiq.app" -maxdepth 3 | head -1)
xcrun simctl install "$U" "$APP"
mkdir -p shots
shot() { # name role route wait
  xcrun simctl terminate "$U" $BID 2>/dev/null || true
  xcrun simctl launch "$U" $BID -AppleLanguages "(ar)" -AppleLocale ar_SA -autoLogin "$2" -startRoute "$3" > /dev/null
  sleep "${4:-6}"
  xcrun simctl io "$U" screenshot "shots/$1.png" > /dev/null 2>&1
  echo "shot $1"
}
shot 00_login login home 10
shot 01_admin_home admin home 8
shot 02_admin_circles admin circles
shot 03_admin_students admin students
shot 04_admin_reports admin reports
shot 05_admin_more admin more
shot 06_teacher_home teacher home
shot 07_teacher_record teacher record/s1
shot 08_teacher_attendance teacher attendance
shot 09_circle_detail teacher circle/c1
shot 10_student_home student home
shot 11_student_rewards student rewards
shot 12_parent_home parent home
shot 13_student_profile parent student/s1
shot 14_parent_notifications parent notifications
shot 15_admin_add_student admin student_edit/new
xcrun simctl spawn "$U" log show --last 5m --predicate 'process == "AlSiddiq" AND messageType == fault' > shots/faults.txt 2>/dev/null || true
ls -la shots
