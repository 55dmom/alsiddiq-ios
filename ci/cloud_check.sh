#!/bin/bash
# v3.1 end-to-end check of the iPhone app against the REAL central database, with throwaway passwords and rows.
# Runs only while no admin password exists yet (before the owner's own first-time setup).
# Everything it creates is listed in shots/cloud_ids.txt and removed by the maintainer right after the run.
U="$1"   # simulator udid
BID=com.alsiddiq.app
t() { local s=$1; shift; perl -e 'alarm shift; exec @ARGV' "$s" "$@"; }
SU="$SUPABASE_URL"; K="$SUPABASE_ANON_KEY"
rnd() { python3 -c 'import secrets;print(secrets.token_hex(6))'; }
AP=A$(rnd); VP=V$(rnd); TP=T$(rnd); TP2=N$(rnd)
for p in "$AP" "$VP" "$TP" "$TP2"; do echo "::add-mask::$p"; done
mkdir -p shots
LOG=shots/cloud_selftest.txt
: > $LOG
fn() { curl -s -X POST "$SU/functions/v1/access" -H "apikey: $K" -H "Authorization: Bearer ${2:-$K}" -H "Content-Type: application/json" -d "$1"; echo; }
code() { curl -s -o /dev/null -w "%{http_code}" -X POST "$SU/functions/v1/access" -H "apikey: $K" -H "Authorization: Bearer $K" -H "Content-Type: application/json" -d "$1"; }
rest() { curl -s -X POST "$SU/rest/v1/$1" -H "apikey: $K" -H "Authorization: Bearer $2" -H "Content-Type: application/json" -H "Prefer: return=minimal" -d "$3" -w " HTTP %{http_code}\n"; }
get() { curl -s "$SU/rest/v1/$1" -H "apikey: $K" -H "Authorization: Bearer $2"; echo; }
jget() { python3 -c "import sys,json;d=json.load(sys.stdin);print($1)"; }
uid() { python3 -c 'import uuid;print(uuid.uuid4())'; }
shot() { sleep 1; t 30 xcrun simctl io "$U" screenshot "shots/$1.png" > /dev/null 2>&1; echo "shot $1"; }
launch() { t 20 xcrun simctl terminate "$U" $BID 2>/dev/null || true; t 60 xcrun simctl launch "$U" $BID -AppleLanguages "(ar)" -AppleLocale ar_SA -forceDemo NO "$@" > /dev/null; }
DATA() { t 30 xcrun simctl get_app_container "$U" $BID data; }

ST=$(fn '{"action":"status"}'); echo "status: $ST" | tee -a $LOG
case "$ST" in *'"needs_setup":true'*) ;; *) echo "An admin password already exists (owner set up) - skipping the live check." | tee -a $LOG; exit 0;; esac
CNAME=$(echo "$ST" | jget 'd["center_name"]')

t 120 xcrun simctl boot "$U" || true
t 600 xcrun simctl bootstatus "$U" -b || true
t 30 xcrun simctl status_bar "$U" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 || true
APP=$(find dd/Build/Products -name "AlSiddiq.app" -path "*iphonesimulator*" | head -1)
t 180 xcrun simctl install "$U" "$APP"
t 30 xcrun simctl privacy "$U" grant photos $BID || true

# 1) Fresh install on the real DB -> the first-time setup screen (centre name pre-filled + 3 passwords)
launch -autoLogin none; sleep 14; shot 20_cloud_setup

# 2) setup (the same server call the setup screen makes), with the centre's own name unchanged
echo "== setup" | tee -a $LOG
SJ=$(fn "{\"action\":\"setup\",\"center_name\":\"$CNAME\",\"admin_password\":\"$AP\",\"viewer_password\":\"$VP\",\"teachers_password\":\"$TP\"}")
AT=$(echo "$SJ" | jget 'd["session"]["access_token"]'); echo "::add-mask::$AT"
echo "setup role: $(echo "$SJ" | jget 'd["profile"]["access_kind"]')" | tee -a $LOG
echo "setup again: $(code "{\"action\":\"setup\",\"admin_password\":\"$TP2\",\"viewer_password\":\"$TP2\"}")" | tee -a $LOG
CID=$(get "centers?select=id" "$AT" | jget 'd[0]["id"]')
C1=$(uid); C2=$(uid); S1=$(uid); S2=$(uid)
rest circles "$AT" "[{\"id\":\"$C1\",\"center_id\":\"$CID\",\"name\":\"TEST حلقة أ\"},{\"id\":\"$C2\",\"center_id\":\"$CID\",\"name\":\"TEST حلقة ب\"}]" | tee -a $LOG
rest students "$AT" "[{\"id\":\"$S1\",\"center_id\":\"$CID\",\"full_name\":\"TEST طالب أ\",\"circle_id\":\"$C1\"},{\"id\":\"$S2\",\"center_id\":\"$CID\",\"full_name\":\"TEST طالب ب\",\"circle_id\":\"$C2\"}]" | tee -a $LOG
echo "C1=$C1 C2=$C2 S1=$S1 S2=$S2 CID=$CID" > shots/cloud_ids.txt

