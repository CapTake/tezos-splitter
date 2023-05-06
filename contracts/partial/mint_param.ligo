type mint_param is [@layout:comb] record [
  amount     : nat;
  target     : address;
  token_id   : nat;
  token_info : map(string, bytes);
]
