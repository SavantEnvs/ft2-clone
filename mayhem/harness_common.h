// Shared helpers for the ft2-clone harnesses: the loaders take a FILE*, so the fuzzer's bytes are
// staged in one anonymous scratch file (TMPDIR, unlinked at once) that is rewritten per input.
#pragma once

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int scratchFd = -1;

static void scratchInit(void)
{
	const char *dir = getenv("TMPDIR");
	if (dir == NULL || dir[0] == '\0')
		dir = "/tmp";

	char path[4096];
	snprintf(path, sizeof (path), "%s/ft2-harness-XXXXXX", dir);
	scratchFd = mkstemp(path);
	if (scratchFd < 0)
		abort();

	unlink(path);
}

// returns a FILE* positioned at 0 holding exactly the input bytes, or NULL for an empty input
static FILE *scratchOpen(const uint8_t *data, size_t size)
{
	if (size == 0)
		return NULL;

	if (scratchFd < 0)
		scratchInit();

	if (ftruncate(scratchFd, 0) != 0)
		abort();

	size_t done = 0;
	while (done < size)
	{
		ssize_t n = pwrite(scratchFd, data + done, size - done, (off_t)done);
		if (n <= 0)
			abort();

		done += (size_t)n;
	}

	int fd = dup(scratchFd);
	if (fd < 0)
		abort();

	lseek(fd, 0, SEEK_SET);
	FILE *f = fdopen(fd, "rb");
	if (f == NULL)
		abort();

	return f;
}
