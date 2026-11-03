// Fuzz harness for ft2-clone's sample loaders (IFF/WAV/AIFF/FLAC/OGG/MP3/BRR/raw).
// The loader translation unit is included so the static format detector can be called exactly as
// the application's loadSampleThread() does. The application picks FLAC/OGG/MP3/BRR by file
// extension, so each such target is built with its own SMP_NAME.
#include "../src/ft2_sample_loader.h"
#include "../src/ft2_sample_loader.c"
#include "harness_common.h"

#ifndef SMP_NAME
#define SMP_NAME "sample.smp"
#endif

static uint8_t stereoChoice = STEREO_SAMPLE_MIX_TO_MONO;

static void quietMsgBox(const char *fmt, ...) { (void)fmt; }
static int16_t pickStereoChannel(int16_t type, const char *headline, const char *text, void (*cb)(void)) { (void)type; (void)headline; (void)text; (void)cb; return stereoChoice; }

// returns 0 if a sample was loaded, -1 if the loader rejected the input
static int processSample(const uint8_t *data, size_t size, bool verbose, int forcedStereo, const char *fileName)
{
	FILE *f = scratchOpen(data, size);
	if (f == NULL)
		return -1;

	loaderMsgBox = quietMsgBox;
	loaderSysReq = pickStereoChannel;
	// left/right/mix: derived from the input unless a known-answer run forces one
	stereoChoice = (uint8_t)(forcedStereo != 0 ? forcedStereo : 1 + (data[size-1] % 3));

	loadAsInstrFlag = false;
	smpFilenameSet = false;
	smpFilename = NULL;
	memset(&tmpSmp, 0, sizeof (tmpSmp));

	char name[512];
	snprintf(name, sizeof (name), "%s", fileName != NULL ? fileName : SMP_NAME);
	int8_t format = detectSample(f, name, (uint32_t)strlen(name));
	fseek(f, 0, SEEK_END);
	uint32_t filesize = (uint32_t)ftell(f);
	rewind(f);

	bool wasLoaded = false;
	switch (format)
	{
		case FORMAT_IFF: wasLoaded = loadIFF(f, filesize); break;
		case FORMAT_WAV: wasLoaded = loadWAV(f, filesize); break;
		case FORMAT_AIFF: wasLoaded = loadAIFF(f, filesize); break;
		case FORMAT_FLAC: wasLoaded = loadFLAC(f, filesize); break;
		case FORMAT_OGG: wasLoaded = loadOGG(f, filesize); break;
		case FORMAT_MP3: wasLoaded = loadMP3(f, filesize); break;
		case FORMAT_BRR: wasLoaded = loadBRR(f, filesize); break;
		default: wasLoaded = loadRAW(f, filesize); break;
	}
	fclose(f);

	if (wasLoaded && verbose)
	{
		uint32_t sum = 0;
		const int32_t bytes = (tmpSmp.flags & SAMPLE_16BIT) ? tmpSmp.length * 2 : tmpSmp.length;
		for (int32_t i = 0; tmpSmp.dataPtr != NULL && i < bytes; i++)
			sum = sum * 31 + (uint8_t)tmpSmp.dataPtr[i];

		printf("format=%d bits=%d length=%d loopstart=%d looplen=%d volume=%d finetune=%d relnote=%d name=\"%s\" sum=%08x\n",
			format, (tmpSmp.flags & SAMPLE_16BIT) ? 16 : 8, tmpSmp.length, tmpSmp.loopStart, tmpSmp.loopLength,
			tmpSmp.volume, tmpSmp.finetune, tmpSmp.relativeNote, tmpSmp.name, sum);
	}

	freeTmpSample(&tmpSmp);
	return wasLoaded ? 0 : -1;
}

#ifdef KAT_MAIN
int main(int argc, char **argv)
{
	if (argc != 3)
	{
		fprintf(stderr, "usage: %s <sample file> <stereo choice 1..3>\n", argv[0]);
		return 2;
	}

	FILE *in = fopen(argv[1], "rb");
	if (in == NULL)
	{
		fprintf(stderr, "cannot open %s\n", argv[1]);
		return 2;
	}

	static uint8_t buf[4 << 20];
	size_t n = fread(buf, 1, sizeof (buf), in);
	fclose(in);
	if (n == 0)
		return 2;

	if (processSample(buf, n, true, atoi(argv[2]), argv[1]) != 0)
	{
		puts("REJECTED");
		return 1;
	}

	return 0;
}
#else
int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	return processSample(data, size, false, 0, NULL) == 0 ? 0 : -1;
}
#endif
