# builtins.
%lang starknet
%builtins pedersen range_check ecdsa

from starkware.cairo.common.cairo_builtins import (HashBuiltin, SignatureBuiltin)
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.math import assert_nn_le
from starkware.cairo.common.registers import get_fp_and_pc


@contract_interface
namespace IAccount:
    func get_nonce() -> (res : felt):
    end

    func is_valid_signature(
            hash: felt,
            signature_len: felt,
            signature: felt*
        ):
    end

    func execute(
            to: felt,
            selector: felt,
            calldata_len: felt,
            calldata: felt*,
            nonce: felt
        ) -> (response: felt):
    end
end


@contract_interface
namespace IERC20:
    func get_total_supply() -> (res : felt):
    end

    func get_decimals() -> (res : felt):
    end

    func balance_of(user: felt) -> (res : felt):
    end

    func allowance(owner: felt, spender: felt) -> (res : felt):
    end

    func transfer(recipient: felt, amount: felt):
    end

    func transfer_from(sender: felt, recipient: felt, amount: felt):
    end

    func approve(spender: felt, amount: felt):
    end
end


struct Order:
    member chain_id : felt
    member user : felt
    member base_asset : felt
    member quote_asset : felt
    member side : felt
    member base_quantity : felt
    member price : felt
    member expiration : felt
    member sig_r: felt
    member sig_s: felt
end

# Storage variable for order tracking
@storage_var
func orderstatus(orderhash: felt) -> (filled: felt):
end

# Computes a hash from an order
func compute_order_hash{
        pedersen_ptr: HashBuiltin*,
        range_check_ptr}(
        order_ptr: Order*) -> (
        hash: felt):
    let (hash) = hash2{hash_ptr=pedersen_ptr}(x=1001, y=order_ptr.user) # 1001 = Starknet Alpha Chain ID
    let (hash) = hash2{hash_ptr=pedersen_ptr}(x=hash, y=order_ptr.base_asset)
    let (hash) = hash2{hash_ptr=pedersen_ptr}(x=hash, y=order_ptr.quote_asset)
    let (hash) = hash2{hash_ptr=pedersen_ptr}(x=hash, y=order_ptr.side)
    let (hash) = hash2{hash_ptr=pedersen_ptr}(x=hash, y=order_ptr.base_quantity)
    let (hash) = hash2{hash_ptr=pedersen_ptr}(x=hash, y=order_ptr.price)
    let (hash) = hash2{hash_ptr=pedersen_ptr}(x=hash, y=order_ptr.expiration)
    return (hash)
end

# Verifies an order signature
func verify_order_signature{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr,
        ecdsa_ptr : SignatureBuiltin*}(
        order_ptr : Order*):
    alloc_locals
    let (orderhash) = compute_order_hash(order_ptr) 
    local pedersen_ptr : HashBuiltin* = pedersen_ptr

    #IAccount.is_valid_signature(contract_address=order_ptr.user, hash=orderhash, signature_len=64, signature=&order_ptr.sig_r)
    return ()
end

# Matches 2 orders and fills them up to the lower of the 2 quantities
@external
func fill_order{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        ecdsa_ptr : SignatureBuiltin*,
        range_check_ptr}(
        buy_order: Order, 
        sell_order: Order,  
        price: felt,
        base_fill_quantity: felt):
    alloc_locals
    
    # Needed for dereferencing buy_order and sell_order
    let fp_and_pc = get_fp_and_pc()
    local __fp__ = fp_and_pc.fp_val  

    assert buy_order.chain_id = 1001
    assert sell_order.chain_id = 1001
    assert buy_order.base_asset = sell_order.base_asset
    assert buy_order.quote_asset = sell_order.quote_asset
    let (buyorderhash) = compute_order_hash(&buy_order)
    let (sellorderhash) = compute_order_hash(&sell_order)
    let (filledbuy) = orderstatus.read(buyorderhash)
    let (filledsell) = orderstatus.read(sellorderhash)
    assert filledbuy = 0
    assert filledsell = 0
    assert_nn_le(price, buy_order.price)
    assert_nn_le(sell_order.price, price)
    assert_nn_le(base_fill_quantity, buy_order.base_quantity)
    assert_nn_le(base_fill_quantity, sell_order.base_quantity)
    verify_order_signature{pedersen_ptr=pedersen_ptr}(&buy_order)
    verify_order_signature{pedersen_ptr=pedersen_ptr}(&sell_order)
    let quote_fill_quantity = base_fill_quantity * price 
    IERC20.transfer_from(contract_address=buy_order.quote_asset, sender=buy_order.user, recipient=sell_order.user, amount=quote_fill_quantity)
    IERC20.transfer_from(contract_address=buy_order.base_asset, sender=sell_order.user, recipient=buy_order.user, amount=base_fill_quantity)
    orderstatus.write(buyorderhash, buy_order.base_quantity)
    orderstatus.write(sellorderhash, sell_order.base_quantity)
    return ()
end

# Returns an order status
@view
func get_order_status{
        syscall_ptr : felt*, pedersen_ptr : HashBuiltin*,
        range_check_ptr}(orderhash: felt) -> (filled : felt):
    let (filled) = orderstatus.read(orderhash)
    return (filled)
end
