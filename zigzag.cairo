# builtins.
%lang starknet
%builtins pedersen range_check ecdsa

from starkware.cairo.common.cairo_builtins import (HashBuiltin, SignatureBuiltin)
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.math import assert_nn_le, unsigned_div_rem
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.uint256 import (
    Uint256
)
from starkware.starknet.common.syscalls import get_caller_address

@constructor
func constructor{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(oracle: felt):
    time_oracle.write(oracle)
    return ()
end


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

    func transfer_from(sender: felt, recipient: felt, amount: Uint256):
    end

    func approve(spender: felt, amount: felt):
    end
end


struct PriceRatio:
    member numerator: felt
    member denominator: felt
end

struct Order:
    member chain_id : felt
    member user : felt
    member base_asset : felt
    member quote_asset : felt
    member side : felt # 0 = buy, 1 = sell
    member base_quantity : felt
    member price : PriceRatio
    member expiration : felt
    member sig_r: felt
    member sig_s: felt
end

# Storage variable for order tracking
@storage_var
func orderstatus(orderhash: felt) -> (filled: felt):
end

# Storage variable for current time
# Temporary until timestamp or blocknum are available through Starknet
@storage_var
func current_time() -> (res: felt):
end

# Time Oracle Address
# Temporary until timestamp or blocknum are available through Starknet
@storage_var
func time_oracle() -> (res: felt):
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
    let (hash) = hash2{hash_ptr=pedersen_ptr}(x=hash, y=order_ptr.price.numerator)
    let (hash) = hash2{hash_ptr=pedersen_ptr}(x=hash, y=order_ptr.price.denominator)
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

    IAccount.is_valid_signature(contract_address=order_ptr.user, hash=orderhash, signature_len=2, signature=&order_ptr.sig_r)
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
        fill_price: PriceRatio,
        base_fill_quantity: felt):
    alloc_locals
    
    # Needed for dereferencing buy_order and sell_order
    let fp_and_pc = get_fp_and_pc()
    local __fp__ = fp_and_pc.fp_val  

    # Run order checks
    assert buy_order.chain_id = 1001
    assert sell_order.chain_id = 1001
    assert buy_order.base_asset = sell_order.base_asset
    assert buy_order.quote_asset = sell_order.quote_asset
    assert buy_order.side = 0
    assert sell_order.side = 1
    let (buyorderhash) = compute_order_hash(&buy_order)
    let (sellorderhash) = compute_order_hash(&sell_order)
    let (filledbuy) = orderstatus.read(buyorderhash)
    let (filledsell) = orderstatus.read(sellorderhash)
    let (contract_time) = current_time.read()
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
    assert_nn_le(contract_time, buy_order.expiration)
    assert_nn_le(contract_time, sell_order.expiration)

    # Check sigs
    verify_order_signature{pedersen_ptr=pedersen_ptr}(&buy_order)
    verify_order_signature{pedersen_ptr=pedersen_ptr}(&sell_order)
    
    # Calculate protocol fee
    # 0 for now, can edit later
    const PROTOCOL_FEE_BIPS = 0
    let (fee, remainder) = unsigned_div_rem(base_fill_quantity * PROTOCOL_FEE_BIPS, 10000)
    let base_fill_quantity_minus_fee = base_fill_quantity - fee
    

    # Transfer tokens
    # For now, fee is paid by seller. Can change later
    let (quote_fill_quantity, remainder_fill_qty) = unsigned_div_rem(base_fill_quantity * fill_price.numerator, fill_price.denominator)
    IERC20.transfer_from(contract_address=buy_order.base_asset, sender=sell_order.user, recipient=buy_order.user, amount=Uint256(base_fill_quantity_minus_fee, 0))
    IERC20.transfer_from(contract_address=buy_order.quote_asset, sender=buy_order.user, recipient=sell_order.user, amount=Uint256(quote_fill_quantity, 0))
    orderstatus.write(buyorderhash, filledbuy + base_fill_quantity)
    orderstatus.write(sellorderhash, filledsell + base_fill_quantity)
    return ()
end

# Cancels an order by setting the fill quantity to greater than the order size
@external
func cancel_order{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        ecdsa_ptr : SignatureBuiltin*,
        range_check_ptr}(
        order: Order
    ):
    alloc_locals
    
    # Needed for dereferencing order
    let fp_and_pc = get_fp_and_pc()
    local __fp__ = fp_and_pc.fp_val  

    let (caller) = get_caller_address()
    assert caller = order.user
    let (orderhash) = compute_order_hash(&order)
    orderstatus.write(orderhash, order.base_quantity + 1)
    return ()
end

# Sets the current time
@external
func set_current_time{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        ecdsa_ptr : SignatureBuiltin*,
        range_check_ptr}(
        updated_time: felt
    ):
    let (updater) = get_caller_address()
    let (oracle) = time_oracle.read()
    assert updater = oracle
    current_time.write(updated_time)
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
