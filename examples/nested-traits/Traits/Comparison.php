<?php

namespace App\Traits;

trait Comparison {
    public function isEqual($other) {
        return $this->value === $other->value;
    }
}
