<?php

namespace App\Traits;

trait Date {
    use Units;
    use Comparison;

    public function format($fmt) {
        return "formatted:" . $fmt;
    }
}
