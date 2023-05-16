type splitter_storage is [@layout:comb] record[
    total : nat;
    shares : map(address, nat);
]
