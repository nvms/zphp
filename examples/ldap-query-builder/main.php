<?php
// covers: a fluent LDAP filter builder that defends against injection,
//   ldap_escape across modes, ldap_explode_dn for parsing returned DNs

final class Filter {
    private function __construct(private string $f) {}

    public static function eq(string $attr, string $value): self {
        return new self('(' . self::attr($attr) . '=' . ldap_escape($value, '', LDAP_ESCAPE_FILTER) . ')');
    }

    public static function present(string $attr): self {
        return new self('(' . self::attr($attr) . '=*)');
    }

    public static function contains(string $attr, string $value): self {
        return new self('(' . self::attr($attr) . '=*' . ldap_escape($value, '', LDAP_ESCAPE_FILTER) . '*)');
    }

    public static function startsWith(string $attr, string $value): self {
        return new self('(' . self::attr($attr) . '=' . ldap_escape($value, '', LDAP_ESCAPE_FILTER) . '*)');
    }

    public static function and (Filter ...$parts): self {
        return self::combine('&', ...$parts);
    }
    public static function or (Filter ...$parts): self {
        return self::combine('|', ...$parts);
    }
    public function not(): self {
        return new self('(!' . $this->f . ')');
    }

    private static function combine(string $op, Filter ...$parts): self {
        $out = '(' . $op;
        foreach ($parts as $p) $out .= $p->f;
        return new self($out . ')');
    }

    private static function attr(string $name): string {
        if (!preg_match('/^[A-Za-z][A-Za-z0-9\-]*$/', $name)) {
            throw new InvalidArgumentException("invalid attribute: $name");
        }
        return $name;
    }

    public function __toString(): string { return $this->f; }
}

echo "=== simple equality ===\n";
echo Filter::eq('cn', 'Alice') . "\n";
echo Filter::eq('uid', 'admin*injection)') . "\n";
echo Filter::eq('mail', 'a@b.c') . "\n";

echo "\n=== conjunctions ===\n";
echo Filter::and(
    Filter::eq('objectClass', 'person'),
    Filter::eq('department', 'engineering'),
) . "\n";

echo "\n=== negation + complex ===\n";
echo Filter::and(
    Filter::eq('objectClass', 'user'),
    Filter::eq('mail', 'admin@corp.local')->not(),
    Filter::or (
        Filter::startsWith('cn', 'Alice'),
        Filter::contains('description', 'lead'),
    ),
) . "\n";

echo "\n=== attribute names guarded ===\n";
try {
    Filter::eq('cn)(uid=*', 'evil');
    echo "leaked\n";
} catch (InvalidArgumentException $e) {
    echo "blocked: " . $e->getMessage() . "\n";
}

echo "\n=== DN parsing pipeline ===\n";
$dns = [
    'cn=Alice Anderson,ou=Engineering,dc=corp,dc=local',
    'uid=admin,ou=Sysadmins,ou=Operations,dc=acme,dc=co,dc=uk',
];

foreach ($dns as $dn) {
    $parts = ldap_explode_dn($dn, 0);
    $values = ldap_explode_dn($dn, 1);
    echo "input: $dn\n";
    echo "  parts: " . $parts['count'] . "\n";
    $top = $parts[0];
    [$attr, $val] = explode('=', $top, 2);
    echo "  leaf: $attr = $val\n";
    $org = [];
    for ($i = 0; $i < $parts['count']; $i++) {
        [$a, $v] = explode('=', $parts[$i], 2);
        if (strtolower($a) === 'dc') $org[] = $v;
    }
    echo "  domain: " . implode('.', $org) . "\n";
    echo "  cn-only values: " . implode(' / ', array_slice(iterator_to_array(new ArrayIterator($values)), 0, $values['count'])) . "\n";
}
