<?php
// json_encode's error codes, partial output and depth checks as php's
// encoder reports them
function show($v, $flags = 0, $depth = 512) {
    try {
        var_dump(json_encode($v, $flags, $depth));
    } catch (JsonException $e) {
        echo "JsonException ", $e->getCode(), " ", $e->getMessage(), "\n";
    }
    echo json_last_error(), " ", json_last_error_msg(), "\n";
}
$p = JSON_PARTIAL_OUTPUT_ON_ERROR;
show(NAN);
show(NAN, $p);
show([1, INF, "x"], $p);
show(["ok", "\xff", "\xc3\xa9"]);
show(["ok", "\xff", "k\xfe" => 1], $p);
show(["a\xffb", "\xf0\x80\x80A"], JSON_INVALID_UTF8_SUBSTITUTE);
show(["a\xffb", "\xf0\x80\x80A"], JSON_INVALID_UTF8_IGNORE);
show("a\xffb", JSON_INVALID_UTF8_SUBSTITUTE | JSON_UNESCAPED_UNICODE);
$fp = fopen("php://memory", "r");
show([1, $fp, 2], $p);
show([1, $fp, 2]);
$a = [1];
$a[] = &$a;
show($a, $p);
show($a);
$o = new stdClass;
$o->self = $o;
$o->n = 1;
show($o, $p);
show([[1]], 0, 1);
show([[1]], $p, 1);
show([], 0, 0);
show(new stdClass, 0, 0);
show([[[1]], 2], $p | JSON_PRETTY_PRINT, 2);
enum Suit { case Hearts; }
enum Code: string { case A = "a"; }
show([Suit::Hearts, 1]);
show([Suit::Hearts, 1], $p);
show([Code::A]);
class Loop implements JsonSerializable {
    public function jsonSerialize(): mixed { return [$this]; }
}
show(new Loop, $p);
show(new Loop);
class Self_ implements JsonSerializable {
    public $x = 1;
    protected $hidden = 2;
    public function jsonSerialize(): mixed { return $this; }
}
show(new Self_);
show(NAN, JSON_THROW_ON_ERROR);
json_encode(NAN);
show(1, JSON_THROW_ON_ERROR);
show("\xff", JSON_THROW_ON_ERROR | $p);
show(["a" => "</tag>&'\"", "u" => "\u{2028}\u{1F600}é"], JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT);
show(["u" => "\u{2028}\u{2029}\u{1F600}"], JSON_UNESCAPED_UNICODE);
show(["u" => "\u{2028}\u{2029}"], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_LINE_TERMINATORS);
show(["12", " 12 ", "1e3", "0x1A", "1.5", "-0", ".5", "9223372036854775808", "1e999"], JSON_NUMERIC_CHECK);
show(["12" => "a", "x" => " 3"], JSON_NUMERIC_CHECK | JSON_FORCE_OBJECT);
show([1.0, 0.1, -0.0, 1e100], JSON_PRESERVE_ZERO_FRACTION);
show(["a" => [], "b" => new stdClass, "c" => [1, [2, ["k" => 3]]]], JSON_PRETTY_PRINT);
