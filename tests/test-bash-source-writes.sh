#!/usr/bin/env bash
# test-bash-source-writes.sh — #39: a source file written through Bash meets the same
# design, planning and library gates as a Write or Edit of it. bash_write_targets in
# _helpers.sh reads the literal targets; the gates run their per-file check on each.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/setup.sh"

SP="$HOOK_DIR/enforce-superpowers.sh"
PT="$HOOK_DIR/enforce-plan-tracking.sh"
C7="$HOOK_DIR/enforce-context7.sh"
SC="$HOOK_DIR/scalability-check.sh"
CL="$HOOK_DIR/changelog-sync-check.sh"

# Bash hook input in the shape Claude Code sends.
bash_input() {
  jq -nc --arg c "$1" --arg d "$TEST_DIR" \
    '{session_id:"s",cwd:$d,permission_mode:"auto",hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}'
}
bash_rc() { (cd "$TEST_DIR" && bash_input "$2" | bash "$1" >/dev/null 2>&1; echo $?); }
bash_out() { (cd "$TEST_DIR" && bash_input "$2" | bash "$1" 2>&1); }
# The targets bash_write_targets prints for a command, from the project root.
targets() { (cd "$TEST_DIR" && source "$HOOK_DIR/_helpers.sh" && bash_write_targets "$1" "${2:-}"); }

setup_src_project() {
  setup_test_project
  mkdir -p "$TEST_DIR/src" "$TEST_DIR/docs"
  echo "export const a = 1" > "$TEST_DIR/src/x.ts"
  echo "export const d = 1" > "$TEST_DIR/draft.ts"
}

# Each literal form that writes the source file src/x.ts (or src/draft.ts, or another
# source file).
FORMS=(
  '((echo x > src/x.ts) )'
  'echo $((echo x > src/x.ts) )'
  '[[ -n x ]] > src/x.ts'
  "python3 -c \"import os; open(os.path.join('src','x.ts'),'w').write('x')\""
  $'python3 - <<\'EOF\'\nfrom pathlib import Path\nwith Path(\'src/x.ts\').open(\'w\') as f:\n    f.write(\'x\')\nEOF'
  "python3 -c \"from pathlib import Path; p=Path('src/x.ts'); p.open('a').write('x')\""
  "python3 -c \"from pathlib import Path; Path('draft.ts').rename('src/x.ts')\""
  'cp src/x.ts src/y.ts 2>&1'
  $'cat > \'app/blog/[slug]/page.tsx\' <<\'EOF\'\nexport default 1\nEOF'
  "sed -i '' 's/a/b/' 'src/routes/[slug]/+page.svelte'"
  $'cat > \'app/routes/posts.$postId.tsx\' <<\'EOF\'\nexport default 1\nEOF'
  "echo x > 'app/[...all]/page.tsx'"
  "gsed -i 's/a/b/' src/x.ts"
  'gcp draft.ts src/x.ts'
  'echo x > ./src/x.ts'
  'echo x > src/../src/x.ts'
  $'python3 - <<\'EOF\'\nfrom pathlib import Path\np = Path(\'src/x.ts\')\np.write_text(p.read_text().replace(\'a\',\'b\'))\nEOF'
  $'python3 - <<\'EOF\'\npath=\'src/x.ts\'\nwith open(path,\'w\') as f:\n    f.write(\'x\')\nEOF'
  "python3 -c \"import pathlib; p=pathlib.Path('src/x.ts'); p.write_text('x')\""
  "python3 -c \"open(file='src/x.ts', mode='w').write('x')\""
  "python3 -c \"import shutil; shutil.copy('draft.ts','src/x.ts')\""

  'echo x > src/x.ts'
  'echo x >> src/x.ts'
  'echo x >| src/x.ts'
  'echo x &> src/x.ts'
  'echo x 1> src/x.ts'
  'echo x 2>&1 >src/x.ts'
  $'cat > src/x.ts <<\'EOF\'\nexport const b = 2\nEOF'
  $'cat >> src/x.ts <<EOF\nexport const b = 2\nEOF'
  $'cat <<EOF > src/x.ts\nexport const b = 2\nEOF'
  'echo x | tee src/x.ts'
  'echo x | tee -a src/x.ts >/dev/null'
  "sed -i '' 's/a/b/' src/x.ts"
  "sed -i 's/a/b/' src/x.ts"
  "sed -i.bak -e 's/a/b/' src/x.ts"
  "sed -Ei 's/a/b/' src/x.ts"
  "perl -pi -e 's/a/b/' src/x.ts"
  "perl -i.bak -pe 's/a/b/' src/x.ts"
  'cp draft.ts src/x.ts'
  'mv draft.ts src/x.ts'
  'install -m 644 draft.ts src/x.ts'
  'ln -sf ../draft.ts src/x.ts'
  'cp -t src draft.ts'
  'cp draft.ts src/'
  'cp draft.ts src'
  "python3 -c \"open('src/x.ts', 'w').write('x')\""
  "python -c 'open(\"src/x.ts\", \"a\").write(\"x\")'"
  "python3 -c \"from pathlib import Path; Path('src/x.ts').write_text('x')\""
  $'python3 - <<\'EOF\'\nopen("src/x.ts", "w").write("x")\nEOF'
  'dd if=/dev/zero of=src/x.ts count=0'
  'truncate -s 0 src/x.ts'
  'cd src && echo x > x.ts'
)

