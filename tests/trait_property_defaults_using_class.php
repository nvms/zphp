<?php
// a trait property's default naming self:: or __CLASS__ is evaluated for
// each class using the trait
trait Named {
    public static $static_name = __CLASS__;
    public $name = __CLASS__;
    public $limit = self::LIMIT * 2;
    protected static $limits = [self::LIMIT, 'x' => self::LIMIT + 1];
    public $plain = 5;

    public static function limits() { return self::$limits; }
}
trait Indirect {
    use Named;
}
class First {
    use Named;
    const LIMIT = 10;
}
class Second {
    use Indirect;
    const LIMIT = 3;
}

// statics read before any instance
var_dump(First::$static_name, Second::$static_name, First::limits(), Second::limits());
var_dump(new First, new Second);
var_dump((new ReflectionClass('Second'))->getDefaultProperties());

// two traits with the same default agree once evaluated
trait T1 { public $x = self::X; }
trait T2 { public $x = self::X; }
class Both {
    use T1, T2;
    const X = 42;
}
var_dump((new Both)->x);

// a class redeclaring the property with the same value
trait WithY { public $y = self::Y; }
class Own {
    use WithY;
    const Y = 'y';
    public $y = 'y';
}
var_dump((new Own)->y);

require __DIR__ . '/fixtures/trait_class_defaults.inc';
class Third {
    use ElsewhereDefaults;
    const LABEL = 'third';
}
class Fourth {
    use ElsewhereDefaults;
    const LABEL = 'fourth';
}
var_dump(new Third, Fourth::$owner, (new Fourth)->pair, Third::$owner);
