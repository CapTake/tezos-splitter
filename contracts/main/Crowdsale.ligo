type amt is nat // token amount
type token_id is nat
type token_info is map(string, bytes)

type oracle_view_param is timestamp * nat
type reserve_giveaways_param is address * amt
type reveal_metadata_item is michelson_pair(nat, "token_id", map(string, bytes), "token_info")
type reveal_metadata_param is list(reveal_metadata_item)

#include "../partial/mint_param.ligo"
#include "../partial/nat_2_bytes.ligo"

type mintery_contract is contract(mint_param)
type updateable_mintery_contract is contract(reveal_metadata_param)
type whitelist_pair is address * nat

type configure_params is [@layout:comb] record [
  phase: nat;
  price: tez;
  limit: nat;
]

type allowance is record [
  amount : amt;
  limit  : amt;
]

type phase is record [
  price : tez;
  limit : nat;
  admin : bool;
]

type storage is record [
  admin                  : address;
  pending_admin          : option(address);
  fa2                    : address;
  sale_price             : tez;
  presale_price          : tez;
  presale_limit          : nat;
  presale_duration       : int;
  per_wallet_limit       : nat;
  metadata               : big_map(string, bytes);
  whitelist              : big_map(address, nat);
  minted                 : set(nat);
  max_supply             : nat;
  start_date             : timestamp;
  paused                 : bool;
  provenance             : bytes;
  ipfs_template_uri      : bytes;
  shares                 : map(address, nat);
]

type action is
  | Confirm_admin
  | Mint of nat
  | Pause of bool
  | Register_fa2 of address
  | Reveal_metadata of reveal_metadata_param
  | Set_admin of option(address)
  | Set_start_date of timestamp
  | Whitelist of list(address)


type return is list (operation) * storage

const noop : list (operation) = (nil: list (operation))

const error_ACCESS_DENIED = "Access denied"
const error_NOT_STARTED = "Not started yet"
const error_NOT_WHITELISTED = "Not whitelisted"
const error_AMOUNT_TOO_BIG = "Mint amount too big"
const error_WALLET_ALLOWANCE_EXCEEDED = "Per Wallet limit reached"
const error_PRESALE_LIMIT = "Presale limit reached"
const error_PAUSED = "Sale paused"
const error_INCORRECT_FUNDS_AMOUNT = "Wrong funds amount"

[@inline]
function get_mint_entrypoint(const s : storage) : mintery_contract is
  case (Tezos.get_entrypoint_opt("%mint", s.fa2) : option(mintery_contract)) of [
    | None -> (failwith(1) : mintery_contract)
    | Some(p) -> p
  ]

function get_destination(const a : address) : contract(unit) is
  case (Tezos.get_contract_opt(a) : option(contract(unit))) of [
    | None -> (failwith(0) : contract(unit))
    | Some(p) -> p
  ];

function next_index(const minted : set(nat); const total_supply : nat) : token_id is {
    var ids : map(nat, int) := map[];
    var _n : nat := 0n;
    for i := 1 to int(total_supply) {
      if minted contains abs(i) then skip
      else {
        ids[_n] := i;
        _n := _n + 1n;
      }
    };
    const rnd : nat = (111147797 + Tezos.level) mod Map.size(ids);
} with abs(case ids[rnd] of [
    | Some(a) -> a
    | None -> (failwith("Wrong index") : int)
  ])

[@inline]
function pay_shares(const shares : map(address, nat); const amt : tez; var ops : list (operation)) : list(operation) is {
   for addr -> value in map shares {
      const share : tez = (amt / 1000n) * value;
      if share > 0tez then ops := Tezos.transaction(unit, share, get_destination(addr)) # ops else skip;
   }
} with ops

function mint_transaction(const token_id : token_id; const target : address; const s : storage) : operation is {
    const mintery : mintery_contract = get_mint_entrypoint(s);
    const token_info : token_info = map ["" -> Bytes.concat(s.ipfs_template_uri, nat_to_bytes(token_id))];
} with Tezos.transaction(record [ target=target; amount=1n; token_id=token_id; token_info=token_info ], 0tz, mintery)

