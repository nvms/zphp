<?php
interface HasLabel {
    public function label(): string;
}
enum Status implements HasLabel {
    case Active;
}
echo "unreachable\n";
