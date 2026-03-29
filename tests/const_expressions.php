<?php

// class constant expressions referencing self::
class MathConst {
    const A = 60;
    const B = 24;
    const C = self::A * self::B;
    const D = self::A + self::B;
    const E = self::A - 10;
    const F = 100;
    const G = self::F / 2;
}

echo MathConst::C . "\n"; // 1440
echo MathConst::D . "\n"; // 84
echo MathConst::E . "\n"; // 50
echo MathConst::G . "\n"; // 50

// interface constants
interface TimeConst {
    const SECONDS_PER_MINUTE = 60;
    const MINUTES_PER_HOUR = 60;
    const HOURS_PER_DAY = 24;
    const SECONDS_PER_HOUR = self::SECONDS_PER_MINUTE * self::MINUTES_PER_HOUR;
}

echo TimeConst::SECONDS_PER_HOUR . "\n"; // 3600

// interface extends interface - constant inheritance
interface Parent1 {
    const X = 10;
    const Y = 20;
}

interface Parent2 {
    const Z = 30;
}

interface Child extends Parent1, Parent2 {
    const W = 40;
}

echo Child::X . "\n"; // 10
echo Child::Y . "\n"; // 20
echo Child::Z . "\n"; // 30
echo Child::W . "\n"; // 40

// class implements interface with constants
class Impl implements TimeConst {
    public function getSecondsPerHour() {
        return self::SECONDS_PER_HOUR;
    }
}

echo (new Impl())->getSecondsPerHour() . "\n"; // 3600
echo Impl::SECONDS_PER_MINUTE . "\n"; // 60

// static:: access to interface constants
class Base implements TimeConst {
    public static function getMinutesPerHour() {
        return static::MINUTES_PER_HOUR;
    }
}
echo Base::getMinutesPerHour() . "\n"; // 60

// chained self:: references
class Chain {
    const STEP1 = 2;
    const STEP2 = self::STEP1 * 3;
    const STEP3 = self::STEP2 * 5;
    const STEP4 = self::STEP3 + self::STEP1;
}
echo Chain::STEP3 . "\n"; // 30
echo Chain::STEP4 . "\n"; // 32

// literal expressions (always worked, regression check)
class Literal {
    const A = 2 * 3;
    const B = 10 + 5;
}
echo Literal::A . "\n"; // 6
echo Literal::B . "\n"; // 15
