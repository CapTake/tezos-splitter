#include "../partial/fa2_types.ligo"
#include "../partial/fa12_types.ligo"
#include "../partial/splitter_storage.ligo"

type storage is splitter_storage

type distribute_param is record [
    amount   : nat;
    token : address * nat;
]

type action is
 | Default
 | Distribute of option(distribute_param)

type fa2 is contract(transfer_params)
type fa12 is contract(send_t)

type return is list(operation) * storage

const noop = (nil : list(operation))

function distribute_tez(const b : tez; const s : storage) : return is {
    var ops : list(operation) := list[];

    for dest -> share in map s.shares {

        ops := Tezos.transaction(Unit, b * share / s.total, Option.unopt((Tezos.get_contract_opt(dest) : option(contract(unit))))) # ops;
    };
} with (ops, s)

function distribute_tokens(const p : distribute_param; const s : storage) : return is
    case (Tezos.get_entrypoint_opt("%transfer", p.token.0) : option(fa2)) of [
        | None -> {
                assert_with_error(p.token.1 = 0n, "Incorrect token parameters");

                const fa12c = Option.unopt((Tezos.get_entrypoint_opt("%transfer", p.token.0) : option(fa12)));

                var ops : list(operation) := list[];

                for dest -> share in map s.shares {

                    ops := Tezos.transaction((Tezos.get_self_address(), (dest, p.amount * share / s.total)), 0tez, fa12c) # ops;
                };
            } with (ops, s)

        | Some(fa2c) -> {
                var txs : list(tx) := list[];

                for dest -> share in map s.shares {

                    txs := record[to_ = dest; amount = p.amount * share / s.total; token_id = p.token.1;] # txs;
                };
            } with (
                list[
                    Tezos.transaction(list[record[from_ = Tezos.get_self_address(); txs = txs;]], 0tez, fa2c);
                ],
                s
            )
    ]

function main (const p : action; var s : storage) : return is
    case p of [
        Default -> (noop, s)
        | Distribute(p) -> case p of [
            | None -> distribute_tez(Tezos.get_balance(), s)
            | Some(param) -> distribute_tokens(param, s)
        ]
    ]

[@view]
function shares (const _ : unit; const s : storage) : map(address, nat) is s.shares