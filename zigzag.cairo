# builtins.
%lang starknet
%builtins pedersen range_check ecdsa

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.storage import Storage
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.math import assert_nn_le


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
    member user : felt
    member base_asset : felt
    member quote_asset : felt
    member side : felt
    member base_quantity : felt
    member price : felt
    member expiration : felt
    member tonce : felt
    member r: felt
    member s: felt
end

# Storage variable for order tracking
@storage_var
func orderstatus(orderhash: felt) -> (filled: felt):
end

# Computes a hash from an order
func compute_order_hash{
        pederson_ptr: HashBuiltin*,
        range_check_ptr}(
        order_ptr: Order*) -> (
        hash: felt):
    return hash2{hash_ptr=pedersen_ptr}(
        x=order, y=vote_info_ptr.vote)
end

# Verifies an order signature
func verify_order_signature{
        pedersen_ptr : HashBuiltin*,
        range_check_ptr,
        ecdsa_ptr : SignatureBuiltin*}(
        order_ptr : Order*):
    let (message) = compute_order_hash(order_ptr) 

    verify_ecdsa_signature(
        message=message,
        public_key=order_ptr.user,
        signature_r=order_ptr.r,
        signature_s=order_ptr.s)
    return ()
end

# Matches 2 orders and fills them up to the lower of the 2 quantities
@external
func fill_order{
        storage_ptr : Storage*, 
        pedersen_ptr : HashBuiltin*,
        ecdsa_ptr : SignatureBuiltin*,
        range_check_ptr}(
        buy_order: Order, 
        sell_order: Order,  
        price: felt,
        base_fill_quantity: felt):
    assert buy_order.base_asset == sell_order.base_asset
    assert buy_order.quote_asset == sell_order.quote_asset
    let (buyorderhash) = compute_order_hash(buy_order)
    let (sellorderhash) = compute_order_hash(sell_order)
    let (filledbuy) = orderstatus.read(buyorderhash)
    let (filledsell) = orderstatus.read(sellorderhash)
    assert filledbuy = 0
    assert filledsell = 0
    assert_nn_le(price, buy_order.price)
    assert_nn_le(sell_order.price, price)
    assert_nn_le(base_fill_quantity, buy_order.base_quantity)
    assert_nn_le(base_fill_quantity, sell_order.base_quantity)
    let (quote_fill_quantity) = base_fill_quantity * price 
    IERC20.transferFrom(contract_address=buy_order.quote_asset, sender=buy_order.user, recipient=sell_order.user, amount=quote_fill_quantity)
    IERC20.transferFrom(contract_address=buy_order.base_asset, sender=sell_order.user, recipient=buy_order.user, amount=base_fill_quantity)
    orderstatus.write(buyorderhash, buy_order.base_quantity)
    orderstatus.write(sellorderhash, sell_order.base_quantity)
    return ()
end

# Returns an order status
@view
func get_order_status{
        storage_ptr : Storage*, pedersen_ptr : HashBuiltin*,
        range_check_ptr}(orderhash: felt) -> (filled : felt):
    let (filled) = orderstatus.read(orderhash)
    return (filled)
end
