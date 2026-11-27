/* holdfile: holds a file open across a card swap. Opens <file> and reads its
 * first block, then waits until <go> exists, then reads the whole file again
 * through the same handle and writes it to <copy>.
 *
 *   Run OUT:holdfile CF0:payload.bin OUT:held.bin OUT:go >OUT:hold.txt
 *
 * Prints "held: <bytes>" or a FAIL line with the DOS error. Gives up when
 * <go> does not show up within two minutes.
 *
 * Build: make holdfile
 */
#include <exec/types.h>
#include <dos/dos.h>
#include <proto/exec.h>
#include <proto/dos.h>

static const char ver[] = "$VER: holdfile 1.0 (17.11.2026)";

static UBYTE buf[4096];

static int fail(const char *what)
{
    LONG err = IoErr();
    char msg[80];

    Fault(err, NULL, msg, sizeof(msg));
    Printf("FAIL: %s: %ld %s\n", (LONG)what, err, (LONG)msg);
    return 20;
}

int main(int argc, char **argv)
{
    BPTR fh, out, go;
    LONG n, total = 0, wait;
    int rc = 0;

    if (argc != 4) {
        PutStr("usage: holdfile <file> <copy> <go>\n");
        return 20;
    }
    fh = Open((STRPTR)argv[1], MODE_OLDFILE);
    if (!fh)
        return fail("open");
    if (Read(fh, buf, sizeof(buf)) <= 0) {
        rc = fail("first read");
        goto close;
    }
    PutStr("open\n");
    Flush(Output());
    for (wait = 0; !(go = Lock((STRPTR)argv[3], ACCESS_READ)); wait++) {
        if (wait == 120 * 5) {
            PutStr("FAIL: no go\n");
            rc = 20;
            goto close;
        }
        Delay(TICKS_PER_SECOND / 5);
    }
    UnLock(go);
    out = Open((STRPTR)argv[2], MODE_NEWFILE);
    if (!out) {
        rc = fail("create the copy");
        goto close;
    }
    if (Seek(fh, 0, OFFSET_BEGINNING) == -1)
        rc = fail("seek after the swap");
    else {
        while ((n = Read(fh, buf, sizeof(buf))) > 0) {
            Write(out, buf, n);
            total += n;
        }
        if (n < 0)
            rc = fail("read after the swap");
        else
            Printf("held: %ld\n", total);
    }
    Close(out);
close:
    Close(fh);
    return rc;
}
