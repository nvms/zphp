<?php
function returnInTry(): string {
    try {
        return "try";
    } finally {
        echo "finally1\n";
    }
}
echo returnInTry(), "\n";

function returnInFinally(): string {
    try {
        return "try";
    } finally {
        return "finally";
    }
}
echo returnInFinally(), "\n";

function exceptionInTry(): string {
    try {
        throw new Exception("err");
    } catch (Exception $e) {
        return "caught:" . $e->getMessage();
    } finally {
        echo "f-runs\n";
    }
}
echo exceptionInTry(), "\n";

function breakInLoopFinally(): void {
    for ($i = 0; $i < 5; $i++) {
        try {
            if ($i === 2) break;
            echo $i, " ";
        } finally {
            echo "f($i) ";
        }
    }
    echo "\n";
}
breakInLoopFinally();

function continueInLoopFinally(): void {
    for ($i = 0; $i < 5; $i++) {
        try {
            if ($i === 2) continue;
            echo $i, " ";
        } finally {
            echo "f($i) ";
        }
    }
    echo "\n";
}
continueInLoopFinally();

function returnInLoopFinally(): int {
    for ($i = 0; $i < 5; $i++) {
        try {
            if ($i === 2) return $i;
        } finally {
            echo "f($i) ";
        }
    }
    return -1;
}
echo "\n", returnInLoopFinally(), "\n";

function nestedTryFinally(): string {
    try {
        try {
            return "inner";
        } finally {
            echo "inner-f\n";
        }
    } finally {
        echo "outer-f\n";
    }
}
echo nestedTryFinally(), "\n";

function nestedReturnOverride(): string {
    try {
        try {
            return "inner";
        } finally {
            return "inner-finally";
        }
    } finally {
        return "outer-finally";
    }
}
echo nestedReturnOverride(), "\n";

function exceptionInFinally(): string {
    try {
        try {
            return "try";
        } finally {
            throw new Exception("from-finally");
        }
    } catch (Exception $e) {
        return "caught:" . $e->getMessage();
    }
}
echo exceptionInFinally(), "\n";

function finallyInGen(): Generator {
    try {
        yield 1;
        yield 2;
    } finally {
        echo "gen-f\n";
    }
}
$g = finallyInGen();
foreach ($g as $v) echo $v, " ";
echo "\n";

function loopFinally(): array {
    $out = [];
    for ($i = 0; $i < 4; $i++) {
        try {
            $out[] = $i;
        } finally {
            $out[] = "f$i";
        }
    }
    return $out;
}
print_r(loopFinally());

function continueInOuterFinally(): array {
    $out = [];
    for ($i = 0; $i < 3; $i++) {
        try {
            $out[] = $i;
            if ($i === 1) continue;
            $out[] = "after-$i";
        } finally {
            $out[] = "f$i";
        }
    }
    return $out;
}
print_r(continueInOuterFinally());

function multipleFinally(): void {
    try {
        try {
            try {
                echo "1 ";
            } finally {
                echo "2 ";
            }
        } finally {
            echo "3 ";
        }
    } finally {
        echo "4\n";
    }
}
multipleFinally();

function throwFromCatch(): string {
    try {
        try {
            throw new Exception("e1");
        } catch (Exception $e) {
            throw new RuntimeException("e2");
        } finally {
            echo "inner-f\n";
        }
    } catch (RuntimeException $r) {
        return "got:" . $r->getMessage();
    }
}
echo throwFromCatch(), "\n";

function finallyModifiesReturn(): int {
    try {
        return 10;
    } finally {
        echo "f\n";
    }
}
echo finallyModifiesReturn(), "\n";

class WithCleanup {
    public function process(): array {
        $log = [];
        try {
            $log[] = "process";
        } catch (\Throwable $e) {
            $log[] = "caught";
        } finally {
            $log[] = "cleanup";
        }
        return $log;
    }
}
print_r((new WithCleanup)->process());

function finallySwallowsException(): string {
    try {
        try {
            throw new Exception("orig");
        } finally {
            return "swallowed";
        }
    } catch (Exception $e) {
        return "caught:" . $e->getMessage();
    }
}
echo finallySwallowsException(), "\n";

