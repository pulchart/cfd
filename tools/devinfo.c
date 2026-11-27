/* devinfo: DOS device nodes with the stack and priority they carry and those
 * of their running handler task, to check STACK_<fs>/PRI_<fs> in cfd.prefs.
 *
 *   devinfo        all devices
 *   devinfo CF0:   one device
 *
 * Build: make devinfo
 */
#include <exec/types.h>
#include <exec/tasks.h>
#include <exec/ports.h>
#include <dos/dos.h>
#include <dos/dosextens.h>
#include <dos/filehandler.h>
#include <proto/exec.h>
#include <proto/dos.h>
#include <string.h>

static const char ver[] = "$VER: devinfo 1.0 (07.11.2026)";

#define MAXDEV 64

struct row {
    char  name[32];
    char  dostype[20];
    LONG  pri;
    ULONG stack;
    int   running;
    LONG  tpri;
    ULONG tstack;
};

static struct row rows[MAXDEV];

static int same(const char *a, const char *b)
{
    for (;; a++, b++) {
        char x = *a, y = *b;
        if (x >= 'a' && x <= 'z')
            x -= 32;
        if (y >= 'a' && y <= 'z')
            y -= 32;
        if (x != y)
            return 0;
        if (!x)
            return 1;
    }
}

static void bstr(BPTR b, char *out, int max)
{
    UBYTE *p = BADDR(b);
    int n = 0;

    if (p) {
        n = *p;
        if (n > max - 1)
            n = max - 1;
        memcpy(out, p + 1, n);
    }
    out[n] = 0;
}

/* "FAT\1" style; empty when the node has no file system environment */
static void dostype(struct DeviceNode *dn, char *out)
{
    struct FileSysStartupMsg *fssm;
    struct DosEnvec *de;
    ULONG t;
    int i, n = 0;

    out[0] = 0;
    if ((ULONG)dn->dn_Startup <= 64)
        return;
    fssm = BADDR(dn->dn_Startup);
    de = BADDR(fssm->fssm_Environ);
    if (!de || de->de_TableSize < DE_DOSTYPE || de->de_TableSize > 64)
        return;
    t = de->de_DosType;
    for (i = 3; i >= 0; i--) {
        UBYTE c = (t >> (i * 8)) & 0xff;
        if (c >= 0x20 && c < 0x7f) {
            out[n++] = c;
        } else {
            out[n++] = '\\';
            if (c >= 100)
                out[n++] = '0' + c / 100;
            if (c >= 10)
                out[n++] = '0' + c / 10 % 10;
            out[n++] = '0' + c % 10;
        }
    }
    out[n] = 0;
}

int main(int argc, char **argv)
{
    struct DosList *dl;
    char wbuf[32];
    char *want = NULL;
    struct row *r;
    int count = 0;

    if (argc > 1) {
        size_t n = strlen(argv[1]);

        if (n && argv[1][n - 1] == ':')
            n--;
        if (n > sizeof(wbuf) - 1)
            n = sizeof(wbuf) - 1;
        memcpy(wbuf, argv[1], n);
        wbuf[n] = 0;
        want = wbuf;
    }

    dl = LockDosList(LDF_DEVICES | LDF_READ);
    while ((dl = NextDosEntry(dl, LDF_DEVICES)) && count < MAXDEV) {
        struct DeviceNode *dn = (struct DeviceNode *)dl;

        r = &rows[count];

        bstr(dn->dn_Name, r->name, sizeof(r->name) - 1);
        if (want && !same(want, r->name))
            continue;
        strcat(r->name, ":");
        dostype(dn, r->dostype);
        r->pri = dn->dn_Priority;
        r->stack = dn->dn_StackSize;
        r->running = 0;
        if (dn->dn_Task) {
            struct Task *t = ((struct MsgPort *)dn->dn_Task)->mp_SigTask;
            if (t) {
                r->running = 1;
                r->tpri = t->tc_Node.ln_Pri;
                r->tstack = (ULONG)t->tc_SPUpper - (ULONG)t->tc_SPLower;
            }
        }
        count++;
    }
    UnLockDosList(LDF_DEVICES | LDF_READ);

    Printf("%-10s %-8s %5s %8s   %5s %8s\n",
           (LONG)"Device", (LONG)"DosType", (LONG)"Pri", (LONG)"Stack",
           (LONG)"TPri", (LONG)"TStack");
    for (r = rows; r < rows + count; r++) {
        Printf("%-10s %-8s %5ld %8lu   ",
               (LONG)r->name, (LONG)r->dostype, r->pri, r->stack);
        if (r->running)
            Printf("%5ld %8lu\n", r->tpri, r->tstack);
        else
            Printf("%5s %8s\n", (LONG)"-", (LONG)"-");
    }
    if (want && !count) {
        Printf("%s: no such device\n", (LONG)wbuf);
        return RETURN_WARN;
    }
    return RETURN_OK;
}
