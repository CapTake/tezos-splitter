#include "../partial/fa2_errors.ligo"

type token_id is nat
type operator is address
type owner is address

type operator_storage is big_map((owner * operator), unit)

type ledger is big_map(owner, nat)

type tx is michelson_pair(address, "to_", michelson_pair(nat, "token_id", nat, "amount"), "")

type txList is list (tx)

type transfer_batch is michelson_pair(address, "from_", txList, "txs")

type transfer_param is list (transfer_batch)

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

type operator_param is [@layout:comb] record [
  owner : address;
  operator : address;
  token_id: nat;
]

type update_operator is
[@layout:comb]
  | Add_operator of operator_param
  | Remove_operator of operator_param

type update_operators_param is list (update_operator)

type withdraw_token_param is record [
  kt : address;
  token_id : nat;
  total_balance : nat;
]

type token_meta is record [
  token_id   : nat;
  token_info : map (string, bytes);
];

type storage is record [
    credit         : tez; // sum of tz withdrawn
    debits         : big_map (owner, tez); // owner shares * debit
    token_credits  : big_map (address * nat, nat);
    token_debits   : big_map (address * nat * owner, nat);
    ledger         : ledger;
    metadata       : big_map (string, bytes);
    operators      : operator_storage;
    token_metadata : big_map (token_id, token_meta);
    total_supply   : nat;
]

type action is
  | Balance_of of balance_of_params
  | Default
  | Set_delegate of option(key_hash)
  | Transfer of transfer_param
  | Update_operators of update_operators_param
  | Withdraw_tez
  | Withdraw_token of withdraw_token_param

 type return is list (operation) * storage

 const noop : list (operation) = (nil: list (operation))
 const cTOKEN_ID : nat = 0n

//////////////// HELPERS ////////////////////////////////////
  
  function get_balance(const owner : owner; const s : storage) : nat is 
    case s.ledger[owner] of [
      | None -> 0n
      | Some(a) -> a
    ]

  function get_debit(const owner : owner; const s : storage) : tez is
    case s.debits[owner] of [
      | None -> 0tz
      | Some(a) -> a
    ]

//////////////////////// FA2 FUNCTIONS ////////////////////////////
function iterate_transfer (var s : storage; const batch : transfer_batch) : storage is {
    const from_ : owner = batch.0;
      (* Perform single transfer *)
    function make_transfer(var s : storage; const tx : tx) : storage is {
        assert_with_error(tx.1.0 = cTOKEN_ID, fa2_token_undefined);
          
        assert_with_error(from_ = Tezos.get_sender() or Big_map.mem((from_, Tezos.get_sender()), s.operators), fa2_not_operator);

          (* transfer only to different address, and not 0 amount, but not fail *)
        var sender_balance : nat := get_balance(from_, s);

        assert_with_error(sender_balance >= tx.1.1, fa2_insufficient_balance);

        if (from_ = tx.0) or (tx.1.1 = 0n) then skip else {
          
            var sender_debit : tez := get_debit(from_, s);

            var dest_balance : nat := get_balance(tx.0, s);
            var dest_debit : tez := get_debit(tx.0, s);

            const debit_transfer : tez = (sender_debit * tx.1.1) / sender_balance;

            sender_debit := Option.unopt(sender_debit - debit_transfer);

            sender_balance := abs(sender_balance - tx.1.1);
                
            if sender_balance > 0n then s.ledger[from_] := sender_balance else s.ledger := Big_map.remove(from_, s.ledger);

            if sender_debit > 0tz then s.debits[from_] := sender_debit else s.debits := Big_map.remove(from_, s.debits);

            s.ledger[tx.0] := dest_balance + tx.1.1;
            s.debits[tx.0] := dest_debit + debit_transfer;
        };
    } with s;
} with (List.fold(make_transfer, batch.1, s))

