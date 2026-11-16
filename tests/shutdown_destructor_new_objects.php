<?php
// objects a destructor makes while php destroys the remaining objects at
// shutdown are destructed too, after the ones that were there

class Cycle {
    public $self;
    public function __construct(public string $name) {
        $this->self = $this;
    }
    public function __destruct() {
        echo "destruct {$this->name}\n";
        if ($this->name === "first") {
            new Cycle("made by first");
            $GLOBALS["held"] = new Cycle("held global");
        }
        if ($this->name === "made by first") new Cycle("made by made");
    }
}

register_shutdown_function(function () {
    echo "shutdown\n";
});

new Cycle("first");
new Cycle("second");
echo "end of script\n";
