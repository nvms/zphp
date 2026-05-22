<?php

// a small ActiveRecord-flavored base. its factory and query methods return
// `static`, so a subclass gets instances of itself without overriding
// anything - the whole point of late static binding

trait Timestamped
{
    // static:: inside a trait method resolves to the class using the trait,
    // never the trait itself
    public function describe(): string
    {
        return static::class . ' is a ' . static::kind();
    }
}

abstract class Model
{
    // redeclared in each subclass, so static::$rows binds to per-class
    // storage rather than one shared array
    protected static array $rows = [];

    public function __construct(protected array $attrs)
    {
    }

    abstract public static function kind(): string;

    // new static() builds an instance of the called class, not Model
    public static function make(array $attrs): static
    {
        $obj = new static($attrs);
        static::$rows[] = $obj;
        return $obj;
    }

    public static function count(): int
    {
        return count(static::$rows);
    }

    public static function first(): ?static
    {
        return static::$rows[0] ?? null;
    }

    public function get(string $key): mixed
    {
        return $this->attrs[$key] ?? null;
    }

    // self:: is fixed to the defining class (Model); static:: follows the
    // class the method was actually called on
    public function lineage(): string
    {
        return self::class . ' -> ' . static::class;
    }

    public static function tag(): string
    {
        return 'model';
    }

    // a closure created inside a static method must still resolve static::
    // against the called class when it runs later
    public static function decorateAll(array $labels): array
    {
        return array_map(fn ($label) => static::kind() . ':' . $label, $labels);
    }
}
