<?php
// openlog, syslog and closelog go to the c library's syslog; LOG_PERROR
// copies each line to stderr, where a message's newlines split it into
// lines and its control bytes show as \xNN
var_dump(openlog("zphp-compat", LOG_PERROR, LOG_USER));
var_dump(syslog(LOG_DEBUG, "first line\nsecond\x01line\x00end"));
var_dump(closelog());
var_dump(closelog());
