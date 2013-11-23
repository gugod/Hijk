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
        HV *header = newHV();
        EXTEND(SP,3);
        struct response resp = {
                                   .header = header,
                                   .body = body,
                                   .status = 0,
                                   .flags = 0,
                                   .current_header = NULL,
                                   .current_value  = NULL
                        };
        read_and_store(fd,&resp);
        PUSHs(sv_2mortal(newSViv(resp.status)));
        PUSHs(sv_2mortal(resp.body));
        PUSHs(newRV_noinc((SV *)resp.header));
