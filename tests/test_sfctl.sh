#!/bin/sh
# Model-less checks of sfctl/sfctl, the same file in every child: the model,
# server and port come from the checkout's only sfctl/sf-*.conf, and two
# fixture configs cover a model with and without variants. HOME points at a
# scratch directory, so nothing is installed; launchctl and lsof are never
# called, except through stubs in that directory; no build runs.
set -u

root=$(cd "$(dirname "$0")/.." && pwd -P)
set -- "$root"/sfctl/sf-*.conf
[ $# -eq 1 ] && [ -e "$1" ] || { echo "sfctl: expected one sfctl/sf-*.conf"; exit 1; }
m=${1##*/sf-}
m=${m%.conf}
SF_VARIANTS=
. "$1"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

check() {
    # $1 name, rest: command that must succeed
    name=$1
    shift
    if "$@"; then
        echo "sfctl: $name: ok"
    else
        echo "sfctl: $name: FAILED"
        fail=1
    fi
}

sfctl() { HOME="$tmp" "$root/sfctl/sfctl" "$@"; }

plist=$(sfctl plist "$m")
plist_lints() { printf '%s\n' "$plist" | plutil -lint -s - ; }
plist_has() { printf '%s\n' "$plist" | grep -qF "$1"; }

check "plist is a valid property list" plist_lints
check "plist runs serve's server" plist_has "<string>$tmp/.sf/$m/serve/$SF_SERVER</string>"
check "plist port $SF_PORT" plist_has "<string>$SF_PORT</string>"
check "plist KV in the model home" plist_has "<string>$tmp/.sf/$m/kv"
plist_false() { printf '%s\n' "$plist" | grep -A1 -F "<key>$1</key>" | grep -qF '<false/>'; }
check "plist never starts on its own" plist_false RunAtLoad
check "plist never restarts on exit" plist_false KeepAlive
check "no placeholder left" sh -c '! printf "%s\n" "$1" | grep -q "@HOME@\|@VARIANT@"' sh "$plist"

usage_error() { sfctl "$@" >/dev/null 2>&1; [ $? -eq 2 ]; }
check "stop without a model is a usage error" usage_error stop
check "start without a model is a usage error" usage_error start
check "unknown command is a usage error" usage_error bogus
not_installed() { sfctl start no-such-model 2>&1 | grep -q "no-such-model is not installed"; }
check "unknown model is named" not_installed

# The checkout's own variants, when its config lists any.
kvs=
for v in $SF_VARIANTS; do
    eval "spec=\$SF_MODEL_$v"
    plist=$(sfctl plist "$m-$v")
    check "$m-$v plist is a valid property list" plist_lints
    check "$m-$v plist passes -m ${spec#*:}" plist_has "<string>-m</string>
    <string>${spec#*:}</string>"
    check "$m-$v no placeholder left" sh -c '! printf "%s\n" "$1" | grep -q "@HOME@\|@VARIANT@"' sh "$plist"
    kvs="$kvs$(printf '%s\n' "$plist" | grep -A1 -F '<string>--kv-disk-dir</string>' | tail -n 1)
"
done
if [ -n "$SF_VARIANTS" ]; then
    distinct_kv() { [ -z "$(printf '%s' "$kvs" | sort | uniq -d)" ]; }
    check "$m variants keep separate KV dirs" distinct_kv
    names_variants() { sfctl start "$m" 2>&1 | grep -qF "$m-${SF_VARIANTS%% *}"; }
    check "start $m is a usage error" usage_error start "$m"
    check "start $m names the variants" names_variants
fi

nothing_installed() { [ "$(sfctl status)" = "no sfctl service installed" ]; }
check "status with nothing installed" nothing_installed
check "plist writes nothing" sh -c '[ ! -e "$1/Library" ] && [ ! -e "$1/.sf" ]' sh "$tmp"
generic() { ! grep -rn /Users/ "$root/sfctl" >/dev/null; }
check "no user path under sfctl/" generic

# Fixtures: t1-flash has no variants, t2-flash has q4 and q2. Their serve
# dirs hold only the config; launchctl and lsof are stubs on PATH.
H=$tmp/fx
mkdir -p "$H/.sf/t1-flash/serve/sfctl" "$H/.sf/t2-flash/serve/sfctl" "$tmp/bin"
cat >"$H/.sf/t1-flash/serve/sfctl/sf-t1-flash.conf" <<'EOF'
SF_PORT=8999
SF_SERVER=sf-t1-server
SF_COMPONENTS="m:t1.gguf"
SF_ARGS='--ctx 4096 --kv-disk-dir @HOME@/kv --kv-disk-space-mb 1024'
EOF
cat >"$H/.sf/t2-flash/serve/sfctl/sf-t2-flash.conf" <<'EOF'
SF_PORT=8998
SF_SERVER=sf-t2-server
SF_COMPONENTS="vision:gguf/v.gguf"
SF_VARIANTS="q4 q2"
SF_MODEL_q4=q4:gguf/T-Q4.gguf
SF_MODEL_q2=q2:gguf/T-Q2.gguf
SF_ARGS='--ctx 4096 --kv-disk-dir @HOME@/kv-@VARIANT@ --kv-disk-space-mb 1024'
SF_ARGS_q2='--tokens 128 --kv-note @HOME@/n-@VARIANT@'
EOF
cat >"$tmp/bin/launchctl" <<'EOF'
#!/bin/sh
echo "$*" >>"$STUB_DIR/launchctl.log"
[ "$1" = print ] || exit 0
[ -f "$STUB_DIR/state" ] || exit 113
cat "$STUB_DIR/state"
EOF
printf '#!/bin/sh\nexit 1\n' >"$tmp/bin/lsof"
chmod +x "$tmp/bin/launchctl" "$tmp/bin/lsof"
fx() { HOME="$H" STUB_DIR="$tmp" PATH="$tmp/bin:$PATH" "$root/sfctl/sfctl" "$@"; }
fx_has() { fx plist "$1" | grep -qF "$2"; }

# The agent sfctl wrote before variants existed, for the t1-flash config.
golden() {
    cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<!-- Written by sfctl from sfctl/sf-t1-flash.conf: edit that file and run sfctl update t1-flash. -->
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.starforge.sf-t1-flash</string>
  <key>ProgramArguments</key>
  <array>
    <string>$H/.sf/t1-flash/serve/sf-t1-server</string>
    <string>--port</string>
    <string>8999</string>
    <string>--ctx</string>
    <string>4096</string>
    <string>--kv-disk-dir</string>
    <string>$H/.sf/t1-flash/kv</string>
    <string>--kv-disk-space-mb</string>
    <string>1024</string>
  </array>
  <key>WorkingDirectory</key>
  <string>$H/.sf/t1-flash/serve</string>
  <key>RunAtLoad</key>
  <false/>
  <key>KeepAlive</key>
  <false/>
  <key>StandardOutPath</key>
  <string>$H/Library/Logs/sf/t1-flash.out.log</string>
  <key>StandardErrorPath</key>
  <string>$H/Library/Logs/sf/t1-flash.err.log</string>
</dict>
</plist>
EOF
}
same_as_before() { [ "$(fx plist t1-flash)" = "$(golden)" ]; }
check "config without variants: plist unchanged" same_as_before
refused() { out=$(fx "$@" 2>&1); [ $? -eq 1 ] && printf '%s\n' "$out" | grep -qF "$FX_WANT"; }
FX_WANT="t1-flash has no variant q4"
check "variant of a model without variants refused" refused plist t1-flash-q4
FX_WANT="t2-flash has no variant q9; its services: t2-flash-q4 t2-flash-q2"
check "unknown variant refused" refused start t2-flash-q9
FX_WANT="t2-flash is not installed"
check "<model>-<variant> resolves to the model" refused stop t2-flash-q2
fx_usage() { fx "$@" >/dev/null 2>&1; [ $? -eq 2 ]; }
check "start <model> with variants is a usage error" fx_usage start t2-flash
names() { fx start t2-flash 2>&1 | grep -qF "start t2-flash needs a variant: t2-flash-q4 t2-flash-q2"; }
check "start <model> names the variants" names
fx_lints() { fx plist "$1" | plutil -lint -s -; }
for v in q4 q2; do
    check "t2-flash-$v plist passes its model" fx_has "t2-flash-$v" "<string>-m</string>
    <string>gguf/T-Q${v#q}.gguf</string>"
    check "t2-flash-$v plist has its KV dir" fx_has "t2-flash-$v" "<string>$H/.sf/t2-flash/kv-$v</string>"
    check "t2-flash-$v plist is a valid property list" fx_lints "t2-flash-$v"
done
check "plist <model> is the first variant's" fx_has t2-flash "<string>$H/.sf/t2-flash/kv-q4</string>"
variant_args_after() {
    out=$(fx plist t2-flash-q2) &&
        printf '%s\n' "$out" | grep -A1 -F '<string>1024</string>' | grep -qF '<string>--tokens</string>' &&
        printf '%s\n' "$out" | grep -qF "<string>$H/.sf/t2-flash/n-q2</string>"
}
check "SF_ARGS_<variant> follows SF_ARGS, with @HOME@ and @VARIANT@" variant_args_after
no_variant_args() { ! fx plist t2-flash-q4 | grep -qF -- '--tokens'; }
check "SF_ARGS_<variant> reaches only its variant" no_variant_args
bad_variant_args() {
    c="$H/.sf/t2-flash/serve/sfctl/sf-t2-flash.conf"
    cp "$c" "$tmp/t2.conf" && printf "SF_ARGS_q4='--x a<b'\n" >>"$c"
    out=$(fx plist t2-flash-q4 2>&1); rc=$?
    cp "$tmp/t2.conf" "$c"
    [ $rc -eq 1 ] && printf '%s\n' "$out" | grep -qF "SF_ARGS_q4 must not contain <, > or &"
}
check "SF_ARGS_<variant> with a forbidden character refused" bad_variant_args

# start, through the stubs: the fixture is "installed" by its agent file.
mkdir -p "$H/Library/LaunchAgents"
: >"$H/Library/LaunchAgents/com.starforge.sf-t2-flash.plist"
FX_WANT="t2-flash-q2 needs $H/.sf/t2-flash/serve/gguf/T-Q2.gguf, which is missing; link it with: sfctl update t2-flash"
check "start without the variant's model points to update" refused start t2-flash-q2
mkdir -p "$H/.sf/t2-flash/serve/gguf"
: >"$H/.sf/t2-flash/serve/gguf/T-Q2.gguf"
stub_start() {
    fx start t2-flash-q2 >/dev/null &&
        [ "$(cat "$H/.sf/t2-flash/variant")" = q2 ] &&
        grep -qF "$H/.sf/t2-flash/kv-q2" "$H/Library/LaunchAgents/com.starforge.sf-t2-flash.plist" &&
        grep -q '^kickstart ' "$tmp/launchctl.log"
}
check "start <model>-<variant> writes its agent and records it" stub_start
echo '	pid = 4242' >"$tmp/state"
FX_WANT="t2-flash is running t2-flash-q2 (pid 4242); to switch run: sfctl restart t2-flash-q4"
check "start of another variant while running refused" refused start t2-flash-q4
running_q2() {
    git -C "$H/.sf/t2-flash/serve" -c init.defaultBranch=main init -q &&
        git -C "$H/.sf/t2-flash/serve" -c user.name=t -c user.email=t@t -c commit.gpgsign=false \
            commit -q --allow-empty -m t &&
        fx status t2-flash-q4 | grep -q '^t2-flash running q2 pid 4242 port 8998, serve [0-9a-f]* = main$'
}
check "status shows the running variant" running_q2
rm -f "$tmp/state"
stopped_q2() { fx status | grep -q '^t2-flash stopped (last q2) port 8998,'; }
check "status shows the last variant when stopped" stopped_q2

# update, through the stubs and a stub make: serve is a git repository whose
# detached HEAD is one commit behind main, and main's sfctl logs its own runs.
U=$tmp/up
s=$U/.sf/t3-flash/serve
mkdir -p "$s/sfctl" "$s/gguf" "$U/Library/LaunchAgents"
cat >"$s/sfctl/sf-t3-flash.conf" <<'EOF'
SF_PORT=8997
SF_SERVER=sf-t3-server
SF_VARIANTS="q4 q2"
SF_MODEL_q4=q4:gguf/q4.gguf
SF_MODEL_q2=q2:gguf/q2.gguf
SF_ARGS='--kv-disk-dir @HOME@/kv-@VARIANT@'
EOF
printf 'gguf/\n' >"$s/.gitignore"
printf '#!/bin/sh\necho "$1" >>"$STUB_DIR/download.log"\n: >"gguf/$1.gguf"\n' >"$s/download.sh"
printf '#!/bin/sh\necho "$*" >>"$STUB_DIR/make.log"\n' >"$tmp/bin/make"
chmod +x "$s/download.sh" "$tmp/bin/make"
cp "$root/sfctl/sfctl" "$s/sfctl/sfctl"
: >"$s/gguf/q4.gguf"
: >"$U/Library/LaunchAgents/com.starforge.sf-t3-flash.plist"
g() { git -C "$s" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }
update_reexecs() {
    g -c init.defaultBranch=main init -q && g add -A && g commit -qm old &&
        awk '{ print } /^set -eu$/ { print "echo \"$*\" >>\"$STUB_DIR/exec.log\"" }' \
            "$root/sfctl/sfctl" >"$s/sfctl/sfctl" &&
        g commit -qam new && g checkout -q --detach HEAD~1 || return 1
    old=$(g rev-parse --short HEAD)
    new=$(g rev-parse --short main)
    out=$(HOME="$U" STUB_DIR="$tmp" PATH="$tmp/bin:$PATH" "$root/sfctl/sfctl" update t3-flash) &&
        [ "$(cat "$tmp/exec.log" 2>/dev/null)" = "_update-finish t3-flash $old " ] &&
        [ "$(cat "$tmp/download.log")" = q2 ] &&
        [ "$(cat "$tmp/make.log")" = "-C $s sf-t3-server" ] &&
        grep -qF "<string>$U/.sf/t3-flash/kv-q4</string>" "$U/Library/LaunchAgents/com.starforge.sf-t3-flash.plist" &&
        printf '%s\n' "$out" | grep -qx "t3-flash serve $old..$new"
}
check "update hands over to main's script, which links, builds and writes the agent" update_reexecs

[ "$fail" -eq 0 ] && echo "sfctl tests passed"
exit "$fail"
