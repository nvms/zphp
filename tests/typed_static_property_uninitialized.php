<?php
// a typed static property without a default is uninitialized until assigned

class Counter
{
    public static int $count;
    public static ?string $label;
    protected static int $hidden;
    public static int $set = 1;
    public int $instance;
    public ?int $withDefault = null;

    public static function hidden() { return self::$hidden; }
}

function attempt(callable $f): void
{
    try {
        var_dump($f());
    } catch (Error $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}

attempt(fn () => Counter::$count);
attempt(fn () => Counter::$label);
attempt(fn () => Counter::hidden());
var_dump(isset(Counter::$count), Counter::$label ?? "none");
var_dump(get_class_vars(Counter::class));
$rc = new ReflectionClass(Counter::class);
var_dump($rc->getStaticProperties());
attempt(fn () => $rc->getStaticPropertyValue('count'));
attempt(fn () => Counter::$count++);
Counter::$count = 5;
Counter::$count += 2;
Counter::$label = null;
var_dump(Counter::$count, Counter::$label, $rc->getStaticProperties());
