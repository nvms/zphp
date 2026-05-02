<?php

// return inside finally overrides return inside try
function overrideReturn(): int {
    try {
        return 1;
    } finally {
        return 2;
    }
}
echo "overridden: " . overrideReturn() . "\n";
echo "stored: " . (overrideReturn() + 0) . "\n";

// return inside finally overrides return inside catch
function overrideCatch(): string {
    try {
        throw new RuntimeException('boom');
    } catch (Throwable $e) {
        return $e->getMessage();
    } finally {
        return 'finally-wins';
    }
}
echo "catch-override: " . overrideCatch() . "\n";

// nested try/finally; inner return triggers outer finally
function nestedFinally(): int {
    try {
        try {
            return 1;
        } finally {
            echo "[inner] ";
        }
    } finally {
        echo "[outer] ";
    }
}
echo "nested: " . nestedFinally() . "\n";

// finally preserves return when no return in finally
function passThrough(): int {
    try {
        return 7;
    } finally {
        echo "[no-override] ";
    }
}
echo "pass: " . passThrough() . "\n";
