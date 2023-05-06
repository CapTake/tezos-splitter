type amt is nat
type token_id is nat
type operator is address
type owner is address

type ledger is big_map(owner * token_id, amt)

type tx is [@layout:comb] record [
    to_       : address;
    token_id  : token_id;
    amount    : nat;
  ]

type transfer_param is [@layout:comb] record [
    from_   : address;
    txs     : list (tx);
  ]

type balance_of_request is [@layout:comb] record [
    owner       : address;
    token_id    : token_id;
  ]

type balance_of_response is [@layout:comb] record [
    request     : balance_of_request;
    balance     : nat;
  ]

type balance_of_params is [@layout:comb] record [
    requests    : list (balance_of_request);
    callback    : contract (list (balance_of_response));
  ]

type transfer_params is list (transfer_param)

type operator_param is [@layout:comb] record [
  owner : address;
  operator : address;
  token_id: nat;
]

type operator_storage is big_map(operator_param, unit)

type update_operator is [@layout:comb]
  | Add_operator of operator_param
  | Remove_operator of operator_param

type update_operator_params is list (update_operator)

type token_meta is [@layout:comb] record [
  token_id   : nat;
  token_info : map (string, bytes);
]

type fa2_action is
  | Balance_of of balance_of_params
  | Transfer of transfer_params
  | Update_operators of update_operator_params