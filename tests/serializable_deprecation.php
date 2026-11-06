<?php
// implementing Serializable without __serialize and __unserialize is
// deprecated when the class is linked; declared conditionally here so the
// classes link after error reporting is set
error_reporting(E_ALL);
set_error_handler(function ($level, $message, $file, $line) {
    echo $level === E_DEPRECATED ? "deprecated" : $level, " at line $line: $message\n";
    return true;
});

if (true) {
    class OldStyle implements Serializable {
        function serialize() { return ''; }
        function unserialize($s) {}
    }
    class InheritsOldStyle extends OldStyle {}
    abstract class AbstractOldStyle implements Serializable {}
    class Both implements Serializable {
        function serialize() { return ''; }
        function unserialize($s) {}
        function __serialize(): array { return []; }
        function __unserialize(array $data): void {}
    }
    class OnlyHalf implements Serializable {
        function serialize() { return ''; }
        function unserialize($s) {}
        function __serialize(): array { return []; }
    }
    class FromArrayObject extends ArrayObject {}
}
echo "declared\n";