# Read-only and non-source commands: no gate looks twice at them.
PASSES=(
  'git status'
  'cat src/x.ts'
  'grep -rn foo src/'
  'git add src/x.ts'
  'echo x > notes.md'
  'npm test > /tmp/out.txt'
  'ls src > /dev/null 2>&1'
  'cp README.md docs/'
  'sed -n 1,5p src/x.ts'
  "sed 's/a/b/' src/x.ts > /tmp/x.ts"
  'cat src/x.ts | tee /tmp/copy.ts'
  "python3 -c \"print(open('src/x.ts').read())\""
  'echo x > tests/test_x.py'
  'echo x 2>/dev/null'
  "sed -i '' 's/a/b/' README.md 2>&1"
  'cp src/x.ts /tmp/ 2>&1'
  'echo x | tee /tmp/a.txt 2>&1'
  'echo x | tee /tmp/a.txt >&2'
  "perl -pi -e 's/a/b/' docs/a.md 2>&1"
  $'cd /tmp && cat > ./t.py <<EOF\nprint(1)\nEOF'
  'echo x > ../sibling/x.ts'
  '(( n > 3 )) && echo big'
  'if [[ "$(node -v)" > "v18" ]]; then echo new; fi'
  'while [[ $n > 0 ]]; do n=$((n-1)); done'
  "python3 -c \"s=open('src/x.ts').read(); print(s.replace('foo', 'bar'))\""
  "python3 -c \"s=open('src/x.ts').read(); print(len(s), 'a')\""
  $'python3 - <<\'EOF\'\ns = open(\'src/x.ts\').read()\nprint(s, \'at\')\nEOF'
  "python3 -c \"import json; open('/tmp/o.json','w').write(json.dumps({'type':'application/json'}))\""
  "python3 -c \"import time; open('/tmp/d.txt','w').write(time.strftime('%Y/%m/%d'))\""
  'echo $((8>>1))'
)

