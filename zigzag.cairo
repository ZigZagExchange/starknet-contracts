# builtins.
%lang starknet
%builtins pedersen range_check ecdsa

from starkware.cairo.common.cairo_builtins import (HashBuiltin, SignatureBuiltin)
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.starknet.common.syscalls import get_caller_address, get_block_timestamp

from Exchange_base import Exchange_execute_trade
from ZZ_Message_base import ZZ_Message, validate_message_prefix, verify_message_signature, compute_message_hash
from Order_base import PriceRatio, check_order_valid
from config import TRUE, PROTOCOL_FEE_BIPS

##############
# CONSTRUCTOR
##############

@constructor
func constructor{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }():
    return ()
end

##############
# STORAGE
##############

# Storage variable for order tracking
@storage_var
func orderstatus(messagehash: felt) -> (filled: felt):
end

##############
# FILL ORDER, CANCEL, VIEW
##############

# Matches 2 orders and fills them up to the lower of the 2 quantities
@external
func fill_order{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        ecdsa_ptr : SignatureBuiltin*,
        range_check_ptr}(
        buy_order: ZZ_Message, 
        sell_order: ZZ_Message,  
        fill_price: PriceRatio,
        base_fill_quantity: felt):
    alloc_locals
    
    # Needed for dereferencing buy_order and sell_order
    let fp_and_pc = get_fp_and_pc()
    local __fp__ = fp_and_pc.fp_val  

    #validate message prefixes
    let (local check_buy: felt) = validate_message_prefix(&buy_order)
    let (local check_sell: felt) = validate_message_prefix(&sell_order)

    assert check_buy = TRUE
    assert check_sell = TRUE

    #validate order
    let (local buymessagehash: felt) = compute_message_hash(&buy_order)
    let (local sellmessagehash: felt) = compute_message_hash(&sell_order)
    let (local filledbuy: felt) = orderstatus.read(buymessagehash)
    let (local filledsell: felt) = orderstatus.read(sellmessagehash)

    let (local check_order: felt) = check_order_valid(&buy_order.order, &sell_order.order, filledbuy, filledsell, base_fill_quantity, fill_price)

    assert check_order = TRUE

    # Check sigs
    let (local check_buy_sig: felt) = verify_message_signature(&buy_order)
    let (local check_sell_sig: felt) = verify_message_signature(&sell_order)

    assert check_buy_sig = TRUE
    assert check_sell_sig = TRUE
    
    #execute trade
    let (local fulfilled: felt) = Exchange_execute_trade(base_fill_quantity, fill_price, buy_order.order.base_asset, buy_order.order.quote_asset, buy_order.sender, sell_order.sender)

    assert fulfilled = TRUE

    orderstatus.write(buymessagehash, filledbuy + base_fill_quantity)
    orderstatus.write(sellmessagehash, filledsell + base_fill_quantity)
    return ()
end

# Cancels an order by setting the fill quantity to greater than the order size
@external
func cancel_order{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        ecdsa_ptr : SignatureBuiltin*,
        range_check_ptr}(
        order: ZZ_Message
    ):
    alloc_locals
    
    # Needed for dereferencing order
    let fp_and_pc = get_fp_and_pc()
    local __fp__ = fp_and_pc.fp_val  

    let (caller) = get_caller_address()
    assert caller = order.sender
    let (orderhash) = compute_message_hash(&order)
    orderstatus.write(orderhash, order.order.base_quantity + 1)
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
