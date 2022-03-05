# from OZ cairo contracts
"""Utilities for testing Cairo contracts."""

from starkware.cairo.common.hash_state import compute_hash_on_elements
from starkware.crypto.signature.signature import private_to_stark_key, sign
from starkware.starknet.public.abi import get_selector_from_name
from starkware.starknet.compiler.compile import compile_starknet_files
from starkware.starkware_utils.error_handling import StarkException
from starkware.starknet.testing.starknet import StarknetContract
from starkware.starknet.business_logic.transaction_execution_objects import Event


MAX_UINT256 = (2 ** 128 - 1, 2 ** 128 - 1)
ZERO_ADDRESS = 0
TRUE = 1
FALSE = 0

TRANSACTION_VERSION = 0


def str_to_felt(text):
    b_text = bytes(text, "ascii")
    return int.from_bytes(b_text, "big")


def felt_to_str(felt):
    b_felt = felt.to_bytes(31, "big")
    return b_felt.decode()


class Signer:
    def __init__(self, private_key):
        self.private_key = private_key
        self.public_key = private_to_stark_key(private_key)

    def sign(self, message_hash):
        return sign(msg_hash=message_hash, priv_key=self.private_key)

    async def send_transaction(self, account, to, selector_name, calldata, nonce=None):
        if nonce is None:
            execution_info = await account.get_nonce().call()
            (nonce,) = execution_info.result

        selector = get_selector_from_name(selector_name)
        message_hash = hash_message(
            account.contract_address, to, selector, calldata, nonce
        )
        sig_r, sig_s = self.sign(message_hash)

        return await account.execute(to, selector, calldata, nonce).invoke(
            signature=[sig_r, sig_s]
        )


def hash_message(sender, to, selector, calldata, nonce):
    message = [sender, to, selector, compute_hash_on_elements(calldata), nonce]
    return compute_hash_on_elements(message)
