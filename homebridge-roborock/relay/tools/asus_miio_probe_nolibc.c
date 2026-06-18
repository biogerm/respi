#include <stdint.h>
#include <stddef.h>

#define SYS_EXIT 1
#define SYS_READ 3
#define SYS_WRITE 4
#define SYS_SOCKET 281
#define SYS_SENDTO 290
#define SYS_RECVFROM 292
#define SYS_SETSOCKOPT 294

#define AF_INET 2
#define SOCK_DGRAM 2
#define IPPROTO_UDP 17
#define SOL_SOCKET 1
#define SO_RCVTIMEO 20

typedef unsigned int socklen_t;

struct sockaddr_in {
  uint16_t sin_family;
  uint16_t sin_port;
  uint32_t sin_addr;
  uint8_t sin_zero[8];
};

struct timeval32 {
  int32_t tv_sec;
  int32_t tv_usec;
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

static long sys_read(int fd, void *buf, unsigned len) {
  return syscall6(SYS_READ, fd, (long)buf, len, 0, 0, 0);
}

static long sys_write(int fd, const void *buf, unsigned len) {
  return syscall6(SYS_WRITE, fd, (long)buf, len, 0, 0, 0);
}

static long sys_socket(int domain, int type, int protocol) {
  return syscall6(SYS_SOCKET, domain, type, protocol, 0, 0, 0);
}

static long sys_setsockopt(int fd, int level, int optname, const void *optval, unsigned optlen) {
  return syscall6(SYS_SETSOCKOPT, fd, level, optname, (long)optval, optlen, 0);
}

static long sys_sendto(int fd, const void *buf, unsigned len, int flags, const struct sockaddr_in *addr, unsigned addrlen) {
  return syscall6(SYS_SENDTO, fd, (long)buf, len, flags, (long)addr, addrlen);
}

static long sys_recvfrom(int fd, void *buf, unsigned len, int flags) {
  return syscall6(SYS_RECVFROM, fd, (long)buf, len, flags, 0, 0);
}

static void put(const char *s) {
  unsigned n = 0;
  while (s[n]) n++;
  sys_write(1, s, n);
}

static void putu(uint32_t v) {
  static const char h[] = "0123456789abcdef";
  char b[10];
  b[0] = '0';
  b[1] = 'x';
  for (unsigned i = 0; i < 8; i++) {
    b[2 + i] = h[(v >> (28 - i * 4)) & 15];
  }
  sys_write(1, b, 10);
}

static void puthex8(uint8_t v) {
  static const char h[] = "0123456789abcdef";
  char b[2];
  b[0] = h[v >> 4];
  b[1] = h[v & 15];
  sys_write(1, b, 2);
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

static int mem_eq(const uint8_t *a, const uint8_t *b, unsigned n) {
  uint8_t x = 0;
  while (n--) x |= *a++ ^ *b++;
  return x == 0;
}

static uint16_t bswap16(uint16_t x) {
  return (uint16_t)((x << 8) | (x >> 8));
}

static uint32_t bswap32(uint32_t x) {
  return ((x & 0xff) << 24) | ((x & 0xff00) << 8) | ((x & 0xff0000) >> 8) | ((x >> 24) & 0xff);
}

static uint32_t read_be32(const uint8_t *p) {
  return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3];
}

static void write_be16(uint8_t *p, uint16_t v) {
  p[0] = (uint8_t)(v >> 8);
  p[1] = (uint8_t)v;
}

static void write_be32(uint8_t *p, uint32_t v) {
  p[0] = (uint8_t)(v >> 24);
  p[1] = (uint8_t)(v >> 16);
  p[2] = (uint8_t)(v >> 8);
  p[3] = (uint8_t)v;
}

static int hexval(uint8_t c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

static int read_token(uint8_t token[16]) {
  uint8_t buf[96];
  long n = sys_read(0, buf, sizeof(buf));
  if (n < 32) return -1;
  int seen = 0;
  uint8_t tmp = 0;
  for (long i = 0; i < n && seen < 32; i++) {
    int hv = hexval(buf[i]);
    if (hv < 0) continue;
    if ((seen & 1) == 0) {
      tmp = (uint8_t)(hv << 4);
    } else {
      token[seen >> 1] = (uint8_t)(tmp | hv);
    }
    seen++;
  }
  return seen == 32 ? 0 : -1;
}

/* MD5 */
#define LEFTROTATE(x, c) (((x) << (c)) | ((x) >> (32 - (c))))

static const uint32_t md5_k[64] = {
  0xd76aa478,0xe8c7b756,0x242070db,0xc1bdceee,0xf57c0faf,0x4787c62a,0xa8304613,0xfd469501,
  0x698098d8,0x8b44f7af,0xffff5bb1,0x895cd7be,0x6b901122,0xfd987193,0xa679438e,0x49b40821,
  0xf61e2562,0xc040b340,0x265e5a51,0xe9b6c7aa,0xd62f105d,0x02441453,0xd8a1e681,0xe7d3fbc8,
  0x21e1cde6,0xc33707d6,0xf4d50d87,0x455a14ed,0xa9e3e905,0xfcefa3f8,0x676f02d9,0x8d2a4c8a,
  0xfffa3942,0x8771f681,0x6d9d6122,0xfde5380c,0xa4beea44,0x4bdecfa9,0xf6bb4b60,0xbebfbc70,
  0x289b7ec6,0xeaa127fa,0xd4ef3085,0x04881d05,0xd9d4d039,0xe6db99e5,0x1fa27cf8,0xc4ac5665,
  0xf4292244,0x432aff97,0xab9423a7,0xfc93a039,0x655b59c3,0x8f0ccc92,0xffeff47d,0x85845dd1,
  0x6fa87e4f,0xfe2ce6e0,0xa3014314,0x4e0811a1,0xf7537e82,0xbd3af235,0x2ad7d2bb,0xeb86d391
};

static const uint32_t md5_r[64] = {
  7,12,17,22,7,12,17,22,7,12,17,22,7,12,17,22,
  5,9,14,20,5,9,14,20,5,9,14,20,5,9,14,20,
  4,11,16,23,4,11,16,23,4,11,16,23,4,11,16,23,
  6,10,15,21,6,10,15,21,6,10,15,21,6,10,15,21
};

static void md5(const uint8_t *msg, unsigned len, uint8_t out[16]) {
  uint8_t data[256];
  unsigned new_len = len + 1;
  while ((new_len & 63) != 56) new_len++;
  mem_set(data, 0, sizeof(data));
  mem_copy(data, msg, len);
  data[len] = 0x80;
  uint32_t bits = len << 3;
  data[new_len + 0] = (uint8_t)bits;
  data[new_len + 1] = (uint8_t)(bits >> 8);
  data[new_len + 2] = (uint8_t)(bits >> 16);
  data[new_len + 3] = (uint8_t)(bits >> 24);

  uint32_t h0 = 0x67452301, h1 = 0xefcdab89, h2 = 0x98badcfe, h3 = 0x10325476;
  for (unsigned off = 0; off < new_len + 8; off += 64) {
    uint32_t w[16];
    for (unsigned i = 0; i < 16; i++) {
      unsigned j = off + i * 4;
      w[i] = (uint32_t)data[j] | ((uint32_t)data[j+1] << 8) | ((uint32_t)data[j+2] << 16) | ((uint32_t)data[j+3] << 24);
    }
    uint32_t a = h0, b = h1, c = h2, d = h3;
    for (unsigned i = 0; i < 64; i++) {
      uint32_t f, g;
      if (i < 16) { f = (b & c) | ((~b) & d); g = i; }
      else if (i < 32) { f = (d & b) | ((~d) & c); g = (5 * i + 1) & 15; }
      else if (i < 48) { f = b ^ c ^ d; g = (3 * i + 5) & 15; }
      else { f = c ^ (b | (~d)); g = (7 * i) & 15; }
      uint32_t temp = d;
      d = c;
      c = b;
      b = b + LEFTROTATE(a + f + md5_k[i] + w[g], md5_r[i]);
      a = temp;
    }
    h0 += a; h1 += b; h2 += c; h3 += d;
  }
  uint32_t hs[4] = {h0, h1, h2, h3};
  for (unsigned i = 0; i < 4; i++) {
    out[i*4+0] = (uint8_t)hs[i];
    out[i*4+1] = (uint8_t)(hs[i] >> 8);
    out[i*4+2] = (uint8_t)(hs[i] >> 16);
    out[i*4+3] = (uint8_t)(hs[i] >> 24);
  }
}

/* AES-128 CBC, compact table implementation */
static const uint8_t sbox[256] = {
0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,
0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,
0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,
0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,
0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,
0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,
0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,
0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,
0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,
0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,
0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,
0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,
0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,
0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,
0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,
0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16
};

static const uint8_t rsbox[256] = {
0x52,0x09,0x6a,0xd5,0x30,0x36,0xa5,0x38,0xbf,0x40,0xa3,0x9e,0x81,0xf3,0xd7,0xfb,
0x7c,0xe3,0x39,0x82,0x9b,0x2f,0xff,0x87,0x34,0x8e,0x43,0x44,0xc4,0xde,0xe9,0xcb,
0x54,0x7b,0x94,0x32,0xa6,0xc2,0x23,0x3d,0xee,0x4c,0x95,0x0b,0x42,0xfa,0xc3,0x4e,
0x08,0x2e,0xa1,0x66,0x28,0xd9,0x24,0xb2,0x76,0x5b,0xa2,0x49,0x6d,0x8b,0xd1,0x25,
0x72,0xf8,0xf6,0x64,0x86,0x68,0x98,0x16,0xd4,0xa4,0x5c,0xcc,0x5d,0x65,0xb6,0x92,
0x6c,0x70,0x48,0x50,0xfd,0xed,0xb9,0xda,0x5e,0x15,0x46,0x57,0xa7,0x8d,0x9d,0x84,
0x90,0xd8,0xab,0x00,0x8c,0xbc,0xd3,0x0a,0xf7,0xe4,0x58,0x05,0xb8,0xb3,0x45,0x06,
0xd0,0x2c,0x1e,0x8f,0xca,0x3f,0x0f,0x02,0xc1,0xaf,0xbd,0x03,0x01,0x13,0x8a,0x6b,
0x3a,0x91,0x11,0x41,0x4f,0x67,0xdc,0xea,0x97,0xf2,0xcf,0xce,0xf0,0xb4,0xe6,0x73,
0x96,0xac,0x74,0x22,0xe7,0xad,0x35,0x85,0xe2,0xf9,0x37,0xe8,0x1c,0x75,0xdf,0x6e,
0x47,0xf1,0x1a,0x71,0x1d,0x29,0xc5,0x89,0x6f,0xb7,0x62,0x0e,0xaa,0x18,0xbe,0x1b,
0xfc,0x56,0x3e,0x4b,0xc6,0xd2,0x79,0x20,0x9a,0xdb,0xc0,0xfe,0x78,0xcd,0x5a,0xf4,
0x1f,0xdd,0xa8,0x33,0x88,0x07,0xc7,0x31,0xb1,0x12,0x10,0x59,0x27,0x80,0xec,0x5f,
0x60,0x51,0x7f,0xa9,0x19,0xb5,0x4a,0x0d,0x2d,0xe5,0x7a,0x9f,0x93,0xc9,0x9c,0xef,
0xa0,0xe0,0x3b,0x4d,0xae,0x2a,0xf5,0xb0,0xc8,0xeb,0xbb,0x3c,0x83,0x53,0x99,0x61,
0x17,0x2b,0x04,0x7e,0xba,0x77,0xd6,0x26,0xe1,0x69,0x14,0x63,0x55,0x21,0x0c,0x7d
};

static uint8_t xtime(uint8_t x) { return (uint8_t)((x << 1) ^ (((x >> 7) & 1) * 0x1b)); }
static uint8_t mul(uint8_t x, uint8_t y) {
  uint8_t r = 0;
  while (y) {
    if (y & 1) r ^= x;
    x = xtime(x);
    y >>= 1;
  }
  return r;
}

static void key_expansion(const uint8_t *key, uint8_t *rk) {
  static const uint8_t rcon[11] = {0,1,2,4,8,16,32,64,128,27,54};
  for (unsigned i = 0; i < 16; i++) rk[i] = key[i];
  unsigned bytes = 16, rci = 1;
  uint8_t t[4];
  while (bytes < 176) {
    for (unsigned i = 0; i < 4; i++) t[i] = rk[bytes - 4 + i];
    if ((bytes & 15) == 0) {
      uint8_t x = t[0]; t[0] = sbox[t[1]] ^ rcon[rci++]; t[1] = sbox[t[2]]; t[2] = sbox[t[3]]; t[3] = sbox[x];
    }
    for (unsigned i = 0; i < 4; i++) { rk[bytes] = rk[bytes - 16] ^ t[i]; bytes++; }
  }
}

static void add_round_key(uint8_t *s, const uint8_t *rk) { for (unsigned i = 0; i < 16; i++) s[i] ^= rk[i]; }
static void sub_bytes(uint8_t *s) { for (unsigned i = 0; i < 16; i++) s[i] = sbox[s[i]]; }
static void inv_sub_bytes(uint8_t *s) { for (unsigned i = 0; i < 16; i++) s[i] = rsbox[s[i]]; }

static void shift_rows(uint8_t *s) {
  uint8_t t;
  t=s[1]; s[1]=s[5]; s[5]=s[9]; s[9]=s[13]; s[13]=t;
  t=s[2]; s[2]=s[10]; s[10]=t; t=s[6]; s[6]=s[14]; s[14]=t;
  t=s[3]; s[3]=s[15]; s[15]=s[11]; s[11]=s[7]; s[7]=t;
}

static void inv_shift_rows(uint8_t *s) {
  uint8_t t;
  t=s[13]; s[13]=s[9]; s[9]=s[5]; s[5]=s[1]; s[1]=t;
  t=s[2]; s[2]=s[10]; s[10]=t; t=s[6]; s[6]=s[14]; s[14]=t;
  t=s[3]; s[3]=s[7]; s[7]=s[11]; s[11]=s[15]; s[15]=t;
}

static void mix_columns(uint8_t *s) {
  for (unsigned i = 0; i < 4; i++) {
    uint8_t *c = s + i*4;
    uint8_t a = c[0], b = c[1], d = c[2], e = c[3];
    uint8_t x = a ^ b ^ d ^ e;
    c[0] ^= x ^ xtime(a ^ b);
    c[1] ^= x ^ xtime(b ^ d);
    c[2] ^= x ^ xtime(d ^ e);
    c[3] ^= x ^ xtime(e ^ a);
  }
}

static void inv_mix_columns(uint8_t *s) {
  for (unsigned i = 0; i < 4; i++) {
    uint8_t *c = s + i*4;
    uint8_t a = c[0], b = c[1], d = c[2], e = c[3];
    c[0] = mul(a,14) ^ mul(b,11) ^ mul(d,13) ^ mul(e,9);
    c[1] = mul(a,9) ^ mul(b,14) ^ mul(d,11) ^ mul(e,13);
    c[2] = mul(a,13) ^ mul(b,9) ^ mul(d,14) ^ mul(e,11);
    c[3] = mul(a,11) ^ mul(b,13) ^ mul(d,9) ^ mul(e,14);
  }
}

static void aes_encrypt_block(uint8_t *s, const uint8_t *rk) {
  add_round_key(s, rk);
  for (unsigned r = 1; r < 10; r++) {
    sub_bytes(s); shift_rows(s); mix_columns(s); add_round_key(s, rk + r*16);
  }
  sub_bytes(s); shift_rows(s); add_round_key(s, rk + 160);
}

static void aes_decrypt_block(uint8_t *s, const uint8_t *rk) {
  add_round_key(s, rk + 160);
  for (unsigned r = 9; r > 0; r--) {
    inv_shift_rows(s); inv_sub_bytes(s); add_round_key(s, rk + r*16); inv_mix_columns(s);
  }
  inv_shift_rows(s); inv_sub_bytes(s); add_round_key(s, rk);
}

static void aes_cbc_encrypt(uint8_t *buf, unsigned len, const uint8_t *key, const uint8_t *iv0) {
  uint8_t rk[176], iv[16];
  key_expansion(key, rk);
  mem_copy(iv, iv0, 16);
  for (unsigned off = 0; off < len; off += 16) {
    for (unsigned i = 0; i < 16; i++) buf[off+i] ^= iv[i];
    aes_encrypt_block(buf + off, rk);
    mem_copy(iv, buf + off, 16);
  }
}

static void aes_cbc_decrypt(uint8_t *buf, unsigned len, const uint8_t *key, const uint8_t *iv0) {
  uint8_t rk[176], iv[16], prev[16];
  key_expansion(key, rk);
  mem_copy(iv, iv0, 16);
  for (unsigned off = 0; off < len; off += 16) {
    mem_copy(prev, buf + off, 16);
    aes_decrypt_block(buf + off, rk);
    for (unsigned i = 0; i < 16; i++) buf[off+i] ^= iv[i];
    mem_copy(iv, prev, 16);
  }
}

static void derive_keys(const uint8_t token[16], uint8_t key[16], uint8_t iv[16]) {
  uint8_t tmp[32];
  md5(token, 16, key);
  mem_copy(tmp, key, 16);
  mem_copy(tmp + 16, token, 16);
  md5(tmp, 32, iv);
}

static void print_json_sanitized(const uint8_t *buf, unsigned len) {
  put("response=");
  for (unsigned i = 0; i < len; i++) {
    uint8_t c = buf[i];
    if (c >= 32 && c <= 126) sys_write(1, &c, 1);
    else sys_write(1, ".", 1);
  }
  put("\n");
}

void _start(void) {
  put("asus_miio_probe_start\n");
  uint8_t token[16];
  if (read_token(token) != 0) { put("token_read_error\n"); sys_exit(2); }
  put("token_ok\n");

  uint8_t key[16], iv[16];
  derive_keys(token, key, iv);

  long fd = sys_socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
  if (fd < 0) { put("socket_error\n"); sys_exit(3); }
  struct timeval32 tv; tv.tv_sec = 5; tv.tv_usec = 0;
  sys_setsockopt((int)fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

  struct sockaddr_in addr;
  mem_set(&addr, 0, sizeof(addr));
  addr.sin_family = AF_INET;
  addr.sin_port = bswap16(54321);
  addr.sin_addr = bswap32(0xC0A80148u); /* 192.168.1.72 */

  uint8_t pkt[256], resp[512];
  mem_set(pkt, 0xff, 32);
  pkt[0] = 0x21; pkt[1] = 0x31; write_be16(pkt + 2, 32);
  long s = sys_sendto((int)fd, pkt, 32, 0, &addr, sizeof(addr));
  if (s != 32) { put("handshake_send_error\n"); sys_exit(4); }
  long n = sys_recvfrom((int)fd, resp, sizeof(resp), 0);
  if (n < 32) { put("handshake_timeout_or_short\n"); sys_exit(5); }
  uint32_t did = read_be32(resp + 8);
  uint32_t stamp = read_be32(resp + 12);
  put("handshake_ok device_id="); putu(did); put(" stamp="); putu(stamp); put("\n");

  const char json[] = "{\"id\":1,\"method\":\"__codex_noop_probe__\",\"params\":[]}";
  unsigned json_len = sizeof(json) - 1;
  unsigned enc_len = json_len;
  unsigned pad = 16 - (enc_len & 15);
  enc_len += pad;
  mem_set(pkt, 0, sizeof(pkt));
  mem_copy(pkt + 32, json, json_len);
  for (unsigned i = 0; i < pad; i++) pkt[32 + json_len + i] = (uint8_t)pad;
  aes_cbc_encrypt(pkt + 32, enc_len, key, iv);

  pkt[0] = 0x21; pkt[1] = 0x31; write_be16(pkt + 2, (uint16_t)(32 + enc_len));
  pkt[4] = pkt[5] = pkt[6] = pkt[7] = 0;
  write_be32(pkt + 8, did);
  write_be32(pkt + 12, stamp);
  uint8_t mdin[256], digest[16];
  mem_copy(mdin, pkt, 16);
  mem_copy(mdin + 16, token, 16);
  mem_copy(mdin + 32, pkt + 32, enc_len);
  md5(mdin, 32 + enc_len, digest);
  mem_copy(pkt + 16, digest, 16);
  s = sys_sendto((int)fd, pkt, 32 + enc_len, 0, &addr, sizeof(addr));
  put("probe_sent_len="); putu((uint32_t)s); put("\n");
  if (s != (long)(32 + enc_len)) { put("probe_send_error\n"); sys_exit(6); }

  n = sys_recvfrom((int)fd, resp, sizeof(resp), 0);
  if (n < 0) { put("probe_timeout\n"); sys_exit(10); }
  put("probe_reply_len="); putu((uint32_t)n); put("\n");
  if (n < 32) { put("probe_reply_short\n"); sys_exit(11); }
  unsigned renc_len = (unsigned)n - 32;
  if (renc_len == 0) { put("probe_reply_handshake_only\n"); sys_exit(12); }
  mem_copy(mdin, resp, 16);
  mem_copy(mdin + 16, token, 16);
  mem_copy(mdin + 32, resp + 32, renc_len);
  md5(mdin, 32 + renc_len, digest);
  if (!mem_eq(resp + 16, digest, 16)) {
    put("probe_reply_invalid_checksum got=");
    for (unsigned i = 0; i < 4; i++) puthex8(resp[16+i]);
    put("\n");
    sys_exit(13);
  }
  put("probe_reply_checksum_ok\n");
  aes_cbc_decrypt(resp + 32, renc_len, key, iv);
  unsigned plain_len = renc_len;
  uint8_t last = resp[32 + plain_len - 1];
  if (last > 0 && last <= 16 && last <= plain_len) plain_len -= last;
  print_json_sanitized(resp + 32, plain_len);
  sys_exit(0);
}
