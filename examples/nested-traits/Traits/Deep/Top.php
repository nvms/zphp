<?php

namespace App\Traits\Deep;

trait Top {
    use Middle;

    public function topMethod() {
        return "from-top:" . $this->middleMethod();
    }
}
