/*
 * Copyright (c) 2007, OmniTI Computer Consulting, Inc.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 * 
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above
 *       copyright notice, this list of conditions and the following
 *       disclaimer in the documentation and/or other materials provided
 *       with the distribution.
 *     * Neither the name OmniTI Computer Consulting, Inc. nor the names
 *       of its contributors may be used to endorse or promote products
 *       derived from this software without specific prior written
 *       permission.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#include "noit_defines.h"

#include <uuid/uuid.h>
#include <netinet/in.h>

#include "noit_check.h"
#include "noit_filters.h"
#include "utils/noit_log.h"
#include "jlog/jlog.h"

/* Log format is tab delimited:
 * NOIT CONFIG (implemented in noit_conf.c):
 *  'n' TIMESTAMP strlen(xmlconfig) base64(gzip(xmlconfig))
 *
 * CHECK:
 *  'C' TIMESTAMP UUID TARGET MODULE NAME
 *
 * STATUS:
 *  'S' TIMESTAMP UUID STATE AVAILABILITY DURATION STATUS_MESSAGE
 *
 * METRICS:
 *  'M' TIMESTAMP UUID NAME TYPE VALUE
 */

static noit_log_stream_t check_log = NULL;
static noit_log_stream_t status_log = NULL;
static noit_log_stream_t metrics_log = NULL;
#define SECPART(a) ((unsigned long)(a)->tv_sec)
#define MSECPART(a) ((unsigned long)((a)->tv_usec / 1000))

static void
handle_extra_feeds(noit_check_t *check,
                   int (*log_f)(noit_log_stream_t ls, noit_check_t *check)) {
  noit_log_stream_t ls;
  noit_skiplist_node *curr, *next;
  const char *feed_name;

  if(!check->feeds) return;
  curr = next = noit_skiplist_getlist(check->feeds);
  while(curr) {
    /* We advance next here (before we try to use curr).
     * We may need to remove the node we're looking at and that would
     * disturb the iterator, so advance in advance. */
    noit_skiplist_next(check->feeds, &next);
    feed_name = (char *)curr->data;
    ls = noit_log_stream_find(feed_name);
    if(!ls || log_f(ls, check)) {
      noit_check_transient_remove_feed(check, feed_name);
      /* noit_skiplisti_remove(check->feeds, curr, free); */
    }
    curr = next;
  }
  /* We're done... we may have destroyed the last feed.
   * that combined with transience means we should kill the check */
  /* noit_check_transient_remove_feed(check, NULL); */
}

static int
_noit_check_log_check(noit_log_stream_t ls,
                      noit_check_t *check) {
  struct timeval __now;
  char uuid_str[37];

  uuid_unparse_lower(check->checkid, uuid_str);
  gettimeofday(&__now, NULL);
  return noit_log(ls, &__now, __FILE__, __LINE__,
                  "C\t%lu.%03lu\t%s\t%s\t%s\t%s\n",
                  SECPART(&__now), MSECPART(&__now),
                  uuid_str, check->target, check->module, check->name);
}

void
noit_check_log_check(noit_check_t *check) {
  handle_extra_feeds(check, _noit_check_log_check);
  if(!(check->flags & NP_TRANSIENT)) {
    SETUP_LOG(check, return);
    _noit_check_log_check(check_log, check);
  }
}

