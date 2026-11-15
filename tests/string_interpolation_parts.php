<?php
// interpolated strings are parsed into their parts the way php's scanner
// and parser read them: code inside "{$...}" and "${...}" is ordinary php,
// nested strings and heredocs included

$a = ['x' => 1, 5 => 'five', '01' => 'z', -3 => 'neg', 'k' => ['n' => 'deep'], '-0' => 'minus zero', '0x1A' => 'hex'];
$o = new stdClass;
$o->p = 'prop';
$o->q = $o;
$s = 'substr';
$name = 'a';
$k = 'x';

echo "simple: $a[x] $a[5] $a[01] $a[-3] $a[-0] $a[0x1A] $a[$k]\n";
echo "props: $o->p {$o->q->p} $o->p->x $name->\n";
echo "calls: {$s("abc{$o->p}", 0, 2)} {$a["k"]["n"]} {$s('}', 0)}\n";
echo "dollar brace: ${substr('laruence', 0, 2)}x ${name} ${a['x']} ${a[$k]}\n";
echo "escapes: \$a \{$name} {$a['x']}$name $ {$s}\n";
$n = null;
echo "nullsafe: [$n?->p] [{$o?->p}]\n";

echo <<<EOT
  heredoc: $a[x]
    {$s("q}w", 0, 1)} ${name}
  end
  EOT;
echo "\n";

echo <<<DOC
{$s(<<<'ppp'
abcdefg
ppp
,0,3)}
DOC;
echo "\n";

echo <<<DOC
  outer {$s(<<<DOC
    inner {$s("xyz", 1)}
    DOC, 0, 7)} done
  DOC;
echo "\n";

$la = 'found';
echo "${substr('laruence', 0, 2)}\n";

// each part becomes a string as it is added
class T {
    function __construct(public $n) {}
    function __toString(): string { echo "[str {$this->n}]"; return $this->n; }
}
function f($v) { echo "[f $v]"; return $v; }
$t = new T('t');
echo "{$t}{$s(f('x'), 0)}\n";
echo "$t$t\n";

// line numbers of the parts
echo "line
$undefined1
{$undefined2}
";

// carriage returns end heredoc lines
eval("\$h = <<<H\r    a\r\r    b\r    H;");
var_dump(addcslashes($h, "\r"));
eval("\$h = <<<H\r\n    a\r\n  \r\n    b\r\n    H;");
var_dump(addcslashes($h, "\r\n"));

// syntax errors inside the code
foreach (['"{$g{\'h\'}}";', '"{$a + 1}";', '"$a[ x]";', '"{$a::B}";'] as $code) {
    try {
        eval($code);
    } catch (ParseError $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}
