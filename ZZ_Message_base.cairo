# builtins.
%lang starknet

from starkware.cairo.common.hash_state import (
    HashState, hash_finalize, hash_init, hash_update, hash_update_single, hash2)
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.registers import get_fp_and_pc

from Order_base import PriceRatio, Order, compute_order_hash
from lib.StructHash import StarkNet_Domain, hashDomain
from config import DOMAIN_NAME, APP_VERSION, CHAIN_ID, STARKNET_MESSAGE_PREFIX, TRUE, STARKNET_DOMAIN_TYPE_HASH, ORDER_TYPE_HASH

##############
# STRUCTS
##############

struct ZZ_Message:
    member message_prefix: felt
    member domain_prefix: StarkNet_Domain
    member sender: felt
    member order: Order
    member sig_r: felt
    member sig_s: felt
end

##############
# Interfaces
##############

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
end

##############
# Verification
##############

# validate_message
func validate_message_prefix{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr}(
        msg_ptr: ZZ_Message*) -> (bool: felt):
    alloc_locals
    
    # Needed for dereferencing buy_order and sell_order
    let fp_and_pc = get_fp_and_pc()
    local __fp__ = fp_and_pc.fp_val

    # Run message checks
    with_attr error_message("Invalid Message"):
        assert msg_ptr.message_prefix = STARKNET_MESSAGE_PREFIX
        assert msg_ptr.domain_prefix.name = DOMAIN_NAME
        assert msg_ptr.domain_prefix.version = APP_VERSION
        assert msg_ptr.domain_prefix.chain_id = CHAIN_ID
    end
    return (TRUE)
end

# Verifies an order signature
func verify_message_signature{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr}(
        msg_ptr : ZZ_Message*) -> (bool: felt):
    alloc_locals
    let (local msghash: felt) = compute_message_hash(msg_ptr) 

    IAccount.is_valid_signature(contract_address=msg_ptr.sender, hash=msghash, signature_len=2, signature=&msg_ptr.sig_r)
    return (TRUE)
end


# Computes a hash from a message
func compute_message_hash{
        pedersen_ptr: HashBuiltin*,
        range_check_ptr}(
        msg_ptr: ZZ_Message*) -> (
        hash: felt):

        let hash_ptr = pedersen_ptr
        with hash_ptr:
            #let (hash_state_ptr: HashState*) = hash_init()
            
            #hash prefix
            let (hash) = hash2(msg_ptr.message_prefix, STARKNET_DOMAIN_TYPE_HASH)

            #hash domain
            let (hash) = hash2(hash, msg_ptr.domain_prefix.name)
            let (hash) = hash2(hash, msg_ptr.domain_prefix.version)
            let (hash) = hash2(hash, msg_ptr.domain_prefix.chain_id)

            #hash sender
            let (hash) = hash2(hash, msg_ptr.sender)

            #hash order
            let (hash) = hash2(hash, ORDER_TYPE_HASH)
            let (hash) = hash2(hash, msg_ptr.order.base_asset)
            let (hash) = hash2(hash, msg_ptr.order.quote_asset)
            let (hash) = hash2(hash, msg_ptr.order.side)
            let (hash) = hash2(hash, msg_ptr.order.base_quantity)
            let (hash) = hash2(hash, msg_ptr.order.price.numerator)
            let (hash) = hash2(hash, msg_ptr.order.price.denominator)
            let (hash) = hash2(hash, msg_ptr.order.expiration)

            #finalize
            #let (hash) = hash_finalize(hash_state_ptr)
            let pedersen_ptr = hash_ptr
            return (hash=hash)
        end
end