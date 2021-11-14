import os
import pytest

from starkware.starknet.testing.starknet import Starknet
from starkware.crypto.signature.signature import pedersen_hash, sign, private_to_stark_key
from lib.Signer import Signer

# The path to the contract source code.
CONTRACT_FILE = os.path.join(
    os.path.dirname(__file__), "zigzag.cairo")
ERC20_FILE = os.path.join(
    os.path.dirname(__file__), "lib/ERC20.cairo")
ACCOUNT_FILE = os.path.join(
    os.path.dirname(__file__), "lib/Account.cairo")

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

    def to_starknet_args(self, privkey):
        r,s = self.sign(privkey)
        return (self.chain_id, self.user, self.base_asset, self.quote_asset, 
                self.side, self.base_quantity, self.price, self.expiration, 
                r, s)

# The testing library uses python's asyncio. So the following
# decorator and the ``async`` keyword are needed.
@pytest.mark.asyncio
async def test_send_order():
    # Create a new Starknet class that simulates the StarkNet
    # system.
    starknet = await Starknet.empty()

    # Generate key pairs.
    signer1 = Signer(1234322181823212312)
    signer2 = Signer(1039489391002310220)

    # Deploy the contract.
    base_asset_owner = await starknet.deploy(
        source=ACCOUNT_FILE,
        constructor_calldata=[signer1.public_key]
    )
    quote_asset_owner = await starknet.deploy(
        source=ACCOUNT_FILE,
        constructor_calldata=[signer2.public_key]
    )
    base_asset = await starknet.deploy(
        source=ERC20_FILE,
        constructor_calldata=[base_asset_owner.contract_address]
    )
    quote_asset = await starknet.deploy(
        source=ERC20_FILE,
        constructor_calldata=[quote_asset_owner.contract_address]
    )
    contract = await starknet.deploy(
        source=CONTRACT_FILE,
    )
    await base_asset_owner.initialize(base_asset_owner.contract_address).invoke()
    await quote_asset_owner.initialize(quote_asset_owner.contract_address).invoke()

    base_asset_balance_owner = await base_asset.balance_of(base_asset_owner.contract_address).call()
    base_asset_balance_recipient = await base_asset.balance_of(quote_asset_owner.contract_address).call()
    quote_asset_balance_owner = await quote_asset.balance_of(quote_asset_owner.contract_address).call()
    quote_asset_balance_recipient = await quote_asset.balance_of(base_asset_owner.contract_address).call()
    assert base_asset_balance_owner.result == (1000,)
    assert base_asset_balance_recipient.result == (0,)
    assert quote_asset_balance_owner.result == (1000,)
    assert quote_asset_balance_recipient.result == (0,)


    # Set Allowances
    await signer1.send_transaction(base_asset_owner, base_asset, 'approve', [contract, 1000])
    await signer2.send_transaction(quote_asset_owner, quote_asset, 'approve', [contract, 1000])
    base_asset_approval_owner = await base_asset.allowances(base_asset_owner.contract_address, contract).call()
    quote_asset_approval_owner = await quote_asset.allowances(quote_asset_owner.contract_address, contract).call()
    print(base_asset_approval_owner)
    print(quote_asset_approval_owner)
    return


    buy_order = Order(pub_keys[0], base_asset.contract_address, quote_asset.contract_address, 0, 1000, 101000, 0)
    sell_order = Order(pub_keys[1], base_asset.contract_address, quote_asset.contract_address, 1, 1000, 99000, 0)

    # Invoke fill_order()
    await contract.fill_order(
        buy_order=buy_order.to_starknet_args(priv_keys[0]), 
        sell_order=sell_order.to_starknet_args(priv_keys[1]),
        price=100000,
        base_fill_quantity=900
    ).invoke()

    # Check the result of get_balance().
    base_asset_balance_owner = await base_asset.balance_of(base_asset_owner.contract_address).call()
    base_asset_balance_recipient = await base_asset.balance_of(quote_asset_owner.contract_address).call()
    quote_asset_balance_owner = await quote_asset.balance_of(quote_asset_owner.contract_address).call()
    quote_asset_balance_recipient = await quote_asset.balance_of(base_asset_owner.contract_address).call()
    print(base_asset_balance_owner.result)
    print(base_asset_balance_recipient.result)
    print(quote_asset_balance_owner.result)
    print(quote_asset_balance_recipient.result)
    #assert execution_info.result == (30,)