# =====================================================================
# 1. bash_write_targets prints each literal target, as the shell would resolve it
# =====================================================================
test_targets_per_form() {
  setup_src_project
  assert_equals "src/x.ts" "$(targets 'echo x > src/x.ts')" "targets: > redirect"
  assert_equals "src/x.ts" "$(targets 'echo x >>src/x.ts')" "targets: >> redirect, no space"
  assert_equals "src/x.ts" "$(targets 'echo x >| src/x.ts')" "targets: >| (one command, not a pipe)"
  assert_equals "src/x.ts" "$(targets 'make &> src/x.ts')" "targets: &>"
  assert_equals "src/x.ts" "$(targets 'make 2> src/x.ts')" "targets: N> (the fd is no operand)"
  assert_equals "" "$(targets 'make 2>&1')" "targets: fd duplication is no file"
  assert_equals "/dev/null" "$(targets 'make > /dev/null 2>&1')" "targets: /dev/null printed as written"
  assert_equals "src/x.ts" "$(targets $'cat > src/x.ts <<EOF\nimport a from \'b\'\nEOF')" "targets: cat > f <<EOF"
  assert_equals "" "$(targets 'cat < src/x.ts')" "targets: input redirect is no write"
  assert_equals $'src/x.ts\nsrc/y.ts' "$(targets 'echo x | tee -a src/x.ts src/y.ts')" "targets: tee -a, every file"
  assert_equals "src/x.ts" "$(targets "sed -i '' 's/a/b/' src/x.ts")" "targets: BSD sed -i ''"
  assert_equals "src/x.ts" "$(targets "sed -i .bak 's/a/b/' src/x.ts")" "targets: BSD sed -i .bak"
  assert_equals "src/x.ts" "$(targets "sed -i 's/a/b/' src/x.ts")" "targets: GNU sed -i"
  assert_equals $'src/x.ts\nsrc/y.ts' "$(targets "sed -i -e 's/a/b/' -e 's/c/d/' src/x.ts src/y.ts")" "targets: sed -i -e -e, two files"
  assert_equals "" "$(targets "sed 's/a/b/' src/x.ts")" "targets: sed without -i writes nothing"
  assert_equals "src/x.ts" "$(targets "perl -pi -e 's/a/b/' src/x.ts")" "targets: perl -pi -e"
  assert_equals "" "$(targets "perl -pe 's/a/b/' src/x.ts")" "targets: perl without -i writes nothing"
  assert_equals "" "$(targets "perl -Mstrict -e 'print 1' src/x.ts")" "targets: an i inside -Mstrict is no -i"
  assert_equals "src/x.ts" "$(targets 'cp draft.ts src/x.ts')" "targets: cp onto a file"
  assert_equals $'/dev/null\nsrc/x.ts' "$(targets 'cp draft.ts src/x.ts 2>/dev/null')" "targets: the fd of 2> is no cp operand"
  assert_equals "src/draft.ts" "$(targets 'cp draft.ts src')" "targets: cp into an existing directory"
  assert_equals "src/draft.ts" "$(targets 'mv draft.ts src/')" "targets: mv into dir/"
  assert_equals $'src/draft.ts\nsrc/x.ts' "$(targets 'cp draft.ts other/x.ts src')" "targets: cp of two sources into a directory"
  assert_equals "src/draft.ts" "$(targets 'cp -t src draft.ts')" "targets: cp -t DIR"
  assert_equals "src/draft.ts" "$(targets 'cp --target-directory=src draft.ts')" "targets: cp --target-directory="
  assert_equals "src/x.ts" "$(targets 'install -m 0644 draft.ts src/x.ts')" "targets: install -m MODE"
  assert_equals "" "$(targets 'install -d src/lib')" "targets: install -d makes directories"
  assert_equals "src/x.ts" "$(targets 'ln -s ../draft.ts src/x.ts')" "targets: ln -s"
  assert_equals "" "$(targets 'cp -r src backup')" "targets: a directory copied whole is not a literal file"
  assert_equals "src/x.ts" "$(targets "python3 -c \"open('src/x.ts','w').write('x')\"")" "targets: python3 -c open(w)"
  assert_equals "src/x.ts" "$(targets "python3 -c \"open('src/x.ts', mode='ab')\"")" "targets: python3 -c open(mode=ab)"
  assert_equals "" "$(targets "python3 -c \"open('src/x.ts').read()\"")" "targets: python3 -c open() to read"
  assert_equals "" "$(targets "python3 -c \"open('src/x.ts', 'r')\"")" "targets: python3 -c open(r)"
  assert_equals "src/x.ts" "$(targets "python3.12 -c \"import pathlib; pathlib.Path('src/x.ts').write_bytes(b'')\"")" "targets: Path().write_bytes"
  assert_equals "src/x.ts" "$(targets $'python3 <<EOF\nopen("src/x.ts", "w").write("x")\nEOF')" "targets: python3 reading a here-document"
  assert_equals "notes.md" "$(targets $'cat > notes.md <<EOF\nopen("src/x.ts", "w")\nEOF')" "targets: open() in a body not fed to python is data"
  assert_equals "src/x.ts" "$(targets 'dd if=/dev/zero of=src/x.ts count=0')" "targets: dd of="
  assert_equals "src/x.ts" "$(targets 'truncate -s 0 src/x.ts')" "targets: truncate -s N"
  assert_equals "src/x.ts" "$(targets 'cd src && echo x > x.ts')" "targets: a literal cd moves a relative target"
  assert_equals "$TEST_DIR/src/x.ts" "$(targets 'echo x > src/x.ts' "$TEST_DIR")" "targets: joined to the given directory"
  assert_equals "/tmp/x.ts" "$(targets 'echo x > /tmp/x.ts' "$TEST_DIR")" "targets: an absolute target stays as written"
  teardown_test_project
}

