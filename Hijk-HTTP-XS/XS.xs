#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"
#include "const-c.inc"
#include "http.h"
MODULE = Hijk::HTTP::XS		PACKAGE = Hijk::HTTP::XS		

INCLUDE: const-xs.inc

void fetch(int fd)
    PPCODE:
        SV *body = newSVpv("",0);
        EXTEND(SP,2);
        struct response resp = { .body = body, .status = 0, .flags = 0 };
        read_and_store(fd,&resp);
        PUSHs(sv_2mortal(newSViv(resp.status)));
        PUSHs(sv_2mortal(resp.body));
