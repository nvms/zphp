<?php
// random engines refuse dynamic properties, and clone-with can't add one
foreach (['Random\Engine\Mt19937', 'Random\Engine\PcgOneseq128XslRr64', 'Random\Engine\Xoshiro256StarStar', 'Random\Engine\Secure'] as $class) {
    $engine = new $class();
    try {
        $engine->extra = 1;
    } catch (Error $e) {
        echo $e->getMessage(), "\n";
    }
    try {
        clone($engine, ['with' => 'something']);
    } catch (Error $e) {
        echo $e->getMessage(), "\n";
    }
}
