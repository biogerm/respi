#include <stdint.h>

#ifndef LISTEN_PORT
#define LISTEN_PORT 54322
#endif

#ifndef TARGET_PORT
#define TARGET_PORT 54321
#endif

#ifndef TARGET_IP_BE
#define TARGET_IP_BE 0xC0A80148u /* 192.168.1.72 */
#endif

#define SYS_EXIT 1
#define SYS_WRITE 4
#define SYS_CLOSE 6
#define SYS_SOCKET 281
#define SYS_BIND 282
#define SYS_SENDTO 290
#define SYS_RECVFROM 292
#define SYS_SETSOCKOPT 294

#define AF_INET 2
#define SOCK_DGRAM 2
#define IPPROTO_UDP 17
#define SOL_SOCKET 1
#define SO_REUSEADDR 2

typedef unsigned int socklen_t;

struct sockaddr_in {
  uint16_t sin_family;
  uint16_t sin_port;
  uint32_t sin_addr;
  uint8_t sin_zero[8];
};

static long syscall6(long n, long a, long b, long c, long d, long e, long f) {
  register long r0 asm("r0") = a;
  register long r1 asm("r1") = b;
  register long r2 asm("r2") = c;
  register long r3 asm("r3") = d;
  register long r4 asm("r4") = e;
  register long r5 asm("r5") = f;
  register long r7 asm("r7") = n;
  asm volatile("svc 0" : "+r"(r0) : "r"(r1), "r"(r2), "r"(r3), "r"(r4), "r"(r5), "r"(r7) : "memory");
  return r0;
}

static void sys_exit(int code) {
  syscall6(SYS_EXIT, code, 0, 0, 0, 0, 0);
  for (;;) {}
}

static long sys_write(int fd, const void *buf, unsigned len) {
  return syscall6(SYS_WRITE, fd, (long)buf, len, 0, 0, 0);
}

static long sys_close(int fd) {
  return syscall6(SYS_CLOSE, fd, 0, 0, 0, 0, 0);
}

static long sys_socket(int domain, int type, int protocol) {
  return syscall6(SYS_SOCKET, domain, type, protocol, 0, 0, 0);
}

static long sys_bind(int fd, const struct sockaddr_in *addr, unsigned addrlen) {
  return syscall6(SYS_BIND, fd, (long)addr, addrlen, 0, 0, 0);
}

static long sys_setsockopt(int fd, int level, int optname, const void *optval, unsigned optlen) {
  return syscall6(SYS_SETSOCKOPT, fd, level, optname, (long)optval, optlen, 0);
}

static long sys_sendto(int fd, const void *buf, unsigned len, int flags, const struct sockaddr_in *addr, unsigned addrlen) {
  return syscall6(SYS_SENDTO, fd, (long)buf, len, flags, (long)addr, addrlen);
}

static long sys_recvfrom(int fd, void *buf, unsigned len, int flags, struct sockaddr_in *addr, socklen_t *addrlen) {
  return syscall6(SYS_RECVFROM, fd, (long)buf, len, flags, (long)addr, (long)addrlen);
}

static uint16_t bswap16(uint16_t x) {
  return (uint16_t)((x << 8) | (x >> 8));
}

static uint32_t bswap32(uint32_t x) {
  return ((x & 0xff) << 24) | ((x & 0xff00) << 8) | ((x & 0xff0000) >> 8) | ((x >> 24) & 0xff);
}

static void mem_set(void *p, uint8_t v, unsigned n) {
  uint8_t *b = (uint8_t *)p;
  while (n--) *b++ = v;
}

static void mem_copy(void *dst, const void *src, unsigned n) {
  uint8_t *d = (uint8_t *)dst;
  const uint8_t *s = (const uint8_t *)src;
  while (n--) *d++ = *s++;
}

static int same_addr(const struct sockaddr_in *a, const struct sockaddr_in *b) {
  return a->sin_family == b->sin_family &&
         a->sin_port == b->sin_port &&
         a->sin_addr == b->sin_addr;
}

static void put(const char *s) {
  unsigned n = 0;
  while (s[n]) n++;
  sys_write(1, s, n);
}

static void put_hex32(uint32_t v) {
  static const char h[] = "0123456789abcdef";
  char b[10];
  b[0] = '0';
  b[1] = 'x';
  for (unsigned i = 0; i < 8; i++) {
    b[2 + i] = h[(v >> (28 - i * 4)) & 15];
  }
  sys_write(1, b, sizeof(b));
}

static void log_packet(const char *prefix, long len) {
  put(prefix);
  put(" len=");
  put_hex32((uint32_t)len);
  put("\n");
}

static int main(void) {
  uint8_t buf[2048];
  struct sockaddr_in listen_addr;
  struct sockaddr_in target_addr;
  struct sockaddr_in client_addr;
  int have_client = 0;

  int fd = (int)sys_socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
  if (fd < 0) {
    put("socket_failed\n");
    return 1;
  }

  int one = 1;
  sys_setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));

  mem_set(&listen_addr, 0, sizeof(listen_addr));
  listen_addr.sin_family = AF_INET;
  listen_addr.sin_port = bswap16((uint16_t)LISTEN_PORT);
  listen_addr.sin_addr = 0;

  if (sys_bind(fd, &listen_addr, sizeof(listen_addr)) < 0) {
    put("bind_failed\n");
    sys_close(fd);
    return 2;
  }

  mem_set(&target_addr, 0, sizeof(target_addr));
  target_addr.sin_family = AF_INET;
  target_addr.sin_port = bswap16((uint16_t)TARGET_PORT);
  target_addr.sin_addr = bswap32(TARGET_IP_BE);

  put("asus_udp_relay_ready listen=");
  put_hex32((uint32_t)LISTEN_PORT);
  put(" target=192.168.1.72:");
  put_hex32((uint32_t)TARGET_PORT);
  put("\n");

  for (;;) {
    struct sockaddr_in from;
    socklen_t from_len = sizeof(from);
    mem_set(&from, 0, sizeof(from));

    long n = sys_recvfrom(fd, buf, sizeof(buf), 0, &from, &from_len);
    if (n <= 0) {
      continue;
    }

    if (same_addr(&from, &target_addr)) {
      if (have_client) {
        sys_sendto(fd, buf, (unsigned)n, 0, &client_addr, sizeof(client_addr));
        log_packet("robot_to_client", n);
      } else {
        log_packet("robot_no_client", n);
      }
    } else {
      mem_copy(&client_addr, &from, sizeof(client_addr));
      have_client = 1;
      sys_sendto(fd, buf, (unsigned)n, 0, &target_addr, sizeof(target_addr));
      log_packet("client_to_robot", n);
    }
  }
}

void _start(void) {
  sys_exit(main());
}
