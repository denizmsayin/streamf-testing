#include <sys/types.h>
#include <sys/stat.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <unistd.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

#ifndef MAX_WORD_SIZE
#define MAX_WORD_SIZE 20
#endif

// After much deliberation, I decided to do away with the header
// and just hardcode the definitions here for easy sharing. I hope
// your definitions match them:

enum FilterType { STREAMF_UPPER, STREAMF_LOWER, STREAMF_CENSOR, STREAMF_SUBS, STREAMF_XOR};

struct filter_struct {
    enum FilterType type;
    union {
        struct streamf_subs_struct {
            char from[MAX_WORD_SIZE];
            char to[MAX_WORD_SIZE];
        } subs;
        struct streamf_xor_struct {
            char from[MAX_WORD_SIZE];
            char cipher[MAX_WORD_SIZE];
        } xor;
        char censor[MAX_WORD_SIZE];
    };
};

#define STREAMF_IOC_MAGIC 's'
#define STREAMF_IOCRESETR _IO(STREAMF_IOC_MAGIC, 1)
#define STREAMF_IOCRESETW _IO(STREAMF_IOC_MAGIC, 2)
#define STREAMF_IOCSPUSHW _IOW(STREAMF_IOC_MAGIC,3, long)
#define STREAMF_IOCSPUSHR _IOR(STREAMF_IOC_MAGIC, 4, long)
#define STREAMF_IOCGPOPW _IOW(STREAMF_IOC_MAGIC,5, long)
#define STREAMF_IOCGPOPR _IOR(STREAMF_IOC_MAGIC,6, long)
#define STREAMF_IOC_MAXNR 6

// END DEFINITIONS

// Ahh, pure boilerplate, the best kind of program :3 (!)

enum direction { D_READ, D_WRITE };
enum operation { O_PUSH, O_POP, O_RESET };

static void error_fmt(const char *fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    vfprintf(stderr, fmt, args);
    va_end(args);
    exit(EXIT_FAILURE);
}

static void perror_fmt(const char *fmt, ...)
{
    static char buffer[8192]; // not really safe but whatever
    va_list args;
    va_start(args, fmt);
    vsprintf(buffer, fmt, args);
    va_end(args);
    perror(buffer);
    exit(EXIT_FAILURE);
}

static int get_ioctl_cmd(enum direction dir, enum operation op)
{
    int read = dir == D_READ;
    switch (op) {
        case O_PUSH:    return read ? STREAMF_IOCSPUSHR : STREAMF_IOCSPUSHW;
        case O_POP:     return read ? STREAMF_IOCGPOPR  : STREAMF_IOCGPOPW;
        case O_RESET:   return read ? STREAMF_IOCRESETR : STREAMF_IOCRESETW;
        default:        error_fmt("Unexpected op %d\n", (int) op);
    }
    return 0;   
}

static int streq(const char *s1, const char *s2) { return !strcmp(s1, s2); }

static enum direction str2dir(const char *s)
{
    if (streq(s, "r"))
        return D_READ;
    else if (streq(s, "w"))
        return D_WRITE;
    error_fmt("Unknown direction %s, try r or w\n", s);
    return D_READ; // unreachable
}

static enum operation str2op(const char *s)
{
    if (streq(s, "push"))
        return O_PUSH;
    else if (streq(s, "pop"))
        return O_POP;
    else if (streq(s, "reset"))
        return O_RESET;
    error_fmt("Unknown operation %s, try push, pop or reset\n", s);
    return O_PUSH;
}

static void build_filter_1(const char *s, struct filter_struct *filter)
{
    if (streq(s, "upper"))
        filter->type = STREAMF_UPPER;
    else if (streq(s, "lower"))
        filter->type = STREAMF_LOWER;
    else
        error_fmt("Unknown length-1 filter spec %s, try upper or lower\n", s);
}

