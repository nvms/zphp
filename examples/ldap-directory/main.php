<?php
// covers: ldap_escape (filter + dn modes), ldap_explode_dn, ldap_err2str,
//   string formatting, array filtering, defensive query building

// build LDAP filters defensively for untrusted user input
function buildUserFilter(string $username, string $email): string {
    $u = ldap_escape($username, "", LDAP_ESCAPE_FILTER);
    $e = ldap_escape($email, "", LDAP_ESCAPE_FILTER);
    return "(&(uid=$u)(mail=$e))";
}

function buildDn(string $cn, string $ou, string $dc1, string $dc2): string {
    $cn = ldap_escape($cn, "", LDAP_ESCAPE_DN);
    return "cn=$cn,ou=$ou,dc=$dc1,dc=$dc2";
}

echo "=== defensive filter construction ===\n";
$cases = [
    ['alice', 'alice@example.com'],
    ['bob*', 'bob@evil.com'],         // wildcard injection attempt
    ['(admin)', 'a@b.c'],              // paren injection
    ['x\\y', 'x@y'],                   // backslash
    ['a)(uid=*', 'x@y'],               // classic LDAP injection
];
foreach ($cases as [$u, $e]) {
    echo sprintf("%-12s -> %s\n", $u, buildUserFilter($u, $e));
}

echo "\n=== defensive DN construction ===\n";
$dn_cases = [
    ['John Doe', 'people', 'example', 'com'],
    ['Smith, Jane', 'admins', 'corp', 'local'],
    ['robert "quoted"', 'people', 'example', 'org'],
    ['back\\slash', 'people', 'example', 'org'],
];
foreach ($dn_cases as [$cn, $ou, $d1, $d2]) {
    echo sprintf("%-20s -> %s\n", $cn, buildDn($cn, $ou, $d1, $d2));
}

echo "\n=== DN explosion ===\n";
$dns = [
    "cn=John Doe,ou=people,dc=example,dc=com",
    "uid=alice,ou=engineering,ou=staff,dc=corp,dc=local",
    "cn=admin,dc=example,dc=org",
];
foreach ($dns as $dn) {
    $parts = ldap_explode_dn($dn, 0);
    echo "$dn ({$parts['count']} parts)\n";
    for ($i = 0; $i < $parts['count']; $i++) {
        echo "  [$i] {$parts[$i]}\n";
    }
    $values = ldap_explode_dn($dn, 1);
    $vals = [];
    for ($i = 0; $i < $values['count']; $i++) $vals[] = $values[$i];
    echo "  values only: " . implode(" / ", $vals) . "\n";
}

echo "\n=== error code lookup ===\n";
$codes = [0, 1, 32, 49, 80];
foreach ($codes as $code) {
    $msg = ldap_err2str($code);
    echo sprintf("  %3d: %s\n", $code, $msg);
}

echo "\n=== connection lifecycle (no real server needed) ===\n";
$ld = ldap_connect("ldap://localhost:1389");
echo "connect ok: " . ($ld !== false ? "yes" : "no") . "\n";
ldap_unbind($ld);
echo "unbound\n";