# A target the text does not fix is not printed: the R-23 residual.
test_targets_not_literal() {
  setup_src_project
  assert_equals "" "$(targets 'f=src/x.ts; echo x > "$f"')" "R-23: a variable target"
  assert_equals "" "$(targets 'echo x > ${F}')" "R-23: a braced variable target"
  assert_equals "" "$(targets 'echo x > src/$(echo x).ts')" "R-23: a substitution in the target"
  assert_equals "" "$(targets 'echo x > "src/$(echo x).ts"')" "R-23: a quoted substitution in the target"
  assert_equals "" "$(targets 'echo x | tee `echo src/x.ts`')" "R-23: a backtick target"
  # A glob or brace is checked as written: it fails closed (#39 review, finding 2).
  assert_equals "src/*.ts" "$(targets 'echo x > src/*.ts')" "a glob target is checked as written"
  assert_equals "src/{a,b}.ts" "$(targets 'echo x > src/{a,b}.ts')" "a brace target is checked as written"
  assert_equals "" "$(targets 'echo x > ~/x.ts')" "R-23: a tilde target"
  assert_equals "" "$(targets 'cd "$D" && echo x > x.ts')" "R-23: a relative target after a cd to a variable"
  assert_equals "" "$(targets 'cp draft.ts "$DEST"')" "R-23: a copy onto a variable"
  teardown_test_project
}

# The review of #39: fd duplication, quoted literals, g-prefixed tools, dot segments
# and the python pattern.
test_targets_review() {
  setup_src_project
  assert_equals "src/x.ts" "$(targets 'cp draft.ts src/x.ts 2>&1')" "finding 1: 2>&1 adds no operand"
  assert_equals "README.md" "$(targets "sed -i '' 's/a/b/' README.md 2>&1")" "finding 1: sed -i with 2>&1"
  assert_equals "/tmp/a.txt" "$(targets 'echo x | tee /tmp/a.txt >&2')" "finding 1: >&2 adds no operand"
  assert_equals "src/x.ts" "$(targets 'cp draft.ts src/x.ts 2>&1 1>&-')" "finding 1: a closed fd adds no operand"
  assert_equals "app/routes/posts.\$postId.tsx" "$(targets "echo x > 'app/routes/posts.\$postId.tsx'")" "finding 2: a single-quoted \$ is literal"
  assert_equals "" "$(targets 'echo x > "app/routes/posts.$postId.tsx"')" "finding 2: a double-quoted \$ expands (R-23)"
  assert_equals "src/routes/[slug]/+page.svelte" "$(targets "sed -i '' 's/a/b/' 'src/routes/[slug]/+page.svelte'")" "finding 2: brackets in a quoted path"
  assert_equals "src/x.ts" "$(targets "gsed -i 's/a/b/' src/x.ts")" "finding 4: gsed"
  assert_equals "src/x.ts" "$(targets 'gtee src/x.ts')" "finding 4: gtee"
  assert_equals "$TEST_DIR/src/x.ts" "$(targets 'echo x > ./src/../src/x.ts' "$TEST_DIR")" "finding 9: . and .. segments resolved"
  assert_equals "/tmp/t.py" "$(targets $'cd /tmp && cat > ./t.py <<EOF\nx\nEOF' "$TEST_DIR")" "finding 9: ./ after a cd"
  assert_equals "${TEST_DIR%/*}/sibling/x.ts" "$(targets 'echo x > ../sibling/x.ts' "$TEST_DIR")" "finding 9: ../ leaves the project"
  assert_equals $'src/a.ts\n/tmp/out' "$(targets "python3 -c \"d=open('src/a.ts').read(); open('/tmp/out','w').write(d)\"")" "python: every path literal counts once the code writes (over-report)"
  assert_equals "src/x.ts" "$(targets "python3 -c \"p='src/x.ts'; open(p, 'w')\"")" "python: a path in a variable counts once the code writes"
  assert_equals "src/x.ts" "$(targets "python3 -c \"import os; os.replace('/tmp/new.ts', 'src/x.ts')\"" | grep -v '^/tmp')" "python: os.replace"
  assert_equals "x.py" "$(targets "python3 -c \"open('x.py', 'a')\"")" "python: a bare name with a source extension"
  assert_equals "src/x.ts" "$(targets "python3 -c \"m=input(); open('src/x.ts', mode=m)\"")" "python: a non-literal mode= counts as a write"
  assert_equals "" "$(targets "python3 -c \"open('notes', 'w').write('example.com')\"")" "python: no slash and no source extension is no path"
  assert_equals "" "$(targets "python3 -c \"print(open('src/x.ts').read())\"")" "python: reading only writes nothing"
  teardown_test_project
}

