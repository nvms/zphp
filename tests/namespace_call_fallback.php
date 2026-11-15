<?php
// only an unqualified function name in a namespace falls back to the global
// function; a qualified, fully qualified, imported or dynamic name doesn't

namespace {
    function helper() { return "global helper"; }
}

namespace Lib {
    function own() { return "Lib\\own"; }
    function pair($a, $b) { return "$a-$b"; }
}

namespace App {
    use function Lib\own;
    use function Lib\missing;
    use function Lib\OWN as shout;
    use function Lib\pair;

    echo helper(), "\n";
    echo strlen("abc"), "\n";
    echo own(), "\n";
    echo shout(), "\n";
    echo \Lib\own(), "\n";
    echo pair(b: 2, a: 1), " ", \Lib\pair(...['b' => 4, 'a' => 3]), " ", \strlen(string: "abcd"), "\n";

    $calls = [
        fn () => missing(),
        fn () => Sub\helper(),
        fn () => \App\helper(),
        fn () => ('App\\helper')(),
        function () { $f = 'App\\strlen'; return $f('x'); },
        fn () => call_user_func('App\\helper'),
    ];
    foreach ($calls as $call) {
        try {
            var_dump($call());
        } catch (\Error $e) {
            echo get_class($e), ": ", $e->getMessage(), "\n";
        }
    }
    var_dump(function_exists('App\\helper'), is_callable('App\\helper'));
}
