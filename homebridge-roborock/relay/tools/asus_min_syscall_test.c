static long sys_exit(long code) {
  register long r0 asm("r0") = code;
  register long r7 asm("r7") = 1;
  asm volatile("svc 0" : : "r"(r0), "r"(r7) : "memory");
  return 0;
}

void _start(void) {
  sys_exit(7);
}