# After the 4.4.9 here-string and arithmetic fix: a here-string is stdin (content for
# context7, code for python), a never-closed here-document still writes its target,
# and a > or < inside arithmetic or [[ ]] is a comparison or shift, not a redirection.
test_targets_herestring_arithmetic() {
  setup_src_project
  assert_equals "src/x.ts" "$(targets 'cat <<< "x" > src/x.ts')" "here-string: the redirection after it is read"
  assert_equals "" "$(targets "bash <<< 'echo x > src/x.ts'")" "here-string: code handed to a shell is R-23"
  assert_equals "src/x.ts" "$(targets "python3 <<< \"open('src/x.ts','w').write('x')\"")" "here-string: python code from a here-string"
  assert_equals "import axios from 'axios'" "$(cd "$TEST_DIR" && source "$HOOK_DIR/_helpers.sh" && bash_heredoc_text "cat <<< \"import axios from 'axios'\" > src/x.ts")" "here-string: its word is content"
  assert_equals "src/x.ts" "$(targets $'cat > src/x.ts <<EOF\nexport const a = 1')" "a never-closed here-document still writes its target"
  assert_equals "src/x.ts" "$(targets 'echo $((1<<2)) > src/x.ts')" "arithmetic <<: the redirection after it is read"
  assert_equals "" "$(targets 'echo $((8>>1))')" "arithmetic >> is a shift"
  assert_equals "" "$(targets '(( x > 2 )) && echo y')" "(( > )) is a comparison"
  assert_equals "" "$(targets 'if (( n >= 3 )); then echo y; fi')" "(( >= )) is a comparison"
  assert_equals "" "$(targets 'echo $[8>>1]')" "\$[ >> ] is a shift"
  assert_equals "" "$(targets '[[ a > b ]] && echo y')" "[[ > ]] is a string comparison"
  assert_equals "src/x.ts" "$(targets '(( n > 1 )) && echo x > src/x.ts')" "a redirection after arithmetic is read"
  assert_equals "a here-document or here-string" "$(source "$HOOK_DIR/_helpers.sh" && command_read_problem 'cat <<< x')" "the read-only reason names a here-string"
  teardown_test_project
}

# Round 2 of the review: real writes inside (( )) and after [[ ]], [[ after a keyword,
# read-only python, slash strings that are not paths, and Path.open / rename.
test_targets_review2() {
  setup_src_project
  assert_equals "src/x.ts" "$(targets '((echo x > src/x.ts) )')" "item 1: a nested subshell in (( )) writes"
  assert_equals "src/x.ts" "$(targets 'echo $((echo x > src/x.ts) )')" "item 1: a nested subshell in \$(( )) writes"
  assert_equals "src/x.ts" "$(targets '[[ -n x ]] > src/x.ts')" "item 1: a redirect after ]] writes"
  assert_equals "src/x.ts" "$(targets '[[ -n x ]]>src/x.ts')" "item 1: a redirect glued to ]] writes"
  assert_equals "" "$(targets 'if [[ "$(node -v)" > "v18" ]]; then echo new; fi')" "item 2: [[ after if"
  assert_equals "" "$(targets 'while [[ $n > 0 ]]; do n=$((n-1)); done')" "item 2: [[ after while"
  assert_equals "" "$(targets "python3 -c \"s=open('src/x.ts').read(); print(len(s), 'a')\"")" "item 3: a mode-like literal outside open() is no mode"
  assert_equals "" "$(targets "python3 -c \"s=open('src/x.ts').read(); f(mode=m)\"")" "item 3: a mode= outside open() is no mode"
  assert_equals "x.ts" "$(targets "python3 -c \"import os; open(os.path.join('src','x.ts'),'w')\"")" "item 3: a nested call inside open() keeps its mode"
  assert_equals "/tmp/o.json" "$(targets "python3 -c \"import json; open('/tmp/o.json','w').write(json.dumps({'type':'application/json'}))\"")" "item 4: a MIME type is no path"
  assert_equals "/tmp/d.txt" "$(targets "python3 -c \"import time; open('/tmp/d.txt','w').write(time.strftime('%Y/%m/%d'))\"")" "item 4: a date format is no path"
  assert_equals "src/x.ts" "$(targets "python3 -c \"from pathlib import Path; Path('src/x.ts').open('w')\"")" "item 5: Path.open(w)"
  assert_equals $'draft.ts\nsrc/x.ts' "$(targets "python3 -c \"from pathlib import Path; Path('draft.ts').rename('src/x.ts')\"")" "item 5: Path.rename"
  assert_equals "" "$(targets "python3 -c \"print(open('src/x.ts').read().replace('a', 'b'))\"")" "item 5: str.replace is no write"
  teardown_test_project
}

