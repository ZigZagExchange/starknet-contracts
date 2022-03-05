# builtins.
%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import unsigned_div_rem
from starkware.cairo.common.uint256 import (
    Uint256
)
from starkware.cairo.common.registers import get_fp_and_pc

from lib.config import TRUE, PROTOCOL_FEE_BIPS
from lib.Order_base import PriceRatio

##############
# Interfaces
##############

@contract_interface
namespace IERC20:
    func transfer_from(sender: felt, recipient: felt, amount: Uint256):
    end
end

##############
# Exchange Functions
##############

func Exchange_execute_trade{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr}(
        base_fill_quantity: felt,
        fill_price: PriceRatio,
        base_asset: felt,
        quote_asset: felt,
        buyer: felt,
        seller: felt) -> (bool: felt):
        alloc_locals

        # Needed for dereferencing buy_order and sell_order
        let fp_and_pc = get_fp_and_pc()
        local __fp__ = fp_and_pc.fp_val  

        # Calculate protocol fee
        let (fee, remainder) = unsigned_div_rem(base_fill_quantity * PROTOCOL_FEE_BIPS, 10000)
        let base_fill_quantity_minus_fee = base_fill_quantity - fee
        
        # Transfer tokens
        # For now, fee is paid by seller. Can change later
        let (quote_fill_quantity, remainder_fill_qty) = unsigned_div_rem(base_fill_quantity * fill_price.numerator, fill_price.denominator)
        IERC20.transfer_from(contract_address=base_asset, sender=seller, recipient=buyer, amount=Uint256(base_fill_quantity_minus_fee, 0))
        IERC20.transfer_from(contract_address=quote_asset, sender=buyer, recipient=seller, amount=Uint256(quote_fill_quantity, 0))

        return (TRUE)
    end