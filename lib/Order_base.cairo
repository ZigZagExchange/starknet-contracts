# builtins.
%lang starknet

from starkware.cairo.common.hash_state import (
    HashState, hash_finalize, hash_init, hash_update, hash_update_single, hash2)
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_nn_le
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.starknet.common.syscalls import get_caller_address, get_block_timestamp

from lib.config import (TRUE, CHAIN_ID, BUY_SIDE, SELL_SIDE)

##############
# Structs
##############

struct PriceRatio:
    member numerator: felt
    member denominator: felt
end

struct Order:
    member base_asset : felt
    member quote_asset : felt
    member side : felt # 0 = buy, 1 = sell
    member base_quantity : felt
    member price : PriceRatio
    member expiration : felt
end

##############
# Verification
##############

# Computes a hash from an order
func compute_order_hash{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr}(
    order_ptr: Order*) -> (
    hash: felt):
    alloc_locals

    let hash_ptr = pedersen_ptr
    with hash_ptr:
        let (hash_state_ptr: HashState*) = hash_init()
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, order_ptr.base_asset)
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, order_ptr.quote_asset)
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, order_ptr.side)
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, order_ptr.base_quantity)
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, order_ptr.price.numerator)
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, order_ptr.price.denominator)
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, order_ptr.expiration)
        let (hash) = hash_finalize(hash_state_ptr)
        let pedersen_ptr = hash_ptr
        return (hash=hash)
    end
end

# sanity checks for valid order
func check_order_valid{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr}(
        buy_order: Order*,
        sell_order: Order*,
        filledbuy: felt,
        filledsell: felt,
        base_fill_quantity: felt,
        fill_price: PriceRatio) -> (bool: felt):
    alloc_locals
    
    # Needed for dereferencing buy_order and sell_order
    let fp_and_pc = get_fp_and_pc()
    local __fp__ = fp_and_pc.fp_val  

    # Run order checks
    with_attr error_message("Invalid order"):
        assert buy_order.base_asset = sell_order.base_asset
        assert buy_order.quote_asset = sell_order.quote_asset
        assert buy_order.side = BUY_SIDE
        assert sell_order.side = SELL_SIDE
        assert_nn_le(0, filledbuy) # Sanity Check
        assert_nn_le(0, filledsell) # Sanity Check
        assert_nn_le(0, buy_order.base_quantity) 
        assert_nn_le(0, sell_order.base_quantity) 
        assert_nn_le(0, base_fill_quantity)
        assert_nn_le(filledbuy + base_fill_quantity, buy_order.base_quantity)
        assert_nn_le(filledsell + base_fill_quantity, sell_order.base_quantity)
        assert_nn_le(fill_price.numerator * buy_order.price.denominator, buy_order.price.numerator * fill_price.denominator)
        assert_nn_le(sell_order.price.numerator * fill_price.denominator, fill_price.numerator * sell_order.price.denominator)
        assert_nn_le(base_fill_quantity, buy_order.base_quantity)
        assert_nn_le(base_fill_quantity, sell_order.base_quantity)

        let (contract_time: felt) = get_block_timestamp()

        assert_nn_le(contract_time, buy_order.expiration)
        assert_nn_le(contract_time, sell_order.expiration)
    end
    return (TRUE)
end