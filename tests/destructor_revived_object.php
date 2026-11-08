<?php
// an object its destructor keeps alive lives on, and is freed later without
// a second destructor call, whether a plain release or the cycle collector
// found it
class Keeper {
    public static array $kept = [];
    public $self;
    public function __construct(public string $name, bool $cycle) { if ($cycle) $this->self = $this; }
    public function __destruct() { echo "destruct {$this->name}\n"; self::$kept[] = $this; }
}
$a = new Keeper('plain', false);
unset($a);
echo count(Keeper::$kept), " kept\n";
new Keeper('cycle', true);
echo 'collected ', gc_collect_cycles(), "\n";
echo count(Keeper::$kept), " kept\n";
Keeper::$kept = [];
echo 'collected after letting go ', gc_collect_cycles(), "\n";
echo "end\n";
