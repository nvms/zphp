<?php
class HookSequence {
    public $backed = 20 {
        get {
            yield 10;
            yield $this->backed;
            yield 30;
            return 'finished';
        }
    }
    public $virtual {
        get { yield from [4, 5]; }
    }
    public $short {
        get => yield 9;
    }
    public $factory {
        get {
            return function () { yield 6; };
        }
    }
}
$sequence = new HookSequence();
$generator = $sequence->backed;
var_dump($generator instanceof Generator);
var_dump(iterator_to_array($generator));
var_dump($generator->getReturn());
var_dump(iterator_to_array($sequence->virtual));
var_dump(iterator_to_array($sequence->short));
$factory = $sequence->factory;
var_dump(iterator_to_array($factory()));
// Hook yields must not turn the containing function into a generator.
function createHookSequence() {
    class LocalHookSequence {
        public $items { get { yield 8; } }
    }
    return new LocalHookSequence();
}
var_dump(iterator_to_array(createHookSequence()->items));
