<?php

#[Attribute]
class Config {
    public function __construct(
        public string $name = '',
        public int $priority = 0,
        public bool $active = true
    ) {}
}

// named args
#[Config(priority: 10, name: 'test')]
class MyService {}

$rc = new ReflectionClass('MyService');
$attrs = $rc->getAttributes();
echo count($attrs) . "\n";
$args = $attrs[0]->getArguments();
echo $args['priority'] . "\n";
echo $args['name'] . "\n";

// newInstance with named args
$instance = $attrs[0]->newInstance();
echo $instance->name . "\n";
echo $instance->priority . "\n";
echo var_export($instance->active, true) . "\n";

// getAttributes filtering
#[Attribute]
class Meta {
    public function __construct(public string $tag = '') {}
}

#[Config(name: 'a')]
#[Meta(tag: 'b')]
class Multi {}

$rc3 = new ReflectionClass('Multi');
echo count($rc3->getAttributes()) . "\n";
echo count($rc3->getAttributes('Config')) . "\n";
echo count($rc3->getAttributes('Meta')) . "\n";
echo count($rc3->getAttributes('NonExistent')) . "\n";

// class constant in attribute arg
class Modes {
    const DEBUG = 1;
    const PRODUCTION = 2;
}

#[Config(priority: Modes::DEBUG)]
class DebugService {}

$rc4 = new ReflectionClass('DebugService');
$args4 = $rc4->getAttributes()[0]->getArguments();
echo $args4['priority'] . "\n";

// isRepeated
#[Config(name: 'x')]
#[Config(name: 'y')]
class Repeated {}

$rc5 = new ReflectionClass('Repeated');
$rattrs = $rc5->getAttributes();
echo count($rattrs) . "\n";
echo var_export($rattrs[0]->isRepeated(), true) . "\n";

// getTarget
echo $rattrs[0]->getTarget() . "\n";
