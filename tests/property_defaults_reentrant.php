<?php
// an instantiation while a class's property defaults are being evaluated
// (here from the autoloader the first default triggers) evaluates them
// again, so the inner object gets the real defaults too

class Base {
    public $inherited = Config::PREFIX . 'base';
}

class Widget extends Base {
    public $label = Config::PREFIX . 'widget';
    public static $count = Config::START;
    public $plain = 'plain';
}

$inner = null;
spl_autoload_register(function ($class) use (&$inner) {
    echo "autoload $class\n";
    if ($class === 'Config') {
        class Config {
            const PREFIX = 'cfg-';
            const START = 10;
        }
        $inner = new Widget();
    }
});

$outer = new Widget();
var_dump($inner, $outer);
var_dump(Widget::$count);
var_dump(new Widget() == $outer);