# 3) The passwords TYPED into the real screens (XCUITest): password screen, viewer, Settings, teachers box, admin box
t 20 xcrun simctl terminate "$U" $BID 2>/dev/null || true
mkdir -p "$PWD/shots"
TEST_RUNNER_VP="$VP" TEST_RUNNER_AP="$AP" TEST_RUNNER_TP="$TP" TEST_RUNNER_SHOTS_DIR="$PWD/shots" \
  t 900 xcodebuild test-without-building -project AlSiddiq.xcodeproj -scheme AlSiddiq -destination "id=$U" -derivedDataPath dd \
  -only-testing:AlSiddiqUITests CODE_SIGNING_ALLOWED=NO > shots/uitest.log 2>&1
echo "uitest exit: $?" | tee -a $LOG
grep -E "ALSIDDIQ_UITEST|error|Test Case|passed|failed" shots/uitest.log | tail -40 | tee -a $LOG

# 4) Self-tests (app paths + raw writes probed on the server), one per password
run_self() { # who pass name
  D=$(DATA); rm -f "$D/Documents/selftest.txt"
  launch -autoLogin "$1" -ciPass "$2" -ciViewerPass "$VP" -selfTest YES -tryStudents "$S1:$C1,$S2:$C2"
  for i in $(seq 1 45); do sleep 2; grep -q "^done" "$D/Documents/selftest.txt" 2>/dev/null && break; done
  echo "== selftest $1" | tee -a $LOG; cat "$D/Documents/selftest.txt" 2>/dev/null | tee -a $LOG
  shot "$3"
}
run_self viewer "$VP" 31_cloud_selftest_viewer
run_self teacher "$TP" 32_cloud_selftest_teachers
launch -autoLogin teacher -ciPass "$TP" -ciViewerPass "$VP" -startRoute "student/$S1"; sleep 12; shot 33_cloud_student_photo
launch -autoLogin teacher -ciPass "$TP" -ciViewerPass "$VP" -startRoute "circle_report/$C1"; sleep 12; shot 34_cloud_today_report
run_self admin "$AP" 35_cloud_selftest_admin
launch -autoLogin viewer -ciPass "$VP" -startRoute "students"; sleep 12; shot 36_cloud_viewer_students_photos

# 5) Admin changes the teachers' password -> the old one stops working, the new one works
TPT=$(fn "{\"action\":\"login\",\"kind\":\"teacher\",\"password\":\"$TP\"}" | jget 'd["session"]["refresh_token"]')
echo "::add-mask::$TPT"
echo "set teachers password: $(fn "{\"action\":\"set_password\",\"target\":\"teachers\",\"password\":\"$TP2\"}" "$AT")" | tee -a $LOG
echo "old teachers password: $(code "{\"action\":\"login\",\"kind\":\"teacher\",\"password\":\"$TP\"}")" | tee -a $LOG
echo "new teachers password: $(code "{\"action\":\"login\",\"kind\":\"teacher\",\"password\":\"$TP2\"}")" | tee -a $LOG
echo "old refresh token: $(curl -s -o /dev/null -w "%{http_code}" -X POST "$SU/auth/v1/token?grant_type=refresh_token" -H "apikey: $K" -H "Content-Type: application/json" -d "{\"refresh_token\":\"$TPT\"}")" | tee -a $LOG
echo "viewer password in the admin box: $(code "{\"action\":\"login\",\"kind\":\"admin\",\"password\":\"$VP\"}")" | tee -a $LOG
# the app with the OLD teachers password
D=$(DATA); rm -f "$D/Documents/selftest.txt"
launch -autoLogin teacher -ciPass "$TP" -ciViewerPass "$VP" -selfTest YES -tryStudents "$S1:$C1"
for i in $(seq 1 30); do sleep 2; grep -q "^done" "$D/Documents/selftest.txt" 2>/dev/null && break; done
echo "== app with the old teachers password" | tee -a $LOG; cat "$D/Documents/selftest.txt" 2>/dev/null | tee -a $LOG

# 6) What the server holds now (read as the admin)
echo "server recitations:" | tee -a $LOG; get "recitations?select=student_id,notes,teacher_id,by_name" "$AT" | tee -a $LOG
echo "server attendance:" | tee -a $LOG; get "attendance?select=student_id,day,status,recorded_by,by_name" "$AT" | tee -a $LOG
echo "server students:" | tee -a $LOG; get "students?select=id,full_name,notes,circle_id,photo_path" "$AT" | tee -a $LOG
echo "server teacher_names:" | tee -a $LOG; get "teacher_names?select=id,name" "$AT" | tee -a $LOG
echo "server announcements:" | tee -a $LOG; get "announcements?select=id,title,by_name,created_by" "$AT" | tee -a $LOG
cat shots/cloud_ids.txt | tee -a $LOG
xcrun simctl spawn "$U" log show --last 15m --predicate 'process == "AlSiddiq" AND (messageType == fault OR eventMessage CONTAINS "ALSIDDIQ")' > shots/app_log.txt 2>/dev/null || true
ls -la shots
