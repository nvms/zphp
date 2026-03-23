<?php

interface Printable {
    public function toString();
}

interface Loggable {
    public function log();
}

class User implements Printable, Loggable {
    public $name;

    public function __construct($name) {
        $this->name = $name;
    }

    public function toString() {
        return "User:" . $this->name;
    }

    public function log() {
        echo "log:" . $this->name . "\n";
    }
}

$u = new User("Alice");
echo $u->toString() . "\n";
$u->log();

// instanceof with interfaces
echo ($u instanceof Printable) ? "true" : "false";
echo "\n";
echo ($u instanceof Loggable) ? "true" : "false";
echo "\n";
echo ($u instanceof User) ? "true" : "false";
echo "\n";

// interface inheritance
interface Shape {
    public function area();
}

interface Drawable extends Shape {
    public function draw();
}

class Circle implements Drawable {
    public $r;

    public function __construct($r) {
        $this->r = $r;
    }

    public function area() {
        return 3.14159 * $this->r * $this->r;
    }

    public function draw() {
        return "circle(r=" . $this->r . ")";
    }
}

$c = new Circle(5);
echo $c->draw() . "\n";
echo ($c instanceof Drawable) ? "true" : "false";
echo "\n";
echo ($c instanceof Shape) ? "true" : "false";
echo "\n";

// inheritance + interface
class ColorCircle extends Circle {
    public $color;

    public function __construct($r, $color) {
        parent::__construct($r);
        $this->color = $color;
    }

    public function draw() {
        return "circle(r=" . $this->r . ",color=" . $this->color . ")";
    }
}

$cc = new ColorCircle(3, "red");
echo $cc->draw() . "\n";
echo ($cc instanceof Shape) ? "true" : "false";
echo "\n";
echo ($cc instanceof Drawable) ? "true" : "false";
echo "\n";
echo ($cc instanceof Circle) ? "true" : "false";
echo "\n";
