#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#include "yxml.h"

static uint64_t now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
}

static char *read_file(const char *path, size_t *out_len) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;

    if (fseek(f, 0, SEEK_END) != 0) {
        fclose(f);
        return NULL;
    }
    long sz = ftell(f);
    if (sz < 0) {
        fclose(f);
        return NULL;
    }
    rewind(f);

    char *buf = (char *)malloc((size_t)sz + 1);
    if (!buf) {
        fclose(f);
        return NULL;
    }

    if ((size_t)sz > 0 && fread(buf, 1, (size_t)sz, f) != (size_t)sz) {
        free(buf);
        fclose(f);
        return NULL;
    }
    fclose(f);

    buf[sz] = '\0';
    *out_len = (size_t)sz;
    return buf;
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: %s <xml-file> <iterations>\n", argv[0]);
        return 2;
    }

    size_t len = 0;
    char *input = read_file(argv[1], &len);
    if (!input) {
        fprintf(stderr, "failed to read file: %s\n", argv[1]);
        return 1;
    }

    const size_t iterations = (size_t)strtoull(argv[2], NULL, 10);

    char *stack = (char *)malloc(len + 1);
    if (!stack) {
        free(input);
        return 1;
    }

    const uint64_t start = now_ns();
    for (size_t it = 0; it < iterations; it++) {
        yxml_t x;
        yxml_init(&x, stack, len + 1);

        for (size_t i = 0; i < len; i++) {
            yxml_ret_t r = yxml_parse(&x, (unsigned char)input[i]);
            if (r < 0) {
                free(stack);
                free(input);
                return 1;
            }
        }

        if (yxml_eof(&x) < 0) {
            free(stack);
            free(input);
            return 1;
        }
    }
    const uint64_t end = now_ns();

    printf("%llu\n", (unsigned long long)(end - start));

    free(stack);
    free(input);
    return 0;
}
