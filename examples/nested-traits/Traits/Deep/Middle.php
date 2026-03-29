<?php

namespace App\Traits\Deep;

trait Middle {
    use Core;

    public function middleMethod() {
        return "from-middle:" . $this->coreMethod();
    }
}
