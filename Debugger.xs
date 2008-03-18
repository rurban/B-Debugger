#include <EXTERN.h>
#include <perl.h>
#include <XSUB.h>

#include <limits.h>

void
print_banner()
{
    printf("\nB::Debugger %s - optree debugger. h for help\n", VERSION);
}
void
print_help()
{
    printf("Usage:\n");
    printf("n <n> next op         op <n>  inspect op\n");
    printf("c <n> continue          next  next op\n");
    printf("b <n> break at step     type  type\n");
    printf("l     list              flags flags of current op\n");
    printf("                      [SAHPICG]V<n> inspect n-th global variable\n");
    printf("h     help            F,Flags   B::Flags of current op\n");
    printf("q     quit            C,Concise B::Concise of current op\n");
}

struct debugger_state {
    int step;
    OP* step_addr;
    AV* args;
    int break_at;
    int numsteps;
};
static struct debugger_state dbg_state;
static void *flagspv;
static void *privatepv;
static void *safe_runops;

typedef enum enum_dbg_continue {
    DBG_SAME, /* stay at this op */
    DBG_CONT, /* continue until breakpoint (dbg_state->break_at) */
    DBG_NEXT, /* continue one step (at dbg_state->next_step) */
    DBG_QUIT, /* abort debugger */
} dbg_continue;

char *op_Bflags(OP *op) {
    dSP; 
    dVAR;
    char buf[1028];
    SV *result;
    int items;

    ENTER; SAVETMPS; PUSHMARK (SP);

    EXTEND (SP, 1);
    XPUSHs(sv_2mortal(newSVuv(PTR2UV(op))));
    PUTBACK;
    items = perl_call_pv("B::Flags::flagspv", G_SCALAR);
    SPAGAIN;
    if (items) {
	result = POPs;
	sprintf(buf, "Flags: %s", SvPVX(result));
    }

    EXTEND (SP, 1);
    XPUSHs(sv_2mortal(newSVuv(PTR2UV(op))));
    PUTBACK;
    items = perl_call_pv("B::Flags::privatepv", G_SCALAR);
    SPAGAIN;
    if (items) {
	result = POPs;
	sprintf(buf, "%s, private: %s", buf, SvPVX(result));
    }

    PUTBACK; FREETMPS; LEAVE;
    return (char *)strdup(buf);
}
char *sv_flags(OP *op) {
    return "";
}

void print_list(int from, int to) {
    if (!from) from=dbg_state.step;
    if (!to) to=from+15;
    SV* op = dbg_state.step_addr; /* or which op? */
    /* list optree with Concise? */
    printf("list %d-%d nyi\n",from,to);
    {
	dSP; 
	dVAR;
	int items;
	ENTER; SAVETMPS; PUSHMARK (SP);

	EXTEND (SP, 2);
	XPUSHs(sv_2mortal(newSVuv(PTR2UV(op))));
	XPUSHs(sv_2mortal(newSVpvn("tree",4)));
	PUTBACK;
	items = perl_call_pv("B::Concise::concise_main", G_VOID);
	SPAGAIN;

	PUTBACK; FREETMPS; LEAVE;
    }
}

char * concise_op() {
    dSP; 
    dVAR;
    SV *temp;
    int items;
    SV *result;

    ENTER; SAVETMPS; PUSHMARK (SP);

    EXTEND (SP, 3);
    /* ($op, $level, $format) = @_; */
    XPUSHs(sv_2mortal(newSVuv(PTR2UV(dbg_state.step_addr))));
    XPUSHs(sv_2mortal(newSVuv(1)));
    XPUSHs(sv_2mortal(newSVpvn("",0)));
    PUTBACK;
    items = perl_call_pv("B::Concise::concise_op", G_SCALAR);
    SPAGAIN;
    if (items) {
	result = POPs;
    }
    printf("op %d %s\n", dbg_state.step, SvPVX(result));

    /* my($sv, $hr, $preferpv) = @_; */
    /* items = Perl_call_pv("B::Concise::concise_sv", G_SCALAR); */

    PUTBACK; FREETMPS; LEAVE;
    return SvPVX(result);
}