# Item 6: a command naming many source files re-runs each blocking gate once per
# extension, not once per file, and every gate once per distinct file.
test_many_targets_fast() {
  local cmd="tee" i ms g
  setup_src_project
  for i in $(seq 1 100); do cmd="$cmd src/f$i.ts"; done
  cmd="echo x | $cmd src/f1.ts"
  touch "/tmp/.claude_superpowers_${TEST_HASH}" "/tmp/.claude_has_plan_${TEST_HASH}" "/tmp/.claude_plan_active_${TEST_HASH}"
  for g in "$SP" "$PT" "$C7"; do
    ms=$(cd "$TEST_DIR" && bash_input "$cmd" | perl -MTime::HiRes=time -e '$t = time; system("bash", $ARGV[0]); printf "%d %d", (time - $t) * 1000, $? >> 8' "$g")
    assert_equals "0" "${ms#* }" "$(basename "$g"): 100 literal targets pass with the zone satisfied"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "${ms% *}" -lt 2000 ]; then TESTS_PASSED=$((TESTS_PASSED + 1)); else TESTS_FAILED=$((TESTS_FAILED + 1)); FAILURES="${FAILURES}  FAIL: $(basename "$g"): 100 literal targets took ${ms% *} ms (limit 2000)\n"; fi
    echo "  $(basename "$g"): 100 targets in ${ms% *} ms"
  done
  rm -f "/tmp/.claude_superpowers_${TEST_HASH}"
  assert_exit_code "2" "$(bash_rc "$SP" "$cmd")" "100 literal targets still refuse without the marker"
  # A per-file gate (scalability-check) re-runs once per distinct file: 50 copies of
  # one path are one re-run.
  jq '.discovery.futurePlatforms = "web"' "$TEST_DIR/.claude/manifest.json" > "$TEST_DIR/m.tmp" && mv "$TEST_DIR/m.tmp" "$TEST_DIR/.claude/manifest.json"
  cmd="tee"; for i in $(seq 1 50); do cmd="$cmd src/UserService.ts"; done
  ms=$(cd "$TEST_DIR" && bash_input "echo x | $cmd" | perl -MTime::HiRes=time -e '$t = time; system("bash $ARGV[0] >/dev/null"); printf "%d", (time - $t) * 1000' "$SC")
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "$ms" -lt 1000 ]; then TESTS_PASSED=$((TESTS_PASSED + 1)); else TESTS_FAILED=$((TESTS_FAILED + 1)); FAILURES="${FAILURES}  FAIL: scalability-check: 50 copies of one target took ${ms} ms (limit 1000)\n"; fi
  echo "  scalability-check.sh: 50 copies of one target in ${ms} ms"
  teardown_test_project
}

# =====================================================================
# 2. Every literal form is refused with the zone unsatisfied, allowed with it satisfied
# =====================================================================
test_forms_superpowers() {
  local f rc
  for f in "${FORMS[@]}"; do
    setup_src_project
    rc=$(bash_rc "$SP" "$f")
    assert_exit_code "2" "$rc" "superpowers refuses without the marker: $f"
    touch "/tmp/.claude_superpowers_${TEST_HASH}"
    rc=$(bash_rc "$SP" "$f")
    assert_exit_code "0" "$rc" "superpowers allows with the marker: $f"
    teardown_test_project
  done
}

