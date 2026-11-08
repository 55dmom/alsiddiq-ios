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
  t 60 xcrun simctl launch "$U" $BID -AppleLanguages "(ar)" -AppleLocale ar_SA -forceDemo "${FORCE_DEMO:-YES}" -autoLogin "$2" -startRoute "$3" $EXTRA > /dev/null
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
tool() { # name tool
  t 20 xcrun simctl terminate "$U" $BID 2>/dev/null || true
  t 60 xcrun simctl launch "$U" $BID -AppleLanguages "(ar)" -AppleLocale ar_SA -forceDemo YES -autoLogin viewer -startRoute home -openTool "$2" $EXTRA > /dev/null
  sleep 9; t 30 xcrun simctl io "$U" screenshot "shots/$1.png" > /dev/null 2>&1; echo "shot $1"
}
tool 18_tools_menu menu
tool 18a_tool_mushaf mushaf
tool 18b_tool_prayer prayer
tool 19a_tool_adhkar adhkar
tool 19b_tool_duas duas
tool 19c_tool_tasbeeh tasbeeh
tool 19d_tool_asma asma
tool 19e_tool_hifz hifz
tool 19f_tool_khatma khatma
# «الثيمات»: the picker, then three of the five themes
tool 20_themes_picker themes
EXTRA="-appTheme emerald" shot 21_theme_emerald viewer home 8
EXTRA="-appTheme night" shot 22_theme_night_teacher teacher home 8
EXTRA="-appTheme sand" shot 23_theme_sand_admin admin more 8
EXTRA="-appTheme night" tool 23b_theme_night_tools menu
# occasions (simulated dates, Debug build only): the greeting popup once a day, then the home/password cards, picker locked
EXTRA="-debugDate 2027-02-10" shot 24_occasion_ramadan_popup none home 9
EXTRA="-debugDate 2027-02-10" shot 25_occasion_ramadan_password none home 8
EXTRA="-debugDate 2027-02-10" shot 26_occasion_ramadan_home viewer home 8
EXTRA="-debugDate 2027-05-16" shot 27_occasion_eid_adha_popup viewer home 9
EXTRA="-debugDate 2027-05-16" shot 28_occasion_eid_adha_home teacher home 8
EXTRA="-debugDate 2026-09-26" shot 29_occasion_sep26_popup viewer home 9
EXTRA="-debugDate 2026-09-26" shot 30_occasion_sep26_home viewer home 8
EXTRA="-debugDate 2026-09-26 -openTool themes" shot 31_occasion_picker_locked viewer home 10
# «عن المركز» (public; bundled text + photo as on a fresh centre), the admin's edit view, «تواصل مع المطوّر» (his package)
tool 32_about about
t 20 xcrun simctl terminate "$U" $BID 2>/dev/null || true
t 60 xcrun simctl launch "$U" $BID -AppleLanguages "(ar)" -AppleLocale ar_SA -forceDemo YES -autoLogin admin -startRoute more -openTool about > /dev/null
sleep 9; t 30 xcrun simctl io "$U" screenshot "shots/33_about_admin.png" > /dev/null 2>&1; echo "shot 33_about_admin"
tool 34_developer developer
# circle fees (v3.5): the admin's edit field, the read-only line on the circle page
shot 37_admin_circle_edit_fee admin circle_edit/c1
shot 38_viewer_circle_fee viewer circle/c1
# offline: what a teacher sees with 2 entries still on the phone (Debug flag -ciPending, simulated state)
EXTRA="-ciPending 2" shot 35_offline_pending_home teacher home 8
EXTRA="-ciPending 2" shot 36_offline_pending_history teacher history/s1 8
xcrun simctl spawn "$U" log show --last 5m --predicate 'process == "AlSiddiq" AND messageType == fault' > shots/faults.txt 2>/dev/null || true
ls -la shots
