/* Side-channel tracer for the #466 fake dns-sd.
 * stdout lines match the selftest simulator. Timestamps go only to
 * LJ_DNS_SD_TRACE. Each stdout line and its "line" trace are one
 * SIGTERM-blocked section: a missing "line" event means that stdout
 * write did not finish. "sigterm" is when this child got the signal,
 * not when the parent run_timed decided to stop.
 * proc_start qos_* is this dns-sd child's pthread_get_qos_class_np result.
 * It is not the parent shell's class and not the effective timer policy.
 * The tracer only reads that value.
 */
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <pthread.h>
#include <pthread/qos.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static int trace_fd = -1;
static volatile sig_atomic_t in_sleep = 0;

static void now_ns(uint64_t *mono, uint64_t *real) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  *mono = (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
  clock_gettime(CLOCK_REALTIME, &ts);
  *real = (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

static int append_str(char *dst, int n, int cap, const char *s) {
  if (!s) return n;
  while (*s && n < cap - 1) dst[n++] = *s++;
  return n;
}

static int append_u64(char *dst, int n, int cap, uint64_t v) {
  char tmp[32];
  int i = 0;
  int j;
  if (v == 0) return append_str(dst, n, cap, "0");
  while (v && i < (int)sizeof tmp) {
    tmp[i++] = (char)('0' + (v % 10));
    v /= 10;
  }
  for (j = i - 1; j >= 0 && n < cap - 1; j--) dst[n++] = tmp[j];
  return n;
}

static void trace_write(const char *event, const char *extra) {
  char buf[1400];
  uint64_t mono = 0;
  uint64_t real = 0;
  int n = 0;
  if (trace_fd < 0) return;
  now_ns(&mono, &real);
  n = append_u64(buf, n, (int)sizeof buf, mono);
  n = append_str(buf, n, (int)sizeof buf, " ");
  n = append_u64(buf, n, (int)sizeof buf, real);
  n = append_str(buf, n, (int)sizeof buf, " ");
  n = append_u64(buf, n, (int)sizeof buf, (uint64_t)getpid());
  n = append_str(buf, n, (int)sizeof buf, " ");
  n = append_str(buf, n, (int)sizeof buf, event);
  if (extra && extra[0]) {
    n = append_str(buf, n, (int)sizeof buf, " ");
    n = append_str(buf, n, (int)sizeof buf, extra);
  }
  if (n < (int)sizeof buf - 1) buf[n++] = '\n';
  (void)write(trace_fd, buf, (size_t)n);
}

static void trace_line(const char *event, const char *extra) {
  sigset_t set;
  sigset_t old;
  sigemptyset(&set);
  sigaddset(&set, SIGTERM);
  sigprocmask(SIG_BLOCK, &set, &old);
  trace_write(event, extra);
  sigprocmask(SIG_SETMASK, &old, NULL);
}

static void on_term(int sig) {
  char extra[64];
  int n = 0;
  const char *flag = in_sleep ? "during_sleep=1" : "during_sleep=0";
  (void)sig;
  n = append_str(extra, n, (int)sizeof extra, flag);
  extra[n] = 0;
  trace_write("sigterm", extra);
  signal(SIGTERM, SIG_DFL);
  raise(SIGTERM);
}

static void trace_open(void) {
  const char *path = getenv("LJ_DNS_SD_TRACE");
  struct sigaction sa;
  if (!path || !path[0]) return;
  trace_fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0644);
  memset(&sa, 0, sizeof sa);
  sa.sa_handler = on_term;
  sigemptyset(&sa.sa_mask);
  sa.sa_flags = 0;
  sigaction(SIGTERM, &sa, NULL);
}

static void hold(void) {
  trace_line("hold", "");
  for (;;) pause();
}

static void chomp(char *s) {
  size_t n = strlen(s);
  while (n && (s[n - 1] == '\n' || s[n - 1] == '\r')) s[--n] = 0;
}

static int is_uint(const char *s) {
  if (!s || !*s) return 0;
  for (; *s; s++) if (!isdigit((unsigned char)*s)) return 0;
  return 1;
}

static void sleep_ms(const char *ms) {
  unsigned v;
  uint64_t t0 = 0;
  uint64_t t1 = 0;
  uint64_t ignored = 0;
  char extra[80];
  if (!ms || !is_uint(ms)) return;
  v = (unsigned)atoi(ms);
  if (!v) {
    trace_line("sleep_skip", "requested_ms=0");
    return;
  }
  snprintf(extra, sizeof extra, "requested_ms=%u", v);
  trace_line("sleep_begin", extra);
  now_ns(&t0, &ignored);
  in_sleep = 1;
  usleep(v * 1000u);
  in_sleep = 0;
  now_ns(&t1, &ignored);
  snprintf(extra, sizeof extra, "elapsed_ns=%" PRIu64, t1 - t0);
  trace_line("sleep_end", extra);
}

/* puts/fflush and the matching trace record share one SIGTERM block. */
static void emit_and_trace(const char *text) {
  sigset_t set;
  sigset_t old;
  char extra[1200];
  int n = 0;
  const char *s;
  sigemptyset(&set);
  sigaddset(&set, SIGTERM);
  sigprocmask(SIG_BLOCK, &set, &old);
  puts(text);
  fflush(stdout);
  n = append_str(extra, n, (int)sizeof extra, "text=");
  for (s = text; *s && n < (int)sizeof extra - 1; s++) {
    if (*s == '\n' || *s == '\r') continue;
    extra[n++] = *s;
  }
  extra[n] = 0;
  trace_write("line", extra);
  sigprocmask(SIG_SETMASK, &old, NULL);
}

static void browse(void) {
  const char *path = getenv("LJ_DNS_SD_BROWSE");
  FILE *f;
  char buf[1024];
  const char *header =
      "Timestamp     A/R    Flags  if Domain               Service Type         Instance Name";
  emit_and_trace(header);
  f = (path && *path) ? fopen(path, "r") : NULL;
  if (f) {
    while (fgets(buf, sizeof buf, f)) {
      char *flags, *name, *tab;
      char shown[1200];
      chomp(buf);
      if (!buf[0]) continue;
      tab = strchr(buf, '\t');
      if (!tab) continue;
      *tab = 0;
      flags = buf;
      name = tab + 1;
      if (is_uint(flags) && strchr(name, '\t')) {
        char *tab2 = strchr(name, '\t');
        sleep_ms(flags);
        *tab2 = 0;
        flags = name;
        name = tab2 + 1;
      }
      snprintf(shown, sizeof shown,
               " 9:00:00.000  Add        %s  1 local.               _ssh._tcp.           %s",
               flags, name);
      emit_and_trace(shown);
    }
    fclose(f);
  }
  hold();
}

static int resolve_one(const char *inst) {
  const char *path = getenv("LJ_DNS_SD_RESOLVE");
  FILE *f;
  char buf[2048];
  if (!path || !(f = fopen(path, "r"))) return 0;
  while (fgets(buf, sizeof buf, f)) {
    char *name, *delay, *line, *tab, *tab2;
    chomp(buf);
    tab = strchr(buf, '\t');
    if (!tab) continue;
    *tab = 0;
    name = buf;
    delay = tab + 1;
    tab2 = strchr(delay, '\t');
    if (!tab2) continue;
    *tab2 = 0;
    line = tab2 + 1;
    if (strcmp(name, inst) != 0) continue;
    fclose(f);
    sleep_ms(delay);
    if (line[0] && strcmp(line, "-") != 0) {
      emit_and_trace(line);
      return 1;
    }
    return 0;
  }
  fclose(f);
  return 0;
}

static void emit_addrs(const char *host, const char *spec) {
  char *copy = strdup(spec ? spec : "");
  char *save = NULL;
  char *tok;
  int n = 0;
  int saw = 0;
  if (!copy) return;
  tok = strtok_r(copy, "|,", &save);
  while (tok) {
    while (*tok == ' ') tok++;
    if (saw && is_uint(tok)) {
      sleep_ms(tok);
    } else if (tok[0]) {
      char shown[1200];
      n++;
      snprintf(shown, sizeof shown, " 9:00:01.%03d  Add   %d %s     %s    120", n, n, host, tok);
      emit_and_trace(shown);
      saw = 1;
    }
    tok = strtok_r(NULL, "|,", &save);
  }
  free(copy);
}

static void addrs(const char *host) {
  const char *path = getenv("LJ_DNS_SD_ADDR");
  FILE *f;
  char buf[2048];
  if (!path || !(f = fopen(path, "r"))) {
    hold();
    return;
  }
  while (fgets(buf, sizeof buf, f)) {
    char *name, *delay, *spec, *tab, *tab2;
    chomp(buf);
    tab = strchr(buf, '\t');
    if (!tab) continue;
    *tab = 0;
    name = buf;
    delay = tab + 1;
    tab2 = strchr(delay, '\t');
    if (!tab2) continue;
    *tab2 = 0;
    spec = tab2 + 1;
    if (strcmp(name, host) != 0) continue;
    fclose(f);
    sleep_ms(delay);
    emit_addrs(host, spec);
    hold();
    return;
  }
  fclose(f);
  hold();
}

static void stamp_and_exit(int argc, char **argv) {
  char extra[1200];
  int i;
  int n = 0;
  for (i = 2; i < argc && n < (int)sizeof extra - 1; i++) {
    const char *s;
    if (i > 2 && n < (int)sizeof extra - 1) extra[n++] = ' ';
    for (s = argv[i]; *s && n < (int)sizeof extra - 1; s++) {
      if (*s == '\n' || *s == '\r') continue;
      extra[n++] = *s;
    }
  }
  extra[n] = 0;
  trace_line("stamp", extra);
}

int main(int argc, char **argv) {
  int i;
  char argv_extra[1200];
  int n = 0;
  setvbuf(stdout, NULL, _IONBF, 0);
  if (argc == 2 && strcmp(argv[1], "--self-check") == 0) {
    puts("lanjump-490-trace");
    return 0;
  }
  trace_open();
  if (argc >= 2 && strcmp(argv[1], "--stamp") == 0) {
    stamp_and_exit(argc, argv);
    return 0;
  }
  n = append_str(argv_extra, n, (int)sizeof argv_extra, "argv=");
  for (i = 0; i < argc && n < (int)sizeof argv_extra - 1; i++) {
    const char *s;
    if (i && n < (int)sizeof argv_extra - 1) argv_extra[n++] = ' ';
    for (s = argv[i]; *s && n < (int)sizeof argv_extra - 1; s++) argv_extra[n++] = *s;
  }
  {
    qos_class_t cls = 0;
    int rel = 0;
    int qrc = pthread_get_qos_class_np(pthread_self(), &cls, &rel);
    char qos[80];
    snprintf(qos, sizeof qos, " qos_rc=%d qos_class=%d qos_rel=%d", qrc, (int)cls, rel);
    n = append_str(argv_extra, n, (int)sizeof argv_extra, qos);
  }
  argv_extra[n] = 0;
  trace_line("proc_start", argv_extra);
  if (argc >= 2 && strcmp(argv[1], "-B") == 0) browse();
  else if (argc >= 3 && strcmp(argv[1], "-L") == 0) {
    if (resolve_one(argv[2])) hold();
    return 0;
  } else if (argc >= 4 && strcmp(argv[1], "-G") == 0) addrs(argv[3]);
  hold();
  return 0;
}
