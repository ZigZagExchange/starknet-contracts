import os
import pytest
import time

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

def uint(a):
    return(int(a), 0)

def unixms():
    return int(time.time()*100)

class PriceRatio:
    def __init__(self, numerator, denominator):
        self.numerator = numerator
        self.denominator = denominator
    
    def to_starknet_args(self):
        return (self.numerator, self.denominator)

class Order:
    def __init__(self, user, base_asset, quote_asset, side, base_quantity, price, expiration):
        self.chain_id = 1001
        self.user = user
        self.base_asset = base_asset
        self.quote_asset = quote_asset
        self.side = side
        self.base_quantity = base_quantity
        self.price = PriceRatio(*price)
        self.expiration = expiration

    def hash(self):
        order_hash = pedersen_hash(self.chain_id, self.user)
        order_hash = pedersen_hash(order_hash, self.base_asset)
        order_hash = pedersen_hash(order_hash, self.quote_asset)
        order_hash = pedersen_hash(order_hash, self.side)
        order_hash = pedersen_hash(order_hash, self.base_quantity)
        order_hash = pedersen_hash(order_hash, self.price.numerator)
        order_hash = pedersen_hash(order_hash, self.price.denominator)
        order_hash = pedersen_hash(order_hash, self.expiration)
        return order_hash

    def sign(self, signer):
        order_hash = self.hash()
        r,s = signer.sign(order_hash)
        return r,s

    def to_starknet_args(self, signer):
        r,s = self.sign(signer)
        return (self.chain_id, self.user, self.base_asset, self.quote_asset, 
                self.side, self.base_quantity, self.price.to_starknet_args(),
                self.expiration, r, s)

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
    signer3 = Signer(8439329023933332923)

    # Deploy the contract.
    base_asset_owner = await starknet.deploy(
        source=ACCOUNT_FILE,
        constructor_calldata=[signer1.public_key]
    )
    quote_asset_owner = await starknet.deploy(
        source=ACCOUNT_FILE,
        constructor_calldata=[signer2.public_key]
    )
    oracle = await starknet.deploy(
        source=ACCOUNT_FILE,
        constructor_calldata=[signer3.public_key]
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
        constructor_calldata=[oracle.contract_address]
    )
    await base_asset_owner.initialize(base_asset_owner.contract_address).invoke()
    await quote_asset_owner.initialize(quote_asset_owner.contract_address).invoke()
    await oracle.initialize(oracle.contract_address).invoke()

    # Set contract time
    # Temporary: will not be required after Starknet supports time
    now = unixms()
    await signer3.send_transaction(oracle, contract.contract_address, 'set_current_time', [now])

    # Fail to set time with non-oracle account
    with pytest.raises(Exception) as e_info:
        await signer2.send_transaction(oracle, contract.contract_address, 'set_current_time', [now])

    

    base_asset_balance_owner = await base_asset.balance_of(base_asset_owner.contract_address).call()
    base_asset_balance_recipient = await base_asset.balance_of(quote_asset_owner.contract_address).call()
    quote_asset_balance_owner = await quote_asset.balance_of(quote_asset_owner.contract_address).call()
    quote_asset_balance_recipient = await quote_asset.balance_of(base_asset_owner.contract_address).call()
    assert base_asset_balance_owner.result.res == uint(100e18)
    assert base_asset_balance_recipient.result.res == uint(0)
    assert quote_asset_balance_owner.result.res == uint(100e18)
    assert quote_asset_balance_recipient.result.res == uint(0)


    # Set Allowances
    approve_amount = uint(1e25)
    await signer1.send_transaction(base_asset_owner, base_asset.contract_address, 'approve', [contract.contract_address, *approve_amount])
    await signer2.send_transaction(quote_asset_owner, quote_asset.contract_address, 'approve', [contract.contract_address, *approve_amount])
    base_asset_approval_owner = await base_asset.allowance(base_asset_owner.contract_address, contract.contract_address).call()
    quote_asset_approval_owner = await quote_asset.allowance(quote_asset_owner.contract_address, contract.contract_address).call()
    assert base_asset_approval_owner.result.res == approve_amount
    assert quote_asset_approval_owner.result.res == approve_amount

    # Full fill

    base_quantity = 1
    buy_price = (1,1)
    exec_price = (1,1)
    sell_price = (1,1)
    expiration = unixms() + 1
    sell_order = Order(base_asset_owner.contract_address, base_asset.contract_address, quote_asset.contract_address, 1, base_quantity, sell_price, expiration)
    buy_order = Order(quote_asset_owner.contract_address, base_asset.contract_address, quote_asset.contract_address, 0, base_quantity, buy_price, expiration)

    await contract.fill_order(
        sell_order=sell_order.to_starknet_args(signer1),
        buy_order=buy_order.to_starknet_args(signer2), 
        fill_price=exec_price,
        base_fill_quantity=base_quantity
    ).invoke()


    # Check Balances
    base_asset_balance_owner = await base_asset.balance_of(base_asset_owner.contract_address).call()
    base_asset_balance_recipient = await base_asset.balance_of(quote_asset_owner.contract_address).call()
    quote_asset_balance_owner = await quote_asset.balance_of(quote_asset_owner.contract_address).call()
    quote_asset_balance_recipient = await quote_asset.balance_of(base_asset_owner.contract_address).call()
    buy_order_filled = await contract.get_order_status(buy_order.hash()).call()
    sell_order_filled = await contract.get_order_status(sell_order.hash()).call()
    assert base_asset_balance_owner.result.res == uint(int(100e18) - 1)
    assert base_asset_balance_recipient.result.res == uint(1)
    assert quote_asset_balance_owner.result.res == uint(int(100e18) - 1)
    assert quote_asset_balance_recipient.result.res == uint(1)
    assert buy_order_filled.result.filled == 1
    assert sell_order_filled.result.filled == 1

    # Re-fill same orders should throw an error
    with pytest.raises(Exception) as e_info:
        await contract.fill_order(
            sell_order=sell_order.to_starknet_args(signer1),
            buy_order=buy_order.to_starknet_args(signer2), 
            fill_price=exec_price,
            base_fill_quantity=base_quantity
        ).invoke()

    # Partial fill

    buy_quantity = 25
    sell_quantity = 50
    fill_quantity = 25
    buy_price = (3,1)
    exec_price = (2,1)
    sell_price = (1,1)
    expiration = unixms() + 1000
    sell_order = Order(base_asset_owner.contract_address, base_asset.contract_address, quote_asset.contract_address, 1, sell_quantity, sell_price, expiration)
    buy_order = Order(quote_asset_owner.contract_address, base_asset.contract_address, quote_asset.contract_address, 0, buy_quantity, buy_price, expiration)

    await contract.fill_order(
        sell_order=sell_order.to_starknet_args(signer1),
        buy_order=buy_order.to_starknet_args(signer2), 
        fill_price=exec_price,
        base_fill_quantity=fill_quantity
    ).invoke()

    # Check Balances
    base_asset_balance_owner = await base_asset.balance_of(base_asset_owner.contract_address).call()
    base_asset_balance_recipient = await base_asset.balance_of(quote_asset_owner.contract_address).call()
    quote_asset_balance_owner = await quote_asset.balance_of(quote_asset_owner.contract_address).call()
    quote_asset_balance_recipient = await quote_asset.balance_of(base_asset_owner.contract_address).call()
    buy_order_filled = await contract.get_order_status(buy_order.hash()).call()
    sell_order_filled = await contract.get_order_status(sell_order.hash()).call()
    assert base_asset_balance_owner.result.res == uint(int(100e18) - 26)
    assert base_asset_balance_recipient.result.res == uint(26)
    assert quote_asset_balance_owner.result.res == uint(int(100e18) - 51)
    assert quote_asset_balance_recipient.result.res == uint(51)
    assert buy_order_filled.result.filled == 25
    assert sell_order_filled.result.filled == 25


    # Fill too much and throw an error
    with pytest.raises(Exception) as e_info:
        buy_quantity = 50
        fill_quantity = 50
        buy_order = Order(quote_asset_owner.contract_address, base_asset.contract_address, quote_asset.contract_address, 0, buy_quantity, buy_price, expiration)
        await contract.fill_order(
            sell_order=sell_order.to_starknet_args(signer1),
            buy_order=buy_order.to_starknet_args(signer2), 
            fill_price=exec_price,
            base_fill_quantity=fill_quantity
        ).invoke()

    # Fill remainder of sell order at different price with leftover in buy order
    buy_quantity = 50
    fill_quantity = 25
    exec_price = (1,1)
    buy_order = Order(quote_asset_owner.contract_address, base_asset.contract_address, quote_asset.contract_address, 0, buy_quantity, buy_price, expiration)
    await contract.fill_order(
        sell_order=sell_order.to_starknet_args(signer1),
        buy_order=buy_order.to_starknet_args(signer2), 
        fill_price=exec_price,
        base_fill_quantity=fill_quantity
    ).invoke()
    base_asset_balance_owner = await base_asset.balance_of(base_asset_owner.contract_address).call()
    base_asset_balance_recipient = await base_asset.balance_of(quote_asset_owner.contract_address).call()
    quote_asset_balance_owner = await quote_asset.balance_of(quote_asset_owner.contract_address).call()
    quote_asset_balance_recipient = await quote_asset.balance_of(base_asset_owner.contract_address).call()
    buy_order_filled = await contract.get_order_status(buy_order.hash()).call()
    sell_order_filled = await contract.get_order_status(sell_order.hash()).call()
    assert base_asset_balance_owner.result.res == uint(int(100e18) - 51)
    assert base_asset_balance_recipient.result.res == uint(51)
    assert quote_asset_balance_owner.result.res == uint(int(100e18) - 76)
    assert quote_asset_balance_recipient.result.res == uint(76)
    assert buy_order_filled.result.filled == 25
    assert sell_order_filled.result.filled == 50

    # Price mismatch should throw an error
    with pytest.raises(Exception) as e_info:
        buy_price = (3,1)
        sell_price = (4,1)
        expiration = unixms() + 1010
        buy_order = Order(quote_asset_owner.contract_address, base_asset.contract_address, quote_asset.contract_address, 0, buy_quantity, buy_price, expiration)
        sell_order = Order(base_asset_owner.contract_address, base_asset.contract_address, quote_asset.contract_address, 1, sell_quantity, sell_price, expiration)
        await contract.fill_order(
            sell_order=sell_order.to_starknet_args(signer1),
            buy_order=buy_order.to_starknet_args(signer2), 
            fill_price=exec_price,
            base_fill_quantity=fill_quantity
        ).invoke()

    # Can't fill an expired order
    contract_time = unixms()
    await signer3.send_transaction(oracle, contract.contract_address, 'set_current_time', [contract_time])
    with pytest.raises(Exception) as e_info:
        buy_price = (4,1)
        sell_price = (3,1)
        exec_price = (4,1)
        buy_quantity = 25
        sell_quantity = 25
        fill_quantity = 25
        expiration_bad = unixms() - 100000
        expiration_good = unixms() + 100000
        buy_order = Order(quote_asset_owner.contract_address, base_asset.contract_address, quote_asset.contract_address, 0, buy_quantity, buy_price, expiration_bad)
        sell_order = Order(base_asset_owner.contract_address, base_asset.contract_address, quote_asset.contract_address, 1, sell_quantity, sell_price, expiration_good)
        await contract.fill_order(
            sell_order=sell_order.to_starknet_args(signer1),
            buy_order=buy_order.to_starknet_args(signer2), 
            fill_price=exec_price,
            base_fill_quantity=fill_quantity
        ).invoke()

    # Fill Big orders
    buy_price = (405736, 100)
    sell_price = (405736, 100)
    buy_quantity = 2000000000000000000
    sell_quantity = 2000000000000000000
    fill_quantity = 2000000000000000000
    exec_price = (405736, 100)
    expiration_good = unixms() + 100000
    buy_order = Order(quote_asset_owner.contract_address, base_asset.contract_address, quote_asset.contract_address, 0, buy_quantity, buy_price, expiration_good)
    sell_order = Order(base_asset_owner.contract_address, base_asset.contract_address, quote_asset.contract_address, 1, sell_quantity, sell_price, expiration_good)
    await contract.fill_order(
        sell_order=sell_order.to_starknet_args(signer1),
        buy_order=buy_order.to_starknet_args(signer2), 
        fill_price=exec_price,
        base_fill_quantity=fill_quantity
    ).invoke()
    base_asset_balance_owner = await base_asset.balance_of(base_asset_owner.contract_address).call()
    base_asset_balance_recipient = await base_asset.balance_of(quote_asset_owner.contract_address).call()
    quote_asset_balance_owner = await quote_asset.balance_of(quote_asset_owner.contract_address).call()
    quote_asset_balance_recipient = await quote_asset.balance_of(base_asset_owner.contract_address).call()
    buy_order_filled = await contract.get_order_status(buy_order.hash()).call()
    sell_order_filled = await contract.get_order_status(sell_order.hash()).call()
    #assert base_asset_balance_owner.result.res == uint(949)
    #assert base_asset_balance_recipient.result.res == uint(51)
    #assert quote_asset_balance_owner.result.res == uint(924)
    #assert quote_asset_balance_recipient.result.res == uint(76)
    #assert buy_order_filled.result.filled == 25
    #assert sell_order_filled.result.filled == 50
