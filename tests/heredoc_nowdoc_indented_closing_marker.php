<?php
$result = <<<EOT
    line1
    line2
    EOT;
echo "[", $result, "]\n";

$result = <<<EOT
        line1
        line2
    EOT;
echo "[", $result, "]\n";

$result = <<<EOT
    line1
      indented
    line3
    EOT;
echo "[", $result, "]\n";

function f(): string {
    return <<<EOT
        hello
        world
        EOT;
}
echo "[", f(), "]\n";

$result = <<<'EOT'
    nowdoc1
    nowdoc2
    EOT;
echo "[", $result, "]\n";

$result = <<<EOT
EOT;
echo "[", $result, "]\n";

$result = <<<EOT

EOT;
echo "[", $result, "]\n";

$result = <<<EOT
        one line
        EOT;
echo "[", $result, "]\n";

$result = <<<TXT
    plain a
    plain b
    TXT;
echo "[", $result, "]\n";

$name = "world";
$result = <<<EOT
    hello, $name
    welcome
    EOT;
echo "[", $result, "]\n";

$arr = [10, 20];
$result = <<<EOT
    first: $arr[0]
    second: $arr[1]
    EOT;
echo "[", $result, "]\n";

class O {
    public int $val = 42;
}
$o = new O;
$result = <<<EOT
    obj: {$o->val}
    EOT;
echo "[", $result, "]\n";

$result = <<<EOT
    {
      "key": "value",
      "nested": {
        "x": 1
      }
    }
    EOT;
echo $result, "\n";

$result = <<<'EOT'
    no interpolation $name
    {$arr[0]}
    EOT;
echo "[", $result, "]\n";

$result = <<<XML
<?xml version="1.0"?>
<root>
    <item>value</item>
</root>
XML;
echo $result, "\n";

$result = <<<HTML
<html>
    <body>
        <p>$name</p>
    </body>
</html>
HTML;
echo $result, "\n";

function process(string $body): array {
    return [
        "header" => <<<HEAD
            Content-Type: text/plain
            HEAD,
        "body" => $body,
    ];
}
print_r(process("data"));

$multiline = <<<EOT
line 1 with literal "quote"
line 2 with $name
\$dollar-escape
EOT;
echo $multiline, "\n";

class Q {
    public function build(): string {
        return <<<SQL
            SELECT id, name
            FROM users
            WHERE active = 1
            SQL;
    }
}
echo (new Q)->build(), "\n";

$indented = <<<EOT
        deeply indented
            even more
        back
        EOT;
echo $indented, "\n";

$result = <<<EOT
    a
      b
    c
    EOT;
echo "[", $result, "]\n";

$query = <<<SQL
    SELECT *
    FROM users
    WHERE id IN (1,2,3)
    SQL;
$lines = explode("\n", $query);
echo count($lines), "\n";

$short = <<<TXT
    one
    TXT;
echo $short === "one" ? "y" : "n", "\n";

$nowdoc_short = <<<'TXT'
    one
    TXT;
echo $nowdoc_short === "one" ? "y" : "n", "\n";

$with_blank = <<<EOT
    first

    third
    EOT;
echo $with_blank, "\n";

function multilineRet(): string {
    return <<<EOT
        a
        b
        c
        EOT;
}
echo multilineRet(), "\n";
echo str_contains(multilineRet(), "    ") ? "y" : "n", "\n";

$arr_with_heredoc = [
    "x" => <<<EOT
    in-array
    EOT,
    "y" => 42,
];
print_r($arr_with_heredoc);
