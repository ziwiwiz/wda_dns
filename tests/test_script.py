"""Regression tests run against temporary files; never touch system DNS."""
import pathlib
import subprocess
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / 'wda_dns.sh'
DOMAINS = SCRIPT.with_name('domains.conf')

class ScriptTests(unittest.TestCase):
    def run_bash(self, body, setup=''):
        with tempfile.TemporaryDirectory() as directory:
            prelude = f'''source "{SCRIPT}"
ROOT="{directory}"
STATE=$ROOT/state; CONFIG=$ROOT/config; UNIT=$ROOT/unit
RESOLV=$ROOT/resolv; LEGACY=$ROOT/legacy; LEGACY_BACKUP=$ROOT/backup
require_root() {{ :; }}
install_deps() {{ :; }}
systemctl() {{ case "$1" in is-active|is-enabled) [[ -f $ROOT/started ]];; restart|enable) touch "$ROOT/started";; stop|disable) rm -f "$ROOT/started";; *) return 0;; esac; }}
dnsmasq() {{ :; }}
probe() {{ :; }}
lsattr() {{ :; }}
{setup}
'''
            return subprocess.run(['bash', '-c', prelude + body], capture_output=True, text=True)

    def assert_ok(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_addresses_and_domains(self):
        self.assert_ok(self.run_bash('''valid_ip 22.22.22.22
for ip in 999.1.1.1 127.0.0.1 1.2.3 0.0.0.0 '1.2.3.4/evil'; do
 if valid_ip "$ip"; then exit 1; fi
done
printf ' Netflix.com # comment\r\nnetflix.com\n\n' > "$ROOT/list"
normalize_domains "$ROOT/list" > "$ROOT/out"
[[ $(cat "$ROOT/out") == netflix.com ]]
printf 'good.com\nbad/name.com\n' > "$ROOT/list"
if normalize_domains "$ROOT/list"; then exit 1; fi
'''))

    def test_repository_domains_and_forwarding(self):
        self.assert_ok(self.run_bash(f'''normalize_domains "{DOMAINS}" > "$ROOT/domains"
printf '1.1.1.1\n' > "$ROOT/upstream"
generate_config 22.22.22.22 "$ROOT/domains" "$ROOT/upstream" > "$ROOT/out"
grep -q '^server=/netflix.com/22.22.22.22$' "$ROOT/out"
grep -q '^server=1.1.1.1$' "$ROOT/out"
! grep -Eq '^(address=|all-servers|interface=)' "$ROOT/out"
'''))

    def test_reinstall_restore_symlink(self):
        self.assert_ok(self.run_bash('''printf 'nameserver 9.9.9.9\nsearch internal\n' > "$ROOT/target"
ln -s "$ROOT/target" "$RESOLV"
printf 'netflix.com\n' > "$ROOT/list"
unlock 22.22.22.22 "$ROOT/list"
unlock 23.23.23.23 "$ROOT/list"
grep -q '^server=9.9.9.9$' "$CONFIG"
! grep -q '^server=127' "$CONFIG"
restore_dns
[[ -L $RESOLV ]]
[[ $(readlink "$RESOLV") == "$ROOT/target" ]]
grep -q '9.9.9.9' "$RESOLV"
[[ ! -d $STATE && ! -e $CONFIG ]]
'''))

    def test_failed_probe_rolls_back(self):
        # EXIT trap executes in the child; inspect paths from a parent shell.
        self.assert_ok(self.run_bash('''printf 'nameserver 9.9.9.9\n' > "$RESOLV"
printf 'netflix.com\n' > "$ROOT/list"
if (probe() { return 1; }; set -e; unlock 22.22.22.22 "$ROOT/list"); then exit 1; fi
grep -q '9.9.9.9' "$RESOLV"
[[ ! -d $STATE && ! -e $CONFIG && ! -e $UNIT ]]
'''.replace('if (probe() { return 1; }; set -e; unlock 22.22.22.22 "$ROOT/list"); then exit 1; fi', '''set +e
(probe() { return 1; }; set -e; unlock 22.22.22.22 "$ROOT/list")
rc=$?
set -e
[[ $rc != 0 ]]''')))

    def test_legacy_migration(self):
        self.assert_ok(self.run_bash("""printf 'nameserver 127.0.0.1\n' > "$RESOLV"
printf 'nameserver 9.9.9.9\n' > "$LEGACY_BACKUP"
printf 'address=/netflix.com/22.22.22.22\n' > "$LEGACY"
printf 'netflix.com\n' > "$ROOT/list"
unlock 22.22.22.22 "$ROOT/list"
[[ ! -e $LEGACY ]]
grep -q '^server=9.9.9.9$' "$CONFIG"
restore_dns
grep -q '9.9.9.9' "$RESOLV"
"""))

    def test_bad_download_content_never_changes_dns(self):
        self.assert_ok(self.run_bash('''printf 'nameserver 9.9.9.9\n' > "$RESOLV"
printf '<html>404</html>\n' > "$ROOT/list"
set +e
(set -e; unlock 22.22.22.22 "$ROOT/list")
rc=$?
set -e
[[ $rc != 0 ]]
grep -q '9.9.9.9' "$RESOLV"
[[ ! -d $STATE && ! -e $CONFIG ]]
'''))

if __name__ == '__main__':
    unittest.main()
