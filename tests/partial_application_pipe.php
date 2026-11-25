<?php
// built from php 8.6.0's Zend/tests/partial_application/*.phpt, one
// namespace per test

namespace pfa\pipe_optimization_001 {
    echo "# pipe_optimization_001\n";
    if (time() > 0) {
        function foo($a) {
            var_dump($a);
        }
    }

    1 |> foo(?);
}

namespace pfa\pipe_optimization_002 {
    echo "# pipe_optimization_002\n";
    if (time() > 0) {
        function foo($a, $b) {
            var_dump($a, $b);
        }
    }

    2 |> foo(1, ?);
}

namespace pfa\pipe_optimization_003 {
    echo "# pipe_optimization_003\n";
    if (time() > 0) {
        function foo($a, $b) {
            var_dump($a, $b);
        }
    }

    2 |> foo(?, 1);
}

namespace pfa\pipe_optimization_004 {
    echo "# pipe_optimization_004\n";
    if (time() > 0) {
        function foo($a, $b) {
            var_dump($a, $b);
        }
    }

    try {
        2 |> foo(?, ?);
    } catch (\Throwable $e) {
        echo $e::class, ": ", $e->getMessage(), "\n";
    }
}

namespace pfa\pipe_optimization_005 {
    echo "# pipe_optimization_005\n";
    if (time() > 0) {
        function foo($a, $b) {
            var_dump($a, $b);
        }
    }

    2 |> foo(1, ...);
}

namespace pfa\pipe_optimization_006 {
    echo "# pipe_optimization_006\n";
    if (time() > 0) {
        function foo($a, $b = null, $c = null) {
            var_dump($a, $b, $c);
        }
    }

    2 |> foo(1, c: ?);
}

namespace pfa\pipe_optimization_007 {
    echo "# pipe_optimization_007\n";
    if (time() > 0) {
        function foo($a, $b) {
            var_dump($a, $b);
        }
    }

    try {
        2 |> foo(a: ?, b: ?);
    } catch (\Throwable $e) {
        echo $e::class, ": ", $e->getMessage(), "\n";
    }
}

namespace pfa\pipe_optimization_008 {
    echo "# pipe_optimization_008\n";
    if (time() > 0) {
        function foo($a, $b) {
            var_dump($a, $b);
        }
    }

    try {
        2 |> foo(a: 1, ...);
    } catch (\Throwable $e) {
        echo $e->getMessage(), "\n";
    }
}

namespace pfa\pipe_optimization_009 {
    echo "# pipe_optimization_009\n";
    if (time() > 0) {
        function foo($a, $b, $c) {
            var_dump($a, $b, $c);
        }
        function lhs() {
            echo __FUNCTION__, "\n";
            return 0;
        }
        function arg1() {
            echo __FUNCTION__, "\n";
            return 1;
        }
        function arg2() {
            echo __FUNCTION__, "\n";
            return 2;
        }
    }

    lhs() |> foo(arg1(), ?, arg2());
}

namespace pfa\pipe_optimization_010 {
    echo "# pipe_optimization_010\n";
    if (time() > 0) {
        function foo(&$a, $b) {
            var_dump($a, $b);
            $a = 2;
        }
    }

    1 |> foo($a, ?);
    var_dump($a);
}

namespace pfa\pipe_optimization_011 {
    echo "# pipe_optimization_011\n";
    if (time() > 0) {
        function foo($a, $b, $c) {
            var_dump($a, $b, $c);
        }
        function arg1() {
            global $a;
            $a = 2;
            echo __FUNCTION__, "\n";
            return 1;
        }
        function arg2() {
            global $a;
            $a = 3;
            echo __FUNCTION__, "\n";
            return 2;
        }
    }

    $a = 0;
    $a |> foo(arg1(), ?, arg2());
}

namespace pfa\pipe_optimization_012 {
    echo "# pipe_optimization_012\n";
    if (time() > 0) {
        function foo($a, $b) {
            var_dump($a, $b);
        }
    }

    1 |> foo(?, b: 2);
}

namespace pfa\pipe_optimization_013 {
    echo "# pipe_optimization_013\n";
    if (time() > 0) {
        function foo($a, $b) {
            var_dump($a, $b);
        }
    }

    1 |> foo(b: 2, ...);
}

namespace pfa\pipe_optimization_014 {
    echo "# pipe_optimization_014\n";
    if (time() > 0) {
        function foo($a, $b = null, $c = null) {
            var_dump($a, $b, $c);
        }
    }

    try {
        2 |> foo(1, unknown: ?);
    } catch (Error $e) {
        echo $e::class, ": ", $e->getMessage(), "\n";
    }
}

namespace pfa\pipe_optimization_015 {
    echo "# pipe_optimization_015\n";
    if (time() > 0) {
        function foo($a, $b = null, $c = null) {
            var_dump($a, $b, $c);
        }
    }

    3 |> foo(1, c: ?);
}
