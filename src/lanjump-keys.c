/*
 * Shift+Enter rewriter for lanjump.
 *
 * Apple Terminal sends the same CR for Enter and Shift+Enter. While Shift is
 * physically down, rewrite CR/LF to CSI-u Shift+Enter (ESC [ 13 ; 2 u).
 *
 * Ghostty already emits that CSI-u sequence. Grok often does not parse it
 * (ESC is consumed, "[13;2u" is inserted as text). Translate CSI-u
 * Shift+Enter to Alt+Enter (ESC CR), which Grok always treats as newline.
 * CR/LF that already follows ESC is left alone (Ghostty Alt+Enter keybind).
 *
 * Reads STDIN / writes STDOUT only — never /dev/tty — so it can sit inside
 * `grok wrap` without stealing the real terminal (that nesting hung).
 */

#include <CoreGraphics/CoreGraphics.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>
#include <util.h>

#define kVK_Shift 56
#define kVK_RightShift 60

static const char CSI_S_ENTER[] = "\x1b[13;2u";
static const size_t CSI_S_ENTER_LEN = sizeof(CSI_S_ENTER) - 1;
static const char ALT_ENTER[] = "\x1b\r";
static const size_t ALT_ENTER_LEN = sizeof(ALT_ENTER) - 1;

enum { ST_NORM = 0, ST_ESC, ST_CSI };

static int rw_st = ST_NORM;
static unsigned char csi[24];
static size_t csi_len;

static pid_t child = -1;
static int master_fd = -1;
static int in_fd = STDIN_FILENO;
static struct termios orig_termios;
static int orig_termios_valid = 0;

static void
restore_tty(void)
{
	if (orig_termios_valid)
		(void)tcsetattr(in_fd, TCSANOW, &orig_termios);
}

static int
shift_down(void)
{
	const char *force = getenv("LANJUMP_FORCE_SHIFT");

	if (force != NULL && force[0] == '1' && force[1] == '\0')
		return 1;
	return CGEventSourceKeyState(kCGEventSourceStateCombinedSessionState,
	           (CGKeyCode)kVK_Shift) ||
	       CGEventSourceKeyState(kCGEventSourceStateCombinedSessionState,
	           (CGKeyCode)kVK_RightShift);
}

static int
write_all(int fd, const void *buf, size_t n)
{
	const unsigned char *p = buf;

	while (n > 0) {
		ssize_t w = write(fd, p, n);
		if (w < 0) {
			if (errno == EINTR)
				continue;
			return -1;
		}
		p += (size_t)w;
		n -= (size_t)w;
	}
	return 0;
}

static int
flush_out(int fd, unsigned char *out, size_t *o)
{
	if (*o == 0)
		return 0;
	if (write_all(fd, out, *o) < 0)
		return -1;
	*o = 0;
	return 0;
}

static int
emit_bytes(int fd, unsigned char *out, size_t *o, const void *p, size_t n)
{
	const unsigned char *s = p;
	size_t i;

	for (i = 0; i < n; i++) {
		if (*o == 512 && flush_out(fd, out, o) < 0)
			return -1;
		out[(*o)++] = s[i];
	}
	return 0;
}

static int
emit_byte(int fd, unsigned char *out, size_t *o, unsigned char b)
{
	return emit_bytes(fd, out, o, &b, 1);
}

static int
csi_final(unsigned char b)
{
	return b >= 0x40 && b <= 0x7e;
}

/* [13;2u / [13;2;1u / [13;2;2u — not release (;3u). */
static int
csi_shift_enter(const unsigned char *s, size_t n)
{
	if (n < 6 || s[0] != '[' || s[n - 1] != 'u')
		return 0;
	if (!(s[1] == '1' && s[2] == '3' && s[3] == ';' && s[4] == '2'))
		return 0;
	if (n == 6)
		return 1;
	if (n == 8 && s[5] == ';' && (s[6] == '1' || s[6] == '2'))
		return 1;
	return 0;
}

static int
rewrite_and_write(int fd, const unsigned char *buf, size_t n)
{
	unsigned char out[512];
	size_t o = 0;
	size_t i;

	for (i = 0; i < n; i++) {
		unsigned char b = buf[i];

		if (rw_st == ST_NORM) {
			if (b == 0x1b) {
				rw_st = ST_ESC;
				continue;
			}
			if ((b == '\r' || b == '\n') && shift_down()) {
				if (emit_bytes(fd, out, &o, CSI_S_ENTER,
				        CSI_S_ENTER_LEN) < 0)
					return -1;
				continue;
			}
			if (emit_byte(fd, out, &o, b) < 0)
				return -1;
			continue;
		}

		if (rw_st == ST_ESC) {
			if (b == '[') {
				rw_st = ST_CSI;
				csi[0] = '[';
				csi_len = 1;
				continue;
			}
			if (emit_byte(fd, out, &o, 0x1b) < 0)
				return -1;
			rw_st = ST_NORM;
			if (b == 0x1b) {
				rw_st = ST_ESC;
				continue;
			}
			if (b == '\r' || b == '\n') {
				if (emit_byte(fd, out, &o, b) < 0)
					return -1;
				continue;
			}
			i--;
			continue;
		}

		if (csi_len < sizeof csi)
			csi[csi_len++] = b;
		if (csi_len == sizeof csi || csi_final(b)) {
			if (csi_shift_enter(csi, csi_len)) {
				if (emit_bytes(fd, out, &o, ALT_ENTER,
				        ALT_ENTER_LEN) < 0)
					return -1;
			} else {
				if (emit_byte(fd, out, &o, 0x1b) < 0)
					return -1;
				if (emit_bytes(fd, out, &o, csi, csi_len) < 0)
					return -1;
			}
			rw_st = ST_NORM;
			csi_len = 0;
		}
	}
	return flush_out(fd, out, &o);
}

