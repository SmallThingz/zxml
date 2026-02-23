#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "rapidxml.hpp"

static uint64_t now_ns() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
}

static char *read_file(const char *path, size_t *out_len) {
    FILE *f = fopen(path, "rb");
    if (!f) return nullptr;
    if (fseek(f, 0, SEEK_END) != 0) {
        fclose(f);
        return nullptr;
    }
    long sz = ftell(f);
    if (sz < 0) {
        fclose(f);
        return nullptr;
    }
    rewind(f);

    char *buf = (char *)malloc((size_t)sz + 1);
    if (!buf) {
        fclose(f);
        return nullptr;
    }

    if ((size_t)sz > 0 && fread(buf, 1, (size_t)sz, f) != (size_t)sz) {
        free(buf);
        fclose(f);
        return nullptr;
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

    const size_t iterations = (size_t)strtoull(argv[2], nullptr, 10);

    size_t len = 0;
    char *input = read_file(argv[1], &len);
    if (!input) {
        fprintf(stderr, "failed to read file: %s\n", argv[1]);
        return 1;
    }

    char *working = (char *)malloc(len + 1);
    if (!working) {
        free(input);
        return 1;
    }

    const uint64_t start = now_ns();
    for (size_t i = 0; i < iterations; i++) {
        memcpy(working, input, len + 1);
        rapidxml::xml_document<> doc;
        try {
            doc.parse<rapidxml::parse_default>(working);
        } catch (const rapidxml::parse_error &) {
            free(working);
            free(input);
            return 1;
        }
    }
    const uint64_t end = now_ns();

    printf("%llu\n", (unsigned long long)(end - start));
    free(working);
    free(input);
    return 0;
}
