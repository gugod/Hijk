#include <stdio.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <errno.h>
#include "http-parser/http_parser.h"
#define DONE 1
static int header_complete_cb(http_parser *p);
static int message_complete_cb (http_parser *p);
static int body_cb(http_parser *p, const char *buf, size_t len);

struct response {
    SV *body;
    int status;
    int flags;
};

static http_parser_settings settings = {
    .on_message_begin = NULL,
    .on_header_field = NULL,
    .on_header_value = NULL,              
    .on_url = NULL,
    .on_body = body_cb,
    .on_headers_complete = header_complete_cb,
    .on_message_complete = message_complete_cb
};

static void read_and_store(int fd, struct response *r) {
    struct http_parser parser;
    memset(&parser,0,sizeof(parser));
    int rc, nparsed;
    http_parser_init(&parser, HTTP_RESPONSE);
    parser.data = r;
    for (;;) {
        char buf[BUFSIZ];
        int rc = recv(fd,buf,BUFSIZ,0);
        if (rc <= 0) {
            r->status = 0;
            sv_setpv(r->body,rc == -1 ? strerror(errno) : "connection terminated unexpectedly");
            break;
        } else {
            if ((nparsed = http_parser_execute(&parser,&settings,buf,rc)) != rc) {
                r->status = 0;
                sv_setpv(r->body,http_errno_description(parser.http_errno));
                break;
            }
            if (r->flags & DONE)
                break;
        }
    }
}

static int header_complete_cb(http_parser *p) {
    struct response *r = (struct response *) p->data;
    r->status = p->status_code;
    return 0;
}

static int message_complete_cb (http_parser *p) {
    struct response *r = (struct response *) p->data;
    r->flags |= DONE;
    return 0;
}

static int body_cb(http_parser *p, const char *buf, size_t len) {
    struct response *r = (struct response *) p->data;
    sv_catpvn(r->body,buf,len);
    return 0;
}