static void
on_winch(int sig)
{
	struct winsize ws;

	(void)sig;
	if (master_fd >= 0 && ioctl(in_fd, TIOCGWINSZ, &ws) == 0)
		(void)ioctl(master_fd, TIOCSWINSZ, &ws);
}

static void
on_fwd(int sig)
{
	if (child > 0)
		(void)kill(child, sig);
}

int
main(int argc, char **argv)
{
	struct winsize ws;
	struct termios raw;
	struct pollfd fds[2];
	unsigned char buf[512];
	int status = 0;

	if (argc >= 2 && strcmp(argv[1], "--selftest") == 0) {
		printf("ok shift=%d\n", shift_down() ? 1 : 0);
		return 0;
	}
	if (argc >= 2 && strcmp(argv[1], "--rewrite") == 0) {
		unsigned char rbuf[512];
		ssize_t n;

		while ((n = read(STDIN_FILENO, rbuf, sizeof rbuf)) > 0) {
			if (rewrite_and_write(STDOUT_FILENO, rbuf, (size_t)n) < 0)
				return 1;
		}
		return n < 0 ? 1 : 0;
	}
	if (argc < 2) {
		fprintf(stderr,
		    "usage: lanjump-keys [--selftest|--rewrite] <command> [args...]\n");
		return 2;
	}

	if (!isatty(in_fd)) {
		execvp(argv[1], argv + 1);
		perror(argv[1]);
		return 127;
	}

	if (tcgetattr(in_fd, &orig_termios) == 0)
		orig_termios_valid = 1;
	atexit(restore_tty);

	if (ioctl(in_fd, TIOCGWINSZ, &ws) < 0) {
		memset(&ws, 0, sizeof ws);
		ws.ws_row = 24;
		ws.ws_col = 80;
	}

	child = forkpty(&master_fd, NULL, NULL, &ws);
	if (child < 0) {
		perror("forkpty");
		return 1;
	}
	if (child == 0) {
		execvp(argv[1], argv + 1);
		perror(argv[1]);
		_exit(127);
	}

	raw = orig_termios;
	cfmakeraw(&raw);
	raw.c_cc[VMIN] = 1;
	raw.c_cc[VTIME] = 0;
	if (tcsetattr(in_fd, TCSANOW, &raw) < 0) {
		perror("tcsetattr");
		(void)kill(child, SIGTERM);
		return 1;
	}

	signal(SIGWINCH, on_winch);
	signal(SIGTERM, on_fwd);
	signal(SIGINT, on_fwd);
	signal(SIGHUP, on_fwd);

	for (;;) {
		pid_t r = waitpid(child, &status, WNOHANG);
		if (r == child) {
			child = -1;
			break;
		}

		fds[0].fd = in_fd;
		fds[0].events = POLLIN;
		fds[1].fd = master_fd;
		fds[1].events = POLLIN;
		if (poll(fds, 2, 200) < 0) {
			if (errno == EINTR)
				continue;
			break;
		}

		if (fds[0].revents & POLLIN) {
			ssize_t n = read(in_fd, buf, sizeof buf);
			if (n < 0) {
				if (errno == EINTR)
					continue;
				break;
			}
			if (n == 0)
				break;
			if (rewrite_and_write(master_fd, buf, (size_t)n) < 0)
				break;
		}
		if (fds[1].revents & POLLIN) {
			ssize_t n = read(master_fd, buf, sizeof buf);
			if (n < 0) {
				if (errno == EINTR)
					continue;
				break;
			}
			if (n == 0)
				break;
			if (write_all(STDOUT_FILENO, buf, (size_t)n) < 0)
				break;
		}
		if ((fds[0].revents | fds[1].revents) & (POLLHUP | POLLERR | POLLNVAL))
			break;
	}

	if (child > 0) {
		(void)waitpid(child, &status, 0);
		child = -1;
	}
	restore_tty();
	orig_termios_valid = 0;

	if (WIFEXITED(status))
		return WEXITSTATUS(status);
	if (WIFSIGNALED(status))
		return 128 + WTERMSIG(status);
	return 0;
}
