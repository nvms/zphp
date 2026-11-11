<?php
// continue aimed at a switch is break, with php's compile-time warning
for ($i = 0; $i < 3; $i++) {
    switch ($i) {
        case 1:
            continue;
        default:
            echo $i, "\n";
    }
    echo "after $i\n";
}
switch (1) {
    case 1:
        foreach ([1, 2] as $v) {
            switch ($v) {
                case 1:
                    continue 2;
            }
            echo "v $v\n";
        }
        continue;
}
while (true) {
    while (true) {
        break 2;
    }
}
echo "done\n";
