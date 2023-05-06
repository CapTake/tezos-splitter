function nat_to_bytes(var i : nat) : bytes is {
    const digits : bytes = 0x30313233343536373839;
    var s : bytes := 0x30;
    while i =/= 0n {
      s := Bytes.concat(Bytes.sub(i mod 10n, 1n, digits), s);
      i := i / 10n;
    };
    const len : nat = abs(Bytes.length(s) - 1);
} with if len = i then s else Bytes.sub(0n, len, s)