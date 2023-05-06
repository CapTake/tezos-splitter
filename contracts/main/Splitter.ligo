#include "../partial/fa2_types.ligo"
#include "../partial/fa12_types.ligo"

type storage is record [
    total  : nat;
    shares : map(address, nat);
]

type distribute_param is record [
    amount   : nat;
    token : address * nat;
]

type action is
 | Default
 | Distibute of option(distribute_param)

type fa2 is contract(transfer_params)
type fa12 is contract(send_t)

type return is list(operation) * storage

const noop = (nil : list(operation))

function distribute_tez(const b : tez; const s : storage) : return is {

    function folder (const ops: list(operation); const dest : address; const share : nat) : list(operation) is {

        const destc = Option.unopt((Tezos.get_contract_opt(dest) : option(contract(unit))));

    } with Tezos.transaction(Unit, b * share / s.total, destc) # ops;

} with (Map.fold(folder, s.shares, list[]), s)

function distribute_tokens(const p : distribute_param; const s : storage) : return is {
    function fa2folder (const txs: list(tx); const dest : address; const share : nat) : list(operation) is
        record [
            to_ = dest;
            amount = p.amount * share / s.total;
            token_id = p.token.1
        ] # txs;

} with case (Tezos.get_entrypoint_opt("%transfer", p.token.0) : option(fa2)) of [
        | None -> if p.token.1 > 0 then (failwith("Incorrect token parameters") : return)
            else {
                const fa12c = Option.unopt(Tezos.get_entrypoint_opt("%transfer", p.token.0) : option(fa12));

                function fa12folder (const ops: list(operation); const dest : address; const share : nat) : list(operation) is
                    Tezos.transaction((Tezos.get_self_address(), (dest, p.amount * share / s.total)), 0tez, fa12c) # ops;
            } with (Map.fold(fa12folder, s.shares, list[]), s)

        | Some(fa2c) -> (
            list [
                Tezos.transaction(
                    list [
                        record [
                            from_ = Tezos.get_self_address(),
                            txs = Map.fold(fa2folder, s.shares, list[])
                        ];
                    ],
                    0tez,
                    fa2c
                );
            ], s)
    ]

function distribute (const p : option(distribute_param); var s : storage) : return is
    case p of [
        | None -> distribute_tez(Tezos.get_balance(), s)
        | Some(param) -> distribute_tokens(param, s)
    ]

function main (const p : action; var s : storage) : return is
    case p of [
        | Default -> (noop, s)
        | Distibute(p) -> distribute(p, s)
    ]