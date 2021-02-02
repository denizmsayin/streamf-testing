#include <poll.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>

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

int main(int argc, char *argv[])
{
    const char *device;
    int ret, fd, timeout;
    struct pollfd fds;

    if (argc != 3) {
        printf("usage: %s device timeout\n", argv[0]);
        return 0;
    }

    device = argv[1];
    timeout = (int) strtol(argv[1], NULL, 10);

    fd = open(device, O_RDWR);
    if (fd < 0)
        perror_fmt("Failed to open device %s\n", device);

    fds.fd = fd;
    fds.events = POLLIN | POLLOUT;
    
    ret = poll(&fds, 1, timeout);
    if (ret == 0) {
        puts("poll timed out.");
        return 0;
    } else if (ret < 0) {
        perror_fmt("Poll call failed\n");
    }

    if (fds.revents & POLLIN)
        puts("Device is now available for reading.");
    if (fds.revents & POLLOUT)
        puts("Device is now available for writing.");
    if (fds.revents & ~(POLLOUT | POLLIN))
        puts("Some other event occurred. Better improve the code to check!");

    return 0;
}
