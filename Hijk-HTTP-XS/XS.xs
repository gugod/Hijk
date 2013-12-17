#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"
#include "http.h"
#include <fcntl.h>

MODULE = Hijk::HTTP::XS		PACKAGE = Hijk::HTTP::XS		

void fetch(int fd,int timeout_ms)
    PPCODE:
        int error = 0;
        SV *body = newSVpv("",0);
        HV *header = newHV();
        EXTEND(SP,3);
        struct response resp = {
                                   .header = header,
                                   .body = body,
                                   .status = 0,
                                   .flags = 0,
                                   .current_header = NULL,
                                   .current_value  = NULL,
                                   .timeout_ms = timeout_ms,
                        };

        error = read_and_store(fd,&resp);
        PUSHs(sv_2mortal(newSViv(resp.status)));
        PUSHs(sv_2mortal(resp.body));
        PUSHs(newRV_noinc((SV *)resp.header));
        if (error != 0)
            PUSHs(newSVnv(error));

void fd_set_blocking(int fd, int blocking)
    CODE:
        int flags = fcntl(fd, F_GETFL, 0);
        if (flags == -1)
            die("failed to F_GETFL");

        if (blocking)
            flags &= ~O_NONBLOCK;
        else
            flags |= O_NONBLOCK;

        if (fcntl(fd, F_SETFL, flags) == -1)
            die("failed to set blocking/nonblocking mode");
