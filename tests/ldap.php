<?php
// covers: ldap constants, ldap_escape, ldap_explode_dn, ldap_err2str, ldap_connect (no bind to live server)

assert(LDAP_DEREF_NEVER === 0);
assert(LDAP_DEREF_ALWAYS === 3);
assert(LDAP_ESCAPE_FILTER === 1);
assert(LDAP_ESCAPE_DN === 2);
assert(defined('LDAP_OPT_PROTOCOL_VERSION'));

// escape filter
$e = ldap_escape("foo*bar(baz)", "", LDAP_ESCAPE_FILTER);
assert($e === "foo\\2abar\\28baz\\29");

// escape dn
$e = ldap_escape("John, Doe", "", LDAP_ESCAPE_DN);
assert(strpos($e, "\\2c") !== false);

// err2str
$s = ldap_err2str(0);
assert(is_string($s) && strlen($s) > 0);

// explode_dn
$parts = ldap_explode_dn("cn=John,ou=Users,dc=example,dc=com", 0);
assert(is_array($parts));
assert($parts[0] === "cn=John");
assert($parts['count'] === 4);

// connect succeeds against any URL (deferred until bind)
$ld = ldap_connect("ldap://127.0.0.1:1");
assert($ld !== false);
ldap_unbind($ld);

echo "ok\n";
