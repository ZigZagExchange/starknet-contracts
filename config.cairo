# Template From OpenZeppelin Cairo Contracts v0.1.0 (utils/constants.cairo)

%lang starknet

#
# Booleans
#

const TRUE = 1
const FALSE = 0

#
# Message Config
#

const STARKNET_MESSAGE_PREFIX = 'StarkNet Message'

const DOMAIN_NAME = 'zigzag.exchange'
const APP_VERSION = 1
const CHAIN_ID = 'SN_GOERLI'

const STARKNET_DOMAIN_TYPE_HASH = 0x1bfc207425a47a5dfa1a50a4f5241203f50624ca5fdf5e18755765416b8e288
const ORDER_TYPE_HASH = 0x1c40c16f3451462e7f4a563be58271e0a15bfc1cb3fe2e4849e78ccc3bd557

#
# Order Config
#

const BUY_SIDE = 0
const SELL_SIDE = 1

#
# Exchange Config
#

const PROTOCOL_FEE_BIPS = 0