<?php
// var_dump, print_r, var_export and json_encode mark the array or object they
// are inside on the value itself, as php does, so a call nested in
// __debugInfo or jsonSerialize sees what the outer call is walking

class Selfish implements JsonSerializable
{
    public $a = 1;

    public function jsonSerialize(): mixed
    {
        var_dump(json_encode($this), json_last_error_msg());
        return $this;
    }
}
var_dump(json_encode(new Selfish()));

class Debugged implements JsonSerializable
{
    public $a = 1;

    public function __debugInfo()
    {
        return ['result' => json_encode($this)];
    }

    public function jsonSerialize(): mixed
    {
        var_dump($this);
        return $this;
    }
}
var_dump(json_encode(new Debugged()));
echo "---\n";
var_dump(new Debugged());

class Exported implements JsonSerializable
{
    public $a = 1;

    public function __debugInfo()
    {
        return ['result' => var_export($this, true)];
    }

    public function jsonSerialize(): mixed
    {
        print_r($this);
        echo "\n";
        return $this;
    }
}
var_dump(json_encode(new Exported()));

class SerializeFirst implements JsonSerializable
{
    public $a = 1;

    public function __serialize(): array
    {
        return ['result' => json_encode($this)];
    }

    public function jsonSerialize(): mixed
    {
        return ['json' => serialize($this)];
    }
}
var_dump(serialize(new SerializeFirst()));

// a plain object or array that contains itself
$o = new stdClass();
$o->self = $o;
var_dump(json_encode($o), json_last_error_msg());
var_dump(json_encode($o, JSON_PARTIAL_OUTPUT_ON_ERROR));
$arr = [1];
$arr[] = &$arr;
var_dump(json_encode($arr), json_last_error_msg());
var_export($o);
echo "\n";
var_export([1, [2, [3]]]);
echo "\n";
print_r($o);
echo "\n";
var_dump($o);
// the same object twice side by side is not recursion
$shared = new stdClass();
$shared->v = 1;
var_dump(json_encode([$shared, $shared]));
var_export([$shared, $shared]);
echo "\n";