test_forms_plan_tracking() {
  local f rc
  for f in "${FORMS[@]}"; do
    setup_src_project
    touch "/tmp/.claude_has_plan_${TEST_HASH}"
    rc=$(bash_rc "$PT" "$f")
    assert_exit_code "2" "$rc" "plan-tracking refuses without an active task: $f"
    touch "/tmp/.claude_plan_active_${TEST_HASH}"
    rc=$(bash_rc "$PT" "$f")
    assert_exit_code "0" "$rc" "plan-tracking allows with an active task: $f"
    teardown_test_project
  done
}

# The message says the write was through Bash, names the file, and keeps the remedy.
test_block_messages_name_bash() {
  local out
  setup_src_project
  echo '{"enabledPlugins":{"superpowers@claude-plugins-official":true}}' > "$TEST_DIR/.claude/settings.local.json"
  out=$(bash_out "$SP" 'echo x > src/x.ts')
  assert_contains "$out" "This Bash command writes $TEST_DIR/src/x.ts" "superpowers: names the Bash write and its file"
  assert_contains "$out" "same check as a Write or Edit" "superpowers: says Bash is held to the same check"
  assert_contains "$out" "BLOCKED" "superpowers: the gate's own block follows"
  assert_contains "$out" "Invoke the skill now" "superpowers: same remedy as for Write/Edit"
  touch "/tmp/.claude_has_plan_${TEST_HASH}"
  out=$(bash_out "$PT" "sed -i '' 's/a/b/' src/x.ts")
  assert_contains "$out" "This Bash command writes $TEST_DIR/src/x.ts" "plan-tracking: names the Bash write and its file"
  assert_contains "$out" "mark-plan-active.sh" "plan-tracking: same remedy as for Write/Edit"
  teardown_test_project
}

# =====================================================================
# 3. Read-only, non-source, temp and non-literal targets pass every gate silently
# =====================================================================
test_passes_untouched() {
  local f g out rc
  setup_src_project
  touch "/tmp/.claude_has_plan_${TEST_HASH}"
  jq '.discovery.futurePlatforms = "web" | .projectConfig._base.changelogFile = "CHANGELOG.md" | .projectConfig._base.syncCommand = "bash sync.sh"' \
    "$TEST_DIR/.claude/manifest.json" > "$TEST_DIR/m.tmp" && mv "$TEST_DIR/m.tmp" "$TEST_DIR/.claude/manifest.json"
  local tmpd; tmpd=$(mktemp -d)
  for f in "${PASSES[@]}" 'f=src/x.ts; echo x > "$f"' "echo x > $tmpd/x.ts" "cat > $tmpd/UserService.ts <<EOF
import axios from 'axios'
EOF"; do
    for g in "$SP" "$PT" "$C7" "$SC" "$CL"; do
      out=$(bash_out "$g" "$f"); rc=$?
      assert_equals "0|" "$rc|$out" "$(basename "$g") passes silently: $f"
    done
  done
  rm -rf "$tmpd"
  teardown_test_project
}

# Log and output files are data, not source: teeing a build log or saving test output
# in the project needs no Superpowers skill. Extensionless names stay source.
test_logs_are_not_source() {
  local f
  setup_src_project
  # test.out also passes as a test file name; build.out is the case only the data list covers.
  for f in 'make 2>&1 | tee build.log' 'npm test > test.out' 'npm run build > build.out' 'echo x >> logs/run.log'; do
    assert_exit_code "0" "$(bash_rc "$SP" "$f")" "superpowers passes a log or output file: $f"
  done
  assert_exit_code "0" "$(run_hook_exit_code "$SP" '{"tool_name":"Write","tool_input":{"file_path":"x.log","content":"x"}}')" "superpowers passes a Write of x.log"
  assert_exit_code "0" "$(run_hook_exit_code "$SP" '{"tool_name":"Write","tool_input":{"file_path":"run.out","content":"x"}}')" "superpowers passes a Write of run.out"
  assert_exit_code "2" "$(bash_rc "$SP" 'echo x > src/x.ts')" "superpowers still refuses > src/x.ts"
  assert_exit_code "2" "$(bash_rc "$SP" 'echo x | tee src/x.ts')" "superpowers still refuses tee src/x.ts"
  assert_exit_code "2" "$(bash_rc "$SP" 'echo x > Makefile')" "an extensionless name stays source"
  assert_exit_code "2" "$(run_hook_exit_code "$SP" '{"tool_name":"Write","tool_input":{"file_path":"Dockerfile","content":"x"}}')" "a Write of Dockerfile stays source"
  teardown_test_project
}