static void build_filter_2(const char *s1, const char *s2, struct filter_struct *filter)
{
    if (streq(s1, "censor")) {
        filter->type = STREAMF_CENSOR;
        strncpy(filter->censor, s2, MAX_WORD_SIZE);
    } else {
        error_fmt("Unknown length-2 filter spec %s, only censor works\n", s1);
    }
}

static void build_filter_3(const char *s1, const char *s2, const char *s3,
                           struct filter_struct *filter)
{
    if (streq(s1, "subs")) {
        filter->type = STREAMF_SUBS;
        strncpy(filter->subs.from, s2, MAX_WORD_SIZE);
        strncpy(filter->subs.to, s3, MAX_WORD_SIZE);
    } else if (streq(s1, "xor")) {
        filter->type = STREAMF_XOR;
        strncpy(filter->xor.from, s2, MAX_WORD_SIZE);
        strncpy(filter->xor.cipher, s3, MAX_WORD_SIZE);
    } else {
        error_fmt("Unknown length-3 filter spec %s, try subs or xor\n", s1);
    }
}

static void build_filter(char *specs[], int nspecs, struct filter_struct *filter)
{
    switch (nspecs) {
    case 1:     build_filter_1(specs[0], filter); break;
    case 2:     build_filter_2(specs[0], specs[1], filter); break;
    case 3:     build_filter_3(specs[0], specs[1], specs[2], filter); break;
    default:    error_fmt("Too few/many words (%d) in filter format specifier\n", nspecs);
    }
}

static void print_usage(const char *name)
{
    printf("usage: %s device r|w push|pop|reset [filter_specifier]\n"
           "    filter_specifier is necessary for pushing, as follows:\n"
           "    1. upper\n"
           "    2. lower\n"
           "    3. censor word\n"
           "    4. subs word repl\n"
           "    5. cypher word cypher\n"
           "\n" 
           "    word, repl and cypher will be truncated to %d chars if too long.\n" 
           "    Be warned that the filter won't contain a null char if using the full %d!\n"
           "    Note that cypher does not support binary values since it's passed\n"
           "    as one of the arguments :( Also, DO NOT QUOTE the filter specifier\n"
           "\n"
           "example call: %s /dev/streamf2 w push subs hello bye\n"
           , name, MAX_WORD_SIZE, MAX_WORD_SIZE, name);
}

static void print_filter(const struct filter_struct *filter)
{
    switch (filter->type) {
    case STREAMF_UPPER:
        printf("UPPER\n");
        break;

    case STREAMF_LOWER:
        printf("LOWER\n");
        break;
    
    case STREAMF_CENSOR:
        printf("CENSOR [%s]\n", filter->censor);
        break;

    case STREAMF_SUBS:
        printf("SUBS from:[%s] to:[%s]\n", filter->subs.from, 
               filter->subs.to);
        break;

    case STREAMF_XOR:
        printf("XOR from:[%s] cypher:[%s]\n", filter->xor.from,
               filter->xor.cipher);
        break;

    default:
        error_fmt("Unexpected filter type %d\n", (int) filter->type);
    }
}

int main(int argc, char *argv[]) 
{
    enum direction dir;
    enum operation op;
    const char *device;
    int ret, fd, ioctl_cmd;
    struct filter_struct filter;

    if (argc < 4) {
        print_usage(argv[0]);
        return 0;
    }

    device = argv[1];
    dir = str2dir(argv[2]);
    op = str2op(argv[3]);
    ioctl_cmd = get_ioctl_cmd(dir, op);

    if (op == O_PUSH)
        build_filter(argv + 4, argc - 4, &filter);

    fd = open(device, O_RDWR);
    if (fd < 0)
        perror_fmt("Failed to open device %s", device);

    ret = ioctl(fd, ioctl_cmd, &filter); 
    if (ret < 0) {
        close(fd);
        fprintf(stderr, "ioctl call failed, filter stack may be full or empty\n");
        perror_fmt("Reported reason");
    }

    if (op == O_POP) {
        printf("Popped filter ");
        print_filter(&filter);
    }

    close(fd);

    return 0;
}