function mint(const requested : nat; var s : storage) : return is {
    assert_with_error(not s.paused, error_PAUSED);
    assert_with_error(Tezos.now >= s.start_date, error_NOT_STARTED);
    assert_with_error(s.max_supply > Set.cardinal(s.minted), "Sale ended");
    assert_with_error(s.max_supply >= requested + Set.cardinal(s.minted), error_AMOUNT_TOO_BIG);
    const skip_whitelist : bool = (s.admin = Tezos.sender or Tezos.now >= s.start_date + s.presale_duration);
    const user_minted : nat = case (s.whitelist[Tezos.sender] : option(nat)) of [
      | Some(p) -> if p >= s.per_wallet_limit then (failwith(error_WALLET_ALLOWANCE_EXCEEDED) : nat) else p + requested
      | None -> if skip_whitelist then requested else (failwith(error_NOT_WHITELISTED) : nat)
    ];
    assert_with_error(Tezos.sender = s.admin or (user_minted <= s.per_wallet_limit), error_AMOUNT_TOO_BIG);
    s.whitelist[Tezos.sender] := user_minted;
    const price : tez = if skip_whitelist then s.sale_price else s.presale_price;
    assert_with_error((Tezos.sender = s.admin and Tezos.amount = 0tez) or Tezos.amount = price * requested, error_INCORRECT_FUNDS_AMOUNT);
    assert_with_error(skip_whitelist or (requested + Set.cardinal(s.minted) <= s.presale_limit), error_PRESALE_LIMIT);

    var ops : list(operation) := noop;
    for i := 1 to int(requested) {
      const token_id : token_id = next_index(s.minted, s.max_supply);
      ops := mint_transaction(token_id, Tezos.sender, s) # ops;
      s.minted := Set.add(token_id, s.minted);
    };

} with (pay_shares(s.shares, Tezos.amount, ops), s)

function register_fa2(const fa2 : address; var s : storage) : return is {
    assert_with_error(s.admin = Tezos.sender, error_ACCESS_DENIED);
    s.fa2 := fa2;
} with (noop, s)

function reveal_metadata(const param : reveal_metadata_param; var s : storage) : return is {
    assert_with_error(s.admin = Tezos.sender, error_ACCESS_DENIED);
    assert_with_error(Tezos.amount = 0tez, error_INCORRECT_FUNDS_AMOUNT);
    const mintery : updateable_mintery_contract = case (Tezos.get_entrypoint_opt("%update_token_metadata", s.fa2) : option(updateable_mintery_contract)) of [
      | None -> (failwith(1) : updateable_mintery_contract)
      | Some(p) -> p
    ];
} with (list[Tezos.transaction(param, 0tez, mintery)], s)

function set_sale_start(const date : timestamp; var s : storage) : return is {
    assert_with_error(s.admin = Tezos.sender, error_ACCESS_DENIED);
    s.start_date := date;
} with (noop, s)

function set_pause(const pause : bool; var s : storage) : return is {
    assert_with_error(s.admin = Tezos.sender, error_ACCESS_DENIED);
    s.paused := pause;
} with (noop, s)

function whitelist_addresses(const p : list(address); var s : storage) : return is {
    assert_with_error(s.admin = Tezos.sender, error_ACCESS_DENIED);
    for a in list p { s.whitelist[a] := 0n; }
} with (noop, s)

function set_admin(const p : option(address); var s : storage): return is {
    assert_with_error(s.admin = Tezos.sender, error_ACCESS_DENIED);
    s.pending_admin := p;
} with (noop, s)

function confirm_admin(var s : storage): return is {
    assert_with_error(s.pending_admin = Some(Tezos.sender), error_ACCESS_DENIED);
    s.admin := Tezos.sender;
    s.pending_admin := (None : option(address));
} with (noop, s)

function main(const action : action; var s : storage) : return is
  case action of [
    | Confirm_admin -> confirm_admin(s)
    | Mint(p) -> mint(p, s)
    | Pause(p) -> set_pause(p, s)
    | Register_fa2(p) -> register_fa2(p, s)
    | Reveal_metadata(p) -> reveal_metadata(p, s)
    | Set_admin(p) -> set_admin(p, s)
    | Set_start_date(p) -> set_sale_start(p, s)
    | Whitelist(p) -> whitelist_addresses(p, s)
  ]