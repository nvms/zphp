<?php

// parse_url returns false on invalid URLs
var_dump(parse_url('http:///'));
var_dump(parse_url('http://'));
var_dump(parse_url('http://:80'));
var_dump(parse_url('http://user:pass@:80'));
var_dump(parse_url('ftp:///foo'));

// file:// is the special case where empty host is permitted
var_dump(parse_url('file:///tmp/foo'));
var_dump(parse_url('file:///'));
var_dump(parse_url('file://localhost/tmp'));

// other valid URLs unaffected
var_dump(parse_url('http://example.com/path?q=1#frag'));
var_dump(parse_url('mailto:user@example.com'));
var_dump(parse_url('//example.com/path'));

// idate returns false on unknown format char
var_dump(@idate('Q'));
var_dump(@idate('z'));
var_dump(idate('Y'));
var_dump(idate('m'));
