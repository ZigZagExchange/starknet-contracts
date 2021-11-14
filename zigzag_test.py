import os
import pytest

from starkware.starknet.testing.starknet import Starknet
from starkware.crypto.signature.signature import pedersen_hash, sign, private_to_stark_key

# The path to the contract source code.
CONTRACT_FILE = os.path.join(
    os.path.dirname(__file__), "zigzag.cairo")

class Order:
    def __init__(self, user, base_asset, quote_asset, side, base_quantity, price, expiration):
        self.chain_id = 1001
        self.user = user
        self.base_asset = base_asset
        self.quote_asset = quote_asset
        self.side = side
        self.base_quantity = base_quantity
        self.price = price
        self.expiration = expiration

    def hash(self):
        order_hash = pedersen_hash(self.chain_id, self.user)
        order_hash = pedersen_hash(order_hash, self.base_asset)
        order_hash = pedersen_hash(order_hash, self.quote_asset)
        order_hash = pedersen_hash(order_hash, self.side)
        order_hash = pedersen_hash(order_hash, self.base_quantity)
        order_hash = pedersen_hash(order_hash, self.price)
        order_hash = pedersen_hash(order_hash, self.expiration)
        return order_hash

    def sign(self, privkey):
        order_hash = self.hash()
        r,s = sign(msg_hash=order_hash, priv_key=privkey)
        return r,s

# The testing library uses python's asyncio. So the following
# decorator and the ``async`` keyword are needed.
@pytest.mark.asyncio
async def test_send_order():
    # Create a new Starknet class that simulates the StarkNet
    # system.
    starknet = await Starknet.empty()

    # Deploy the contract.
    contract = await starknet.deploy(
        source=CONTRACT_FILE,
    )

    # Generate key pairs.
    priv_keys = []
    pub_keys = []

    for i in range(4):
        priv_key = 123456 * i + 654321  # See "Safety note" below.
        priv_keys.append(priv_key)

        pub_key = private_to_stark_key(priv_key)
        pub_keys.append(pub_key)


    buy_order = Order(pub_keys[0], pub_keys[2], pub_keys[3], 0, 1000, 101000, 0)
    sell_order = Order(pub_keys[1], pub_keys[2], pub_keys[3], 1, 1000, 99000, 0)
    buyhash = buy_order.hash()
    sellhash = sell_order.hash()
    r_buy,s_buy = buy_order.sign(priv_keys[1])
    r_sell,s_sell = sell_order.sign(priv_keys[1])

    # Invoke increase_balance() twice.
    await contract.increase_balance(amount=10).invoke()
    await contract.increase_balance(amount=20).invoke()

    # Check the result of get_balance().
    #execution_info = await contract.get_balance().call()
    #assert execution_info.result == (30,)
