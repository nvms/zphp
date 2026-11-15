<?php
// a pipe is a call, which a list() assignment cannot write to
echo "never printed\n";
[$a, strlen(...) |> f] = [1, 2];
