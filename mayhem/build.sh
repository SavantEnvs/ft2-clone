#!/usr/bin/env bash
#
# mayhem/build.sh — build ft2-clone's fuzz harnesses and the known-answer probes test.sh runs.
#
# ft2-clone is a GUI tracker; there is no library target, so the whole application (minus main) is
# compiled into an archive and the loaders are fuzzed through two harnesses that #include the
# loader translation units (mayhem/fuzz_module.c, mayhem/fuzz_sample.c). MIDI (rtmidi/ALSA) is
# left out, as in upstream's own "nomidi" builds. Everything is built under mayhem/build (gitignored).
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — it must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# `=` (not `:=`) so an explicit EMPTY SANITIZER_FLAGS builds with no sanitizers.
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"
B="$SRC/mayhem/build"
rm -rf "$B"
mkdir -p "$B/fuzz" "$B/kat"

# Every application source except main(); the loader files stay in the archive for the harness that
# does not include them itself.
mapfile -t SOURCES < <(ls src/*.c src/gfxdata/*.c src/mixer/*.c src/scopes/*.c src/modloaders/*.c src/smploaders/*.c \
                        | grep -v '^src/ft2_main\.c$')

SDL_CFLAGS=$(pkg-config --cflags sdl2)
SDL_LIBS=$(pkg-config --libs sdl2)

compile_all() {   # compile_all <objdir> <flags...>
	local dir="$1"; shift
	printf '%s\0' "${SOURCES[@]}" | xargs -0 -P "$MAYHEM_JOBS" -I{} bash -c '
		src="$1"; dir="$2"; shift 2
		obj="$dir/$(echo "${src%.c}" | tr / _).o"
		"$@" -c "$src" -o "$obj"' _ {} "$dir" "$@"
}

# 1) Project, instrumented: sanitizers + SanCov (fuzzer-no-link, even with SANITIZER_FLAGS empty) + DWARF<=3.
# Five benign upstream idioms are relaxed (only these UBSan checks; ASan and the rest of UBSan stay halting):
#  - alignment: SMP_DAT_OFFSET is odd on purpose, so every 16-bit sample buffer is misaligned by design;
#  - shift-base: `negative << n` (replayer, loaders) relies on two's-complement shifts;
#  - function: minivorbis.h calls the project's fseek/fread wrappers through ov_callbacks with a different
#    pointer type;
#  - pointer-overflow / nonnull-attribute: NULL+0 and memcpy(dst, NULL, 0) on empty buffers (minivorbis,
#    the MP3/FLAC loaders), harmless and reachable from every near-empty input.
FUZZ_CFLAGS=(-O2 -ffast-math -DNDEBUG -fno-strict-aliasing \
             $SANITIZER_FLAGS -fno-sanitize=alignment,shift-base,function,pointer-overflow,nonnull-attribute $DEBUG_FLAGS -fsanitize=fuzzer-no-link $SDL_CFLAGS)
compile_all "$B/fuzz" "$CC" "${FUZZ_CFLAGS[@]}"
rm -f "$B/libft2.a"
ar rcs "$B/libft2.a" "$B"/fuzz/*.o

$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$B/lsan_off.o"

# Without ASan there is no sanitizer runtime to provide the SanCov callbacks in the standalone link.
STANDALONE_EXTRA=()
case "$SANITIZER_FLAGS" in
	*address*) ;;
	*)
		cat > "$B/sancov_stub.c" <<'STUB'
#include <stdint.h>
void __sanitizer_cov_trace_pc_guard_init(uint32_t *s, uint32_t *e) { (void)s; (void)e; }
void __sanitizer_cov_trace_pc_guard(uint32_t *g) { (void)g; }
void __sanitizer_cov_8bit_counters_init(char *s, char *e) { (void)s; (void)e; }
void __sanitizer_cov_pcs_init(const uintptr_t *s, const uintptr_t *e) { (void)s; (void)e; }
STUB
		$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$B/sancov_stub.c" -o "$B/sancov_stub.o"
		STANDALONE_EXTRA=("$B/sancov_stub.o")
		;;
esac

# 2) Harnesses: <target>:<source>:<extra define>
build_harness() {   # build_harness <name> <source> [define]
	local name="$1" harness="$2" def="${3:-}"
	local defs=()
	[ -z "$def" ] || defs=("-D$def")
	$CC "${FUZZ_CFLAGS[@]}" "${defs[@]}" -c "$SRC/mayhem/$harness" -o "$B/$name.o"
	$CC $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$B/$name.o" "$B/libft2.a" "$B/lsan_off.o" \
		$SDL_LIBS -lm -lpthread -o "$SRC/$name"
	$CC $SANITIZER_FLAGS $DEBUG_FLAGS -x c "$STANDALONE_FUZZ_MAIN" -x none "$B/$name.o" "$B/libft2.a" "$B/lsan_off.o" \
		"${STANDALONE_EXTRA[@]}" $SDL_LIBS -lm -lpthread -o "$SRC/$name-standalone"
}
build_harness fuzz_module       fuzz_module.c
build_harness fuzz_sample       fuzz_sample.c 'SMP_NAME="sample.smp"'
build_harness fuzz_sample_brr   fuzz_sample.c 'SMP_NAME="sample.brr"'
build_harness fuzz_sample_flac  fuzz_sample.c 'SMP_NAME="sample.flac"'
build_harness fuzz_sample_ogg   fuzz_sample.c 'SMP_NAME="sample.ogg"'
build_harness fuzz_sample_mp3   fuzz_sample.c 'SMP_NAME="sample.mp3"'

# 3) Known-answer probes for test.sh: the same loaders, the project's NORMAL flags (no sanitizers, no
# DWARF override), dynamically linked so the sabotage shim can neuter them.
KAT_CFLAGS=(-O2 -ffast-math -DNDEBUG -fno-strict-aliasing $COVERAGE_FLAGS $SDL_CFLAGS)
compile_all "$B/kat" "$CC" "${KAT_CFLAGS[@]}"
rm -f "$B/libft2-kat.a"
ar rcs "$B/libft2-kat.a" "$B"/kat/*.o
for p in module sample; do
	$CC "${KAT_CFLAGS[@]}" -DKAT_MAIN "$SRC/mayhem/fuzz_$p.c" "$B/libft2-kat.a" $SDL_LIBS -lm -lpthread $COVERAGE_FLAGS \
		-o "$B/kat_$p"
done
