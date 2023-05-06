#include "../partial/fa2_types.ligo"
#include "../partial/fa2_errors.ligo"
#include "../partial/mint_param.ligo"

 type storage is record [
    admin          : address;
    minters        : set(address);
    ledger         : ledger;
    metadata       : big_map (string, bytes);
    operators      : big_map (operator_param, unit);
    token_metadata : big_map (token_id, token_meta);
 ]

type return is list (operation) * storage

type update_minter_param is
  | Add_minter of address
  | Remove_minter of address

type action is
  | Balance_of of balance_of_params
  | Mint of mint_param
  | Transfer of transfer_params
  | Update_minters of update_minter_param
  | Update_operators of update_operator_params

const noop : list (operation) = (nil: list (operation))
const error_access_denied = "Access denied"

  [@inline]
  function get_balance(const owner : owner; const token_id : token_id; const s : storage) : amt is
    case s.ledger[(owner, token_id)] of [
      | None -> 0n
      | Some(a) -> a
    ]

  [@inline]
  function iterate_transfer (var s : storage; const param : transfer_param) : storage is block {
      const from_ : owner = param.from_;
      (* Perform single transfer *)
      function make_transfer(var s : storage; const tx : tx) : storage is block {
          assert_with_error(Big_map.mem(tx.token_id, s.token_metadata), fa2_token_undefined);
          assert_with_error(from_ = Tezos.sender or Big_map.mem(record[owner=from_; operator=Tezos.sender; token_id=tx.token_id], s.operators), fa2_not_operator);
          var sender_balance : amt := get_balance(from_, tx.token_id, s);
          assert_with_error(sender_balance >= tx.amount, fa2_insufficient_balance);

          if (from_ = tx.to_) or (tx.amount = 0n) then skip else {
            const dest_balance : amt = get_balance(tx.to_, tx.token_id, s);

            if sender_balance = tx.amount then s.ledger := Big_map.remove((from_, tx.token_id), s.ledger)
            else s.ledger[(from_, tx.token_id)] := abs(sender_balance - tx.amount);

            s.ledger[(tx.to_, tx.token_id)] := dest_balance + tx.amount;
          };
      } with s;
    } with (List.fold(make_transfer, param.txs, s))

  function fa2_transfer(const p : transfer_params; var s : storage) : return is 
    (noop, List.fold(iterate_transfer, p, s))

  function fa2_balance_of(const params : balance_of_params; const s : storage) : return is block {
      function get_balance_response (const r : balance_of_request) : balance_of_response is
        record[
          balance = if Big_map.mem(r.token_id, s.token_metadata) then get_balance(r.owner, r.token_id, s) else (failwith(fa2_token_undefined) : amt);
          request = r;
        ];
  } with (list [Tezos.transaction(List.map(get_balance_response, params.requests), 0tz, params.callback)], s)

  function update_operator (var s : storage; const p : update_operator) : storage is block {
    case p of [
    | Add_operator(param) -> {
        assert_with_error(Tezos.sender = param.owner, fa2_not_owner);
        s.operators[param] := unit
      }
    | Remove_operator(param) -> {
        assert_with_error(Tezos.sender = param.owner, fa2_not_owner);
        s.operators := Big_map.remove(param, s.operators);
      }
    ]
  } with s

  function fa2_update_operators(const commands : update_operator_params; var s : storage) : return is
    (noop, List.fold(update_operator, commands, s))
  
  function mint(const p : mint_param; var s : storage) : return is block {
    assert_with_error(Tezos.sender = s.admin or s.minters contains Tezos.sender, error_access_denied);
    if Big_map.mem(p.token_id, s.token_metadata) then failwith("Token exists already") else skip;
    s.token_metadata[p.token_id] := record [token_id=p.token_id; token_info=p.token_info];
    s.ledger[(p.target, p.token_id)] := p.amount;
  } with (noop, s)

  function update_minters (const p : update_minter_param; var s : storage) : return is block {
    assert_with_error(Tezos.sender = s.admin, error_access_denied);
    case p of [
    | Add_minter(minter) -> {
        s.minters := Set.add(minter, s.minters);
      }
    | Remove_minter(minter) -> {
        s.minters := Set.remove(minter, s.minters);
      }
    ]
  } with (noop, s)

  function main(const action : action; var s : storage) : return is
    case action of [
      | Balance_of(p) -> fa2_balance_of(p, s)
      | Mint(p) -> mint(p, s)
      | Transfer(p) -> fa2_transfer(p, s)
      | Update_minters(p) -> update_minters(p, s)
      | Update_operators(p) -> fa2_update_operators(p, s)
    ]

  [@view]
  function balance_of(const p : list(balance_of_request); const s : storage) : list(balance_of_response) is
    begin
      function get_balance_response (const r : balance_of_request) : balance_of_response is
        record[
          balance = if Big_map.mem(r.token_id, s.token_metadata) then get_balance(r.owner, r.token_id, s) else (failwith(fa2_token_undefined) : amt);
          request = r;
        ];
    end with List.map(get_balance_response, p)