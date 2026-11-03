#!/usr/bin/env bash
#
# mayhem/test.sh — known-answer tests for ft2-clone's module and sample loaders (already built by
# mayhem/build.sh with the project's normal flags). ft2-clone ships no tests of its own, so each case
# loads a committed fixture (mayhem/kat) through the real loader and asserts the exact decoded result
# (format, song/sample geometry, name, checksums over pattern and sample data). exit 0 = pass.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
: "${SRC:=/mayhem}"
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}


PASSED=0 FAILED=0
KAT_MODULE=mayhem/build/kat_module
KAT_SAMPLE=mayhem/build/kat_sample

# expect <label> <expected line> <binary> <args...>
expect() {
  local label="$1" want="$2" got; shift 2
  if [ ! -x "$1" ]; then echo "FAIL $label: missing $1 (build.sh bug)"; FAILED=$((FAILED+1)); return; fi
  if [ ! -f "${2}" ]; then echo "FAIL $label: missing fixture $2"; FAILED=$((FAILED+1)); return; fi
  got=$("$@" 2>&1)
  if [ "$got" = "$want" ]; then
    echo "ok   $label"; PASSED=$((PASSED+1))
  else
    echo "FAIL $label"; echo "  want: $want"; echo "  got:  $got"; FAILED=$((FAILED+1))
  fi
}

# loaded module (format ids: 1 STK, 2 XM, 3 MOD, 4 S3M, 5 STM, 6 DIGI, 8 IT)
expect 'module song.mod' 'format=3 name="ft2 test mod" channels=4 songlen=2 bpm=125 speed=6 patterns=2 instr=1 samples=1 smpbytes=64 pattsum=3b2522ba smpsum=e8333400' "$KAT_MODULE" mayhem/kat/song.mod
expect 'module song.stk' 'format=1 name="ft2 test stk" channels=4 songlen=2 bpm=125 speed=6 patterns=2 instr=1 samples=1 smpbytes=64 pattsum=3b2522ba smpsum=e8333400' "$KAT_MODULE" mayhem/kat/song.stk
expect 'module song.xm' 'format=2 name="ft2 test xm" channels=4 songlen=2 bpm=125 speed=6 patterns=2 instr=1 samples=1 smpbytes=64 pattsum=408e4740 smpsum=e8333400' "$KAT_MODULE" mayhem/kat/song.xm
expect 'module song.s3m' 'format=4 name="ft2 test s3m" channels=1 songlen=1 bpm=125 speed=6 patterns=1 instr=1 samples=1 smpbytes=64 pattsum=e2c8681d smpsum=e495d494' "$KAT_MODULE" mayhem/kat/song.s3m
expect 'module song.stm' 'format=5 name="ft2 test stm" channels=4 songlen=1 bpm=125 speed=6 patterns=1 instr=1 samples=1 smpbytes=64 pattsum=d8bddcc8 smpsum=e8333400' "$KAT_MODULE" mayhem/kat/song.stm
expect 'module song.digi' 'format=6 name="ft2 test digi" channels=4 songlen=1 bpm=125 speed=6 patterns=1 instr=1 samples=1 smpbytes=64 pattsum=8278c1f0 smpsum=e8333400' "$KAT_MODULE" mayhem/kat/song.digi
expect 'module song.it' 'format=8 name="ft2 test it" channels=2 songlen=1 bpm=125 speed=6 patterns=1 instr=1 samples=1 smpbytes=64 pattsum=8278c1f0 smpsum=e8333400' "$KAT_MODULE" mayhem/kat/song.it
expect 'module rejects a non-module' 'REJECTED' "$KAT_MODULE" mayhem/kat/raw8.bin

# loaded sample (format ids: 0 raw, 1 IFF, 2 WAV, 3 AIFF, 4 FLAC, 5 OGG, 6 MP3, 7 BRR); last arg = stereo choice
expect 'sample sample.iff' 'format=1 bits=8 length=64 loopstart=0 looplen=0 volume=64 finetune=0 relnote=0 name="sine" sum=e8333400' "$KAT_SAMPLE" mayhem/kat/sample.iff 1
expect 'sample wav8m.wav' 'format=2 bits=8 length=160 loopstart=0 looplen=0 volume=64 finetune=-96 relnote=0 name="" sum=cdc28216' "$KAT_SAMPLE" mayhem/kat/wav8m.wav 1
expect 'sample wav16s.wav' 'format=2 bits=16 length=221 loopstart=0 looplen=0 volume=64 finetune=104 relnote=4 name="" sum=f76a5556' "$KAT_SAMPLE" mayhem/kat/wav16s.wav 1
expect 'sample aiff16m.aif' 'format=3 bits=16 length=160 loopstart=0 looplen=0 volume=64 finetune=-96 relnote=0 name="" sum=76dc5516' "$KAT_SAMPLE" mayhem/kat/aiff16m.aif 1
expect 'sample raw8.bin' 'format=0 bits=8 length=256 loopstart=0 looplen=0 volume=64 finetune=0 relnote=0 name="" sum=1f89f2d8' "$KAT_SAMPLE" mayhem/kat/raw8.bin 1
expect 'sample sample.flac' 'format=4 bits=16 length=400 loopstart=0 looplen=0 volume=64 finetune=-96 relnote=0 name="" sum=f5b949dc' "$KAT_SAMPLE" mayhem/kat/sample.flac 1
expect 'sample sample.ogg' 'format=5 bits=16 length=800 loopstart=0 looplen=0 volume=64 finetune=-96 relnote=0 name="" sum=5a5a3fd2' "$KAT_SAMPLE" mayhem/kat/sample.ogg 1
expect 'sample sample.mp3' 'format=6 bits=16 length=1600 loopstart=0 looplen=0 volume=64 finetune=-96 relnote=0 name="" sum=0e4d2720' "$KAT_SAMPLE" mayhem/kat/sample.mp3 1
expect 'sample sample.brr' 'format=7 bits=16 length=64 loopstart=0 looplen=0 volume=64 finetune=0 relnote=0 name="" sum=10682fc4' "$KAT_SAMPLE" mayhem/kat/sample.brr 1
expect 'sample stereo8.wav (stereo choice 1)' 'format=2 bits=8 length=110 loopstart=0 looplen=0 volume=64 finetune=104 relnote=4 name="" sum=f06ae04c' "$KAT_SAMPLE" mayhem/kat/stereo8.wav 1
expect 'sample stereo8.wav (stereo choice 2)' 'format=2 bits=8 length=110 loopstart=0 looplen=0 volume=64 finetune=104 relnote=4 name="" sum=a399f35f' "$KAT_SAMPLE" mayhem/kat/stereo8.wav 2
expect 'sample stereo8.wav (stereo choice 3)' 'format=2 bits=8 length=110 loopstart=0 looplen=0 volume=64 finetune=104 relnote=4 name="" sum=18fb0cf8' "$KAT_SAMPLE" mayhem/kat/stereo8.wav 3

emit_ctrf "ft2-clone-loader-kat" "$PASSED" "$FAILED" 0
