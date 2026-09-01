#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#include "pugixml.hpp"

static uint64_t now_ns() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
}

static inline void consume_document(const pugi::xml_document *doc) {
#if defined(__GNUC__) || defined(__clang__)
    // The benchmark measures construction, not traversal. Make the complete
    // document observable without walking it inside the timed region.
    __asm__ __volatile__("" : : "g"(doc) : "memory");
#else
    volatile const pugi::xml_document *sink = doc;
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
        pugi::xml_document doc;
        // Match zxml's zero-copy/raw-value DOM semantics. Build all node kinds
        // benchmarked by zxml, but leave entity expansion, EOL conversion and
        // attribute-value normalization disabled; zxml performs those lazily.
        // Whitespace-only PCDATA stays disabled, matching zxml's default.
        constexpr unsigned int flags = pugi::parse_cdata |
                                       pugi::parse_pi |
                                       pugi::parse_comments |
                                       pugi::parse_declaration |
                                       pugi::parse_doctype;
        pugi::xml_parse_result r = doc.load_buffer(input, len, flags);
        if (!r) {
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