/* TODO: readline enabled */
int do_debugger ()
{
    char buf[80];
    char *in;
    int len;

    printf("> "); 
    if (dbg_state.step && !dbg_state.step_addr) {
	printf("program ended.\n");
	return DBG_SAME;
    }
    in = gets(buf);
    if (strEQ(in, "h")) {
	print_help();
	return DBG_SAME;
    } else 
    if (strEQ(in, "q")) {
	dbg_state.break_at = LONG_MAX;
	printf("quit\n");
	return DBG_QUIT;
    } else 
    if (!strncmp(in, "n",1) || !strncmp(in, "next",4)) {
	char *dummy;
	sscanf(buf,"%s %d",dummy,in);
	dbg_state.numsteps = atoi(in);
	if (dbg_state.numsteps)
	    printf("next %d steps\n", dbg_state.numsteps);
	else
	    dbg_state.numsteps = 1;
	return DBG_NEXT;
    } else 
    if (!strncmp(in, "c",1) || !strncmp(in, "cont",4)) {
	char *dummy;
	sscanf(buf,"%s %d",dummy,in);
	dbg_state.break_at = atoi(in);
	if (dbg_state.break_at)
	    printf("continue until %d\n", dbg_state.break_at);
	return DBG_CONT;
    } else 
    if (!strncmp(in, "l",1) || !strncmp(in, "list",4)) {
	char *dummy;
	int from, to;
	from=0; to=0;
	sscanf(buf,"%s %d-%d",dummy,from,to);
	if (!from) from=dbg_state.step;
	if (!to) to=from+15;
	/* list optree with Concise? */
	print_list(from,to);
	return DBG_SAME;
    } else 
    if (!strncmp(in, "b",1) || !strncmp(in, "break",5)) {
	char *dummy;
	sscanf(buf,"%s %d",dummy,in);
	dbg_state.break_at = atoi(in);
	if (dbg_state.break_at)
	    printf("break at step %d\n", dbg_state.break_at);
	return DBG_SAME;
    } else 
    if (!strncmp(in, "op",2)) {
	int i;
	char *s;
	sscanf(buf,"op %d",in);
	i = atoi(in);
	s = op_Bflags(dbg_state.step_addr);
	printf("op %d Flags: %s", dbg_state.step, s);
	free(s);
	return DBG_SAME;
    } else 
    if (strEQ(in, "flags")||strEQ(in, "f")) {
	char *s = op_Bflags(dbg_state.step_addr);
	printf("op %d Flags: %s", dbg_state.step, s);
	free(s);
	return DBG_SAME;
    } else 
    if (strEQ(in, "Flags")||strEQ(in, "F")) {
	char *s = op_Bflags(dbg_state.step_addr);
	printf("op %d Flags: %s", dbg_state.step, s);
	free(s);
	return DBG_SAME;
    } else 
    if (strEQ(in, "Concise") || strEQ(in, "C")) {
	concise_op();
	return DBG_SAME;
    } else {
        printf("unknown command %s\n", in);
	return DBG_SAME;
    }
}

static int
my_runops(pTHX)
{
    int dbg_cont;

    if (!dbg_state.step)
	print_banner();
    do {
	PERL_ASYNC_CHECK();
	dbg_cont = do_debugger();

	/* continue until break. only one break point so far. */
	if (dbg_cont == DBG_CONT) {
	    do {
		PERL_ASYNC_CHECK();
		PL_op = CALL_FPTR(PL_op->op_ppaddr)(aTHX);
		dbg_state.step_addr = PL_op;
		dbg_state.step++;
	    } while (PL_op && (dbg_state.step != dbg_state.break_at));
	}
	/* execute next n number of steps */
	else if (dbg_cont == DBG_NEXT) {
	    int i;
	    for (i=0; 
		 (i<dbg_state.numsteps) && 
		     PL_op && 
		     (dbg_state.step != dbg_state.break_at);
		 i++) 
	    {
		PERL_ASYNC_CHECK();
		PL_op = CALL_FPTR(PL_op->op_ppaddr)(aTHX); 
		dbg_state.step_addr = PL_op;
		dbg_state.step++;
	    }
	}
    } while (PL_op && (dbg_cont != DBG_QUIT));
    /*PL_runops = safe_runops;*/
    return 0;
}

MODULE = B::Debugger PACKAGE = B::Debugger

PROTOTYPES: DISABLE

BOOT:		/* at which stage to begin? INIT, UNITCHECK or CHECK */
    dbg_state.step = 0;
    dbg_state.break_at = 0;
    dbg_state.numsteps = 1;
    /* save_runops = (void *)PL_runops; */
    /* PL_runops = my_runops; */
