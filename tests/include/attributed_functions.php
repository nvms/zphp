<?php
#[Attribute(Attribute::TARGET_ALL)]
class Tagged { function __construct(public $label = null) {} }

#[Tagged('function')]
function included_function(#[Tagged(PHP_INT_SIZE)] $size, #[SensitiveParameter] $secret) {}

function make_included_closure() {
    return #[Tagged('closure')] fn (#[Tagged('param')] $x) => $x;
}