# =====================================================================
# 4. enforce-context7 reads a here-document body as the content written
# =====================================================================
test_context7_heredoc() {
  local cmd
  setup_src_project
  cmd=$'cat > src/x.ts <<\'EOF\'\nimport axios from \'axios\'\nEOF'
  assert_exit_code "2" "$(bash_rc "$C7" "$cmd")" "context7: an unresearched import in a here-document refuses"
  assert_contains "$(bash_out "$C7" "$cmd")" "axios" "context7: names the library"
  assert_contains "$(bash_out "$C7" "$cmd")" "This Bash command writes" "context7: says the write was through Bash"
  touch "/tmp/.claude_c7_${TEST_HASH}_axios"
  assert_exit_code "0" "$(bash_rc "$C7" "$cmd")" "context7: a researched import passes"
  rm -f "/tmp/.claude_c7_${TEST_HASH}_axios"
  # Without a here-document there is no literal content to scan (residual, documented).
  assert_exit_code "0" "$(bash_rc "$C7" "echo \"import axios from 'axios'\" > src/x.ts")" "context7: echo content is not scanned (residual)"
  assert_exit_code "0" "$(bash_rc "$C7" $'cat > src/x.ts <<EOF\nimport fs from \'fs\'\nEOF')" "context7: a stdlib import passes"
  teardown_test_project
}

# =====================================================================
# 5. The advisories: scalability on an architectural source file, changelog-sync on
#    the changelog
# =====================================================================
test_advisories() {
  local out
  setup_src_project
  jq '.discovery.futurePlatforms = "web dashboard" | .projectConfig._base.changelogFile = "CHANGELOG.md" | .projectConfig._base.syncCommand = "bash sync.sh"' \
    "$TEST_DIR/.claude/manifest.json" > "$TEST_DIR/m.tmp" && mv "$TEST_DIR/m.tmp" "$TEST_DIR/.claude/manifest.json"
  out=$(bash_out "$SC" $'cat > src/UserService.ts <<EOF\nexport class UserService {}\nEOF')
  assert_contains "$out" "web dashboard" "scalability: advises on a Bash write of an architectural file"
  assert_equals "1" "$(jq -s length <<< "$out")" "scalability: one advisory JSON object"
  assert_equals "" "$(bash_out "$SC" 'echo x > src/util.ts')" "scalability: silent on a non-architectural file"
  out=$(bash_out "$CL" $'cat >> CHANGELOG.md <<EOF\n- fix\nEOF')
  assert_contains "$out" "bash sync.sh" "changelog-sync: advises on a Bash write of the changelog"
  assert_equals "" "$(bash_out "$CL" 'echo x >> notes.md')" "changelog-sync: silent on another file"
  teardown_test_project
}

# =====================================================================
# 6. Registration: the five gates are registered for Bash
# =====================================================================
test_registered_for_bash() {
  local out h
  source "$HOOK_DIR/../scripts/_shared.sh"
  out=$(generate_settings_json enforce-superpowers changelog-sync-check scalability-check enforce-plan-tracking enforce-context7)
  for h in enforce-superpowers changelog-sync-check scalability-check enforce-plan-tracking enforce-context7; do
    assert_equals "Bash|Write|Edit|NotebookEdit" \
      "$(jq -r --arg h "$h.sh" '.hooks.PreToolUse[] | select(any(.hooks[]; .command | endswith($h))) | .matcher' <<< "$out")" \
      "registration: $h covers Bash"
  done
}

echo "bash source writes (#39)"
test_targets_per_form
test_targets_not_literal
test_targets_review
test_targets_herestring_arithmetic
test_targets_review2
test_many_targets_fast
test_forms_superpowers
test_forms_plan_tracking
test_block_messages_name_bash
test_passes_untouched
test_logs_are_not_source
test_context7_heredoc
test_advisories
test_registered_for_bash
run_tests