function fa2_transfer(const jobs : list(transfer_batch); var s : storage) : return is (noop, List.fold(iterate_transfer, jobs, s))

function update_operator (var s : storage; const p : update_operator) : storage is {
    case p of [
        | Add_operator(param) -> {
          (* Token id check *)
          assert_with_error(param.token_id = cTOKEN_ID, fa2_token_undefined);
          assert_with_error(Tezos.get_sender() = param.owner, fa2_not_owner);
          s.operators[(param.owner, param.operator)] := unit
        }
        | Remove_operator(param) -> {
          assert_with_error(param.token_id = cTOKEN_ID, fa2_token_undefined);
          assert_with_error(Tezos.get_sender() = param.owner, fa2_not_owner);
          s.operators := Big_map.remove((param.owner, param.operator), s.operators);
        }
    ];
} with s

function fa2_update_operators(const commands : list (update_operator); var s : storage) : return is
    (noop, List.fold(update_operator, commands, s))

function fa2_balance_of(const params : balance_of_params; const s : storage) : return is {
    function get_balance_response (const r : balance_of_request) : balance_of_response is
      record[
        balance = get_balance(r.owner, s);
        request = r;
      ];
} with (list [Tezos.transaction(List.map(get_balance_response, params.requests), 0tz, params.callback)], s)

function withdraw_tez(var s : storage) : return is {
    const share : nat = get_balance(Tezos.get_sender(), s);

    assert_with_error(share > 0n, "NOT_A_SHAREHOLDER");

    const debit : tez = get_debit(Tezos.get_sender(), s);

    var take : tez := ((Tezos.get_balance() + s.credit) * share) / s.total_supply;

    assert_with_error(take > debit, "LIMIT REACHED");

    take := Option.unopt(take - debit);
      
    s.credit := s.credit + take;

    s.debits[Tezos.get_sender()] := debit + take;

    const to_ : contract(unit) = case Tezos.get_contract_opt(Tezos.get_sender()) of [
      | None -> (failwith("NO_CONTRACT") : contract(unit))
      | Some (c) -> c
    ];
} with (list[Tezos.transaction(Unit, take, to_)], s);

function withdraw_token(const p : withdraw_token_param; var s : storage) : return is {
    const share : nat = get_balance(Tezos.get_sender(), s);

    assert_with_error(share > 0n, "NOT_A_SHAREHOLDER");

    const debit : tez = get_debit(Tezos.get_sender(), s);

    var take : tez := ((Tezos.get_balance() + s.credit) * share) / s.total_supply;

    assert_with_error(take > debit, "LIMIT REACHED");

    take := Option.unopt(take - debit);
      
    s.credit := s.credit + take;

    s.debits[Tezos.get_sender()] := debit + take;

    const to_ : contract(unit) = case Tezos.get_contract_opt(Tezos.get_sender()) of [
      | None -> (failwith("NO_CONTRACT") : contract(unit))
      | Some (c) -> c
    ];
} with (list[Tezos.transaction(Unit, take, to_)], s);
  
function delegate(const d : option(key_hash); const s : storage): return is
    if get_balance(Tezos.get_sender(), s) = 0n then failwith("NOT_ALLOWED") else (list[Tezos.set_delegate(d)], s)

function main(const action : action; var s : storage) : return is
  case action of [
    | Balance_of(p) -> fa2_balance_of(p, s)
    | Default -> (noop, s)
    | Set_delegate(p) -> delegate(p, s)
    | Transfer(p) -> fa2_transfer(p, s)
    | Update_operators(p) -> fa2_update_operators(p, s)
    | Withdraw_tez -> withdraw_tez(s)
 ]

[@view]
function balance_of(const p : list(balance_of_request); const s : storage) : list(balance_of_response) is {
    function get_balance_resp (const r : balance_of_request) : balance_of_response is
      record[
        request = r;
        balance = get_balance(r.owner, s);
      ];
} with List.map(get_balance_resp, p)
