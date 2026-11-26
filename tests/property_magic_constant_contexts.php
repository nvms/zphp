<?php
// __PROPERTY__ names the property in its default value, its attributes,
// its hooks' attributes and its set hook parameter's attributes; a hooked
// property keeps its own attributes

#[Attribute(Attribute::TARGET_ALL)]
class Note {
    public function __construct(public string $msg) {}
}

class Item {
    #[Note(msg: __PROPERTY__)]
    public string $title = __PROPERTY__ {
        #[Note(msg: __PROPERTY__ . ' get')]
        get {
            return $this->title . ' via ' . __PROPERTY__;
        }
        set (#[Note(msg: __PROPERTY__ . ' value')] string $v) {
            $this->title = $v;
        }
    }

    #[Note('plain')]
    public string $label = 'label' {
        get => $this->label;
    }

    #[Note(msg: __PROPERTY__)]
    public string $code = __PROPERTY__ . '!';

    public static string $shared = __PROPERTY__;

    public array $list = [__PROPERTY__, 'x' => __PROPERTY__ . 'y'];
}

$item = new Item;
var_dump($item->title, $item->label, $item->code, Item::$shared, $item->list);

$class = new ReflectionClass(Item::class);
foreach (['title', 'label', 'code', 'shared', 'list'] as $name) {
    $prop = $class->getProperty($name);
    $args = array_map(fn($a) => $a->getArguments(), $prop->getAttributes());
    echo $name, ': ', json_encode($args), "\n";
}

$title = $class->getProperty('title');
var_dump($title->getHook(PropertyHookType::Get)->getAttributes()[0]->getArguments());
var_dump($title->getHook(PropertyHookType::Set)->getParameters()[0]->getAttributes()[0]->newInstance()->msg);

// outside a property it is empty
var_dump(__PROPERTY__);
function f() { return __PROPERTY__; }
var_dump(f());
