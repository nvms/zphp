<?php

namespace App\Traits;

trait Units {
    public function isModifiableUnit($unit) {
        return in_array($unit, ['year', 'month', 'day', 'hour', 'minute', 'second']);
    }

    public function getUnitName() {
        return "time-unit";
    }
}
