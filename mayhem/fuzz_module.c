// Fuzz harness for ft2-clone's module loaders (XM/MOD/S3M/STM/STK/DIGI/BEM/IT).
// The loader translation unit is included so the static format detector and the load-error cleanup
// can be called exactly as the application's own doLoadMusic() does.
#include "../src/ft2_module_loader.c"
#include "harness_common.h"

static void quietMsgBox(const char *fmt, ...) { (void)fmt; }
static int16_t quietSysReq(int16_t type, const char *headline, const char *text, void (*cb)(void)) { (void)type; (void)headline; (void)text; (void)cb; return 0; }

// returns 0 if a module was loaded, -1 if the loader rejected the input
static int processModule(const uint8_t *data, size_t size, bool verbose)
{
	FILE *f = scratchOpen(data, size);
	if (f == NULL)
		return -1;

	loaderMsgBox = quietMsgBox;
	loaderSysReq = quietSysReq;
	clearTmpModule();

	int8_t format = detectModule(f);
	fseek(f, 0, SEEK_END);
	uint32_t filesize = (uint32_t)ftell(f);
	rewind(f);

	bool wasLoaded = false;
	switch (format)
	{
		case FORMAT_XM: wasLoaded = loadXM(f, filesize); break;
		case FORMAT_S3M: wasLoaded = loadS3M(f, filesize); break;
		case FORMAT_STM: wasLoaded = loadSTM(f, filesize); break;
		case FORMAT_MOD: wasLoaded = loadMOD(f, filesize); break;
		case FORMAT_POSSIBLY_STK: wasLoaded = loadSTK(f, filesize); break;
		case FORMAT_DIGI: wasLoaded = loadDIGI(f, filesize); break;
		case FORMAT_BEM: wasLoaded = loadBEM(f, filesize); break;
		case FORMAT_IT: wasLoaded = loadIT(f, filesize); break;
		default: break;
	}
	fclose(f);

	if (wasLoaded && verbose)
	{
		uint32_t numPatterns = 0, numInstr = 0, numSamples = 0, smpBytes = 0, pattSum = 0, smpSum = 0;
		for (int32_t i = 0; i < MAX_PATTERNS; i++)
		{
			if (patternTmp[i] == NULL)
				continue;

			numPatterns++;
			const uint8_t *p = (const uint8_t *)patternTmp[i];
			for (int32_t j = 0; j < patternNumRowsTmp[i] * TRACK_WIDTH; j++)
				pattSum = pattSum * 31 + p[j];
		}

		for (int32_t i = 1; i <= 128; i++)
		{
			if (instrTmp[i] == NULL)
				continue;

			numInstr++;
			for (int32_t j = 0; j < MAX_SMP_PER_INST; j++)
			{
				const sample_t *s = &instrTmp[i]->smp[j];
				if (s->dataPtr == NULL || s->length <= 0)
					continue;

				numSamples++;
				smpBytes += (uint32_t)s->length;
				for (int32_t k = 0; k < s->length; k++)
					smpSum = smpSum * 31 + (uint8_t)s->dataPtr[k];
			}
		}

		printf("format=%d name=\"%s\" channels=%d songlen=%d bpm=%d speed=%d patterns=%u instr=%u samples=%u smpbytes=%u pattsum=%08x smpsum=%08x\n",
			format, songTmp.name, songTmp.numChannels, songTmp.songLength, songTmp.BPM, songTmp.speed,
			numPatterns, numInstr, numSamples, smpBytes, pattSum, smpSum);
	}

	freeTmpModule();
	return wasLoaded ? 0 : -1;
}

#ifdef KAT_MAIN
int main(int argc, char **argv)
{
	if (argc != 2)
	{
		fprintf(stderr, "usage: %s <module file>\n", argv[0]);
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

	if (processModule(buf, n, true) != 0)
	{
		puts("REJECTED");
		return 1;
	}

	return 0;
}
#else
int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	return processModule(data, size, false) == 0 ? 0 : -1;
}
#endif
