/*
 * Shift+Enter rewriter for lanjump.
 *
 * Apple Terminal sends the same CR for Enter and Shift+Enter. While Shift is
 * physically down, rewrite CR/LF to CSI-u Shift+Enter (ESC [ 13 ; 2 u).
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
rewrite_and_write(int fd, const unsigned char *buf, size_t n)
{
	unsigned char out[512];
	size_t o = 0;
	size_t i;

	for (i = 0; i < n; i++) {
		unsigned char b = buf[i];
		if ((b == '\r' || b == '\n') && shift_down()) {
			if (o > 0) {
				if (write_all(fd, out, o) < 0)
					return -1;
				o = 0;
			}
			if (write_all(fd, CSI_S_ENTER, CSI_S_ENTER_LEN) < 0)
				return -1;
		} else {
			if (o == sizeof out) {
				if (write_all(fd, out, o) < 0)
					return -1;
				o = 0;
			}
			out[o++] = b;
		}
	}
	if (o > 0)
		return write_all(fd, out, o);
	return 0;
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