static int
_noit_check_log_status(noit_log_stream_t ls,
                       noit_check_t *check) {
  stats_t *c;
  char uuid_str[37];

  uuid_unparse_lower(check->checkid, uuid_str);
  c = &check->stats.current;
  return noit_log(ls, &c->whence, __FILE__, __LINE__,
                  "S\t%lu.%03lu\t%s\t%c\t%c\t%d\t%s\n",
                  SECPART(&c->whence), MSECPART(&c->whence), uuid_str,
                  (char)c->state, (char)c->available, c->duration, c->status);
}
void
noit_check_log_status(noit_check_t *check) {
  handle_extra_feeds(check, _noit_check_log_status);
  if(!(check->flags & NP_TRANSIENT)) {
    SETUP_LOG(status, return);
    _noit_check_log_status(status_log, check);
  }
}
static int
_noit_check_log_metrics(noit_log_stream_t ls, noit_check_t *check) {
  int rv = 0;
  int srv;
  char uuid_str[37];
  noit_hash_iter iter = NOIT_HASH_ITER_ZERO;
  const char *key;
  int klen;
  stats_t *c;
  void *vm;

  uuid_unparse_lower(check->checkid, uuid_str);
  c = &check->stats.current;
  while(noit_hash_next(&c->metrics, &iter, &key, &klen, &vm)) {
    /* If we apply the filter set and it returns false, we don't log */
    metric_t *m = (metric_t *)vm;
    if(!noit_apply_filterset(check->filterset, check, m)) continue;
    if(!ls->enabled) continue;

    srv = 0;
    if(!m->metric_value.s) { /* they are all null */
      srv = noit_log(ls, &c->whence, __FILE__, __LINE__,
                     "M\t%lu.%03lu\t%s\t%s\t%c\t[[null]]\n",
                     SECPART(&c->whence), MSECPART(&c->whence), uuid_str,
                     m->metric_name, m->metric_type);
    }
    else {
      switch(m->metric_type) {
        case METRIC_INT32:
          srv = noit_log(ls, &c->whence, __FILE__, __LINE__,
                         "M\t%lu.%03lu\t%s\t%s\t%c\t%d\n",
                         SECPART(&c->whence), MSECPART(&c->whence), uuid_str,
                         m->metric_name, m->metric_type, *(m->metric_value.i));
          break;
        case METRIC_UINT32:
          srv = noit_log(ls, &c->whence, __FILE__, __LINE__,
                         "M\t%lu.%03lu\t%s\t%s\t%c\t%u\n",
                         SECPART(&c->whence), MSECPART(&c->whence), uuid_str,
                         m->metric_name, m->metric_type, *(m->metric_value.I));
          break;
        case METRIC_INT64:
          srv = noit_log(ls, &c->whence, __FILE__, __LINE__,
                         "M\t%lu.%03lu\t%s\t%s\t%c\t%lld\n",
                         SECPART(&c->whence), MSECPART(&c->whence), uuid_str,
                         m->metric_name, m->metric_type, *(m->metric_value.l));
          break;
        case METRIC_UINT64:
          srv = noit_log(ls, &c->whence, __FILE__, __LINE__,
                         "M\t%lu.%03lu\t%s\t%s\t%c\t%llu\n",
                         SECPART(&c->whence), MSECPART(&c->whence), uuid_str,
                         m->metric_name, m->metric_type, *(m->metric_value.L));
          break;
        case METRIC_DOUBLE:
          srv = noit_log(ls, &c->whence, __FILE__, __LINE__,
                         "M\t%lu.%03lu\t%s\t%s\t%c\t%.12e\n",
                         SECPART(&c->whence), MSECPART(&c->whence), uuid_str,
                         m->metric_name, m->metric_type, *(m->metric_value.n));
          break;
        case METRIC_STRING:
          srv = noit_log(ls, &c->whence, __FILE__, __LINE__,
                         "M\t%lu.%03lu\t%s\t%s\t%c\t%s\n",
                         SECPART(&c->whence), MSECPART(&c->whence), uuid_str,
                         m->metric_name, m->metric_type, m->metric_value.s);
          break;
        default:
          noitL(noit_error, "Unknown metric type '%c' 0x%x\n",
                m->metric_type, m->metric_type);
      }
    }
    if(srv) rv = srv;
  }
  return rv;
}
void
noit_check_log_metrics(noit_check_t *check) {
  handle_extra_feeds(check, _noit_check_log_metrics);
  if(!(check->flags & NP_TRANSIENT)) {
    SETUP_LOG(metrics, return);
    _noit_check_log_metrics(metrics_log, check);
  }
}

int
noit_stats_snprint_metric_value(char *b, int l, metric_t *m) {
  int rv;
  if(!m->metric_value.s) { /* they are all null */
    rv = snprintf(b, l, "[[null]]");
  }
  else {
    switch(m->metric_type) {
      case METRIC_INT32:
        rv = snprintf(b, l, "%d", *(m->metric_value.i)); break;
      case METRIC_UINT32:
        rv = snprintf(b, l, "%u", *(m->metric_value.I)); break;
      case METRIC_INT64:
        rv = snprintf(b, l, "%lld", *(m->metric_value.l)); break;
      case METRIC_UINT64:
        rv = snprintf(b, l, "%llu", *(m->metric_value.L)); break;
      case METRIC_DOUBLE:
        rv = snprintf(b, l, "%.12e", *(m->metric_value.n)); break;
      case METRIC_STRING:
        rv = snprintf(b, l, "%s", m->metric_value.s); break;
      default:
        return -1;
    }
  }
  return rv;
}
int
noit_stats_snprint_metric(char *b, int l, metric_t *m) {
  int rv, nl;
  nl = snprintf(b, l, "%s[%c] = ", m->metric_name, m->metric_type);
  if(nl >= l || nl <= 0) return nl;
  rv = noit_stats_snprint_metric_value(b+nl, l-nl, m);
  if(rv == -1)
    rv = snprintf(b+nl, l-nl, "[[unknown type]]");
  return rv + nl;
}
