<?php
function multi($n) {
    try {
        if ($n === 1) throw new RuntimeException("rt");
        if ($n === 2) throw new LogicException("lg");
        return "no-throw";
    } catch (RuntimeException | LogicException $e) {
        return "multi:" . get_class($e);
    }
}
echo multi(0), "\n";
echo multi(1), "\n";
echo multi(2), "\n";

function falls($n) {
    try {
        if ($n === 1) throw new InvalidArgumentException("ia");
        if ($n === 2) throw new RuntimeException("rt");
        return "ok";
    } catch (InvalidArgumentException $e) {
        return "ia";
    } catch (RuntimeException $e) {
        return "rt";
    } catch (Exception $e) {
        return "ex";
    }
}
echo falls(0), " ", falls(1), " ", falls(2), "\n";

function fin($n) {
    $log = "";
    try {
        $log .= "t";
        if ($n) throw new Exception("x");
        $log .= "T";
    } catch (Exception $e) {
        $log .= "c";
    } finally {
        $log .= "f";
    }
    return $log;
}
echo fin(0), " ", fin(1), "\n";

function rfin() {
    $log = "";
    try {
        return "from-try";
    } finally {
        $log = "fin-ran";
    }
}
echo rfin(), "\n";

function rfin2() {
    try {
        throw new Exception("x");
    } catch (Exception $e) {
        return "caught";
    } finally {
        echo "fin\n";
    }
}
echo rfin2(), "\n";

function rfin3() {
    try {
        return 1;
    } finally {
        return 2;
    }
}
echo rfin3(), "\n";

function rfin4() {
    try {
        try {
            throw new Exception("inner");
        } finally {
            echo "f1\n";
        }
    } catch (Exception $e) {
        echo "outer-c:", $e->getMessage(), "\n";
    } finally {
        echo "f2\n";
    }
    return "done";
}
echo rfin4(), "\n";

function chained() {
    try {
        try {
            throw new RuntimeException("first", 1);
        } catch (RuntimeException $e) {
            throw new LogicException("second", 2, $e);
        }
    } catch (LogicException $e) {
        $prev = $e->getPrevious();
        return $e->getMessage() . "/" . $prev->getMessage();
    }
}
echo chained(), "\n";

function deep() {
    try {
        throw new Exception("a", 0, new Exception("b", 0, new Exception("c")));
    } catch (Exception $e) {
        $msgs = [];
        $cur = $e;
        while ($cur !== null) {
            $msgs[] = $cur->getMessage();
            $cur = $cur->getPrevious();
        }
        return implode("/", $msgs);
    }
}
echo deep(), "\n";

function fthrow() {
    try {
        try {
            return "try-ret";
        } finally {
            throw new Exception("fin-throw");
        }
    } catch (Exception $e) {
        return "caught:" . $e->getMessage();
    }
}
echo fthrow(), "\n";

function fchain() {
    $log = "";
    try {
        try {
            throw new Exception("inner");
        } finally {
            $log .= "f1+";
            throw new RuntimeException("from-finally");
        }
    } catch (Exception $e) {
        $log .= "c:" . $e->getMessage();
    }
    return $log;
}
echo fchain(), "\n";

function nested() {
    try {
        try {
            try {
                throw new Exception("deep");
            } catch (LogicException $e) {
                return "logic";
            }
        } catch (RuntimeException $e) {
            return "runtime";
        }
    } catch (Exception $e) {
        return "exception:" . $e->getMessage();
    }
}
echo nested(), "\n";

function rethrow() {
    try {
        try {
            throw new Exception("x");
        } catch (Exception $e) {
            throw $e;
        }
    } catch (Exception $e) {
        return "outer:" . $e->getMessage();
    }
}
echo rethrow(), "\n";

function partial() {
    try {
        try {
            throw new RangeException("range");
        } catch (LogicException $e) {
            return "logic";
        }
    } catch (Exception $e) {
        return "ex:" . get_class($e);
    }
}
echo partial(), "\n";

function nofin() {
    try {
        return "ok";
    } catch (Exception $e) {
        return "caught";
    }
}
echo nofin(), "\n";

function loopfin($arr) {
    $log = "";
    foreach ($arr as $v) {
        try {
            if ($v === "t") throw new Exception("th");
            if ($v === "b") break;
            if ($v === "c") continue;
            $log .= $v;
        } catch (Exception $e) {
            $log .= "[caught]";
        } finally {
            $log .= ".";
        }
    }
    return $log;
}
echo loopfin(["a", "t", "b", "c", "d"]), "\n";

function leakthrow() {
    try {
        throw new Exception("leak");
    } catch (RuntimeException $e) {
        return "ok";
    }
    return "after";
}
try { echo leakthrow(), "\n"; }
catch (Exception $e) { echo "uncaught:" . $e->getMessage(), "\n"; }

function tryfin_break($arr) {
    $out = "";
    foreach ($arr as $v) {
        try {
            $out .= $v;
            if ($v === "b") break;
        } finally {
            $out .= "!";
        }
    }
    return $out;
}
echo tryfin_break(["a", "b", "c"]), "\n";

function tryfin_continue($arr) {
    $out = "";
    foreach ($arr as $v) {
        try {
            if ($v === "skip") continue;
            $out .= $v;
        } finally {
            $out .= ".";
        }
    }
    return $out;
}
echo tryfin_continue(["a", "skip", "c"]), "\n";

function genfin() {
    try {
        yield 1;
        yield 2;
    } finally {
        echo "gen-fin\n";
    }
}
foreach (genfin() as $v) echo $v, " ";
echo "\n";

// generator finally on partial-consume / gc-finalize (architectural - zphp doesn't dispose generators)
