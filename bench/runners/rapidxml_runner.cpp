#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#include "rapidxml.hpp"

static uint64_t now_ns() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
}

template <class T>
static inline void consume_document(const T *doc) {
#if defined(__GNUC__) || defined(__clang__)
    // RapidXML is header-only, so without an optimization barrier the compiler
    // can see both construction and destruction and may discard dead DOM work.
    __asm__ __volatile__("" : : "g"(doc) : "memory");
#else
    volatile const T *sink = doc;
    (void)sink;
#endif
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

    if (argv[2][0] < '0' || argv[2][0] > '9') {
        fprintf(stderr, "invalid iterations: %s\n", argv[2]);
        return 2;
    }
    errno = 0;
    char *parse_end = nullptr;
    const unsigned long long parsed_iterations = strtoull(argv[2], &parse_end, 10);
    if (errno == ERANGE || parse_end == argv[2] || *parse_end != '\0' || parsed_iterations == 0 || parsed_iterations > SIZE_MAX) {
        fprintf(stderr, "invalid iterations: %s\n", argv[2]);
        return 2;
    }
    const size_t iterations = (size_t)parsed_iterations;

    size_t len = 0;
    char *input = read_file(argv[1], &len);
    if (!input) {
        fprintf(stderr, "failed to read file: %s\n", argv[1]);
        return 1;
    }

    const uint64_t start = now_ns();
    for (size_t i = 0; i < iterations; i++) {
        rapidxml::xml_document<> doc;
        try {
            // Match zxml's zero-copy/raw-value DOM semantics. Non-destructive
            // mode avoids string terminators and entity translation, so the
            // source buffer can be reused without timing an unrelated memcpy.
            // Keep closing-tag validation off because this is the turbo peer.
            constexpr int flags = rapidxml::parse_non_destructive |
                                  rapidxml::parse_declaration_node |
                                  rapidxml::parse_comment_nodes |
                                  rapidxml::parse_doctype_node |
                                  rapidxml::parse_pi_nodes;
            doc.parse<flags>(input);
        } catch (const rapidxml::parse_error &) {
            free(input);
            return 1;
        }
        consume_document(&doc);
    }
    const uint64_t end = now_ns();

    printf("%llu\n", (unsigned long long)(end - start));
    free(input);
    return 0;
}
