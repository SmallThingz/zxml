#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#include <libxml/parser.h>
#include <libxml/tree.h>

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

    const size_t iterations = (size_t)strtoull(argv[2], NULL, 10);

    size_t len = 0;
    char *input = read_file(argv[1], &len);
    if (!input) {
        fprintf(stderr, "failed to read file: %s\n", argv[1]);
        return 1;
    }

    xmlInitParser();

    const uint64_t start = now_ns();
    for (size_t i = 0; i < iterations; i++) {
        xmlDocPtr doc = xmlReadMemory(input, (int)len, "bench.xml", NULL, XML_PARSE_NOERROR | XML_PARSE_NOWARNING | XML_PARSE_NONET);
        if (!doc) {
            free(input);
            xmlCleanupParser();
            return 1;
        }
        xmlFreeDoc(doc);
    }
    const uint64_t end = now_ns();

    printf("%llu\n", (unsigned long long)(end - start));

    free(input);
    xmlCleanupParser();
    return 0;
}
