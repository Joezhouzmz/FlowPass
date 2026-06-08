#!/usr/bin/env bash
set -euo pipefail

RPC_URL="${RPC_URL:-https://sepolia.unichain.org}"
EXPLORER_URL="${EXPLORER_URL:-https://unichain-sepolia.blockscout.com}"

HOOK="0xEfEf9F8aC2B1fEC9b173Ae3530Cdeb1407BC80C0"
ROUTER="0xD22505dD65B985FBf47c2030a6421536fe0C3159"
TOKEN_A="0xd119Da24acdc69190C0a12c1CCD64115c38DE6ac"
TOKEN_B="0xf06219433b255A42667EFD5F0177194Fa6Dbe0f9"
DEPLOYMENT_WALLET="0x775717A1460Cce9Ee3c729a0625f09966F72B628"
POOL_ID="0x6770d05ee2d5efb0a94ea7f27c5212b580b17c1d045c52b3505797721d9c9acb"
SWAP_TX="0xdf2970c1b82d94ebb29b0fb9793d4d6bfae0fba8f8f497a0ec251256a9b6f09d"

require_cast() {
  if ! command -v cast >/dev/null 2>&1; then
    echo "cast is required. Install Foundry first: https://book.getfoundry.sh/getting-started/installation" >&2
    exit 1
  fi
}

code_bytes() {
  local address="$1"
  local code
  code="$(cast code "$address" --rpc-url "$RPC_URL")"
  if [ "$code" = "0x" ]; then
    echo "0"
  else
    echo $(( (${#code} - 2) / 2 ))
  fi
}

print_code_check() {
  local label="$1"
  local address="$2"
  local bytes
  bytes="$(code_bytes "$address")"
  if [ "$bytes" -eq 0 ]; then
    echo "[FAIL] $label has no bytecode at $address"
    exit 1
  fi
  echo "[OK]   $label bytecode: $bytes bytes"
}

require_cast

echo "FlowPass Unichain Sepolia Verification"
echo "RPC: $RPC_URL"
echo

print_code_check "FlowPassV4Hook" "$HOOK"
print_code_check "FlowPassRouter" "$ROUTER"
print_code_check "Mock token A" "$TOKEN_A"
print_code_check "Mock token B" "$TOKEN_B"
echo

echo "Hook configuration"
echo "owner:           $(cast call "$HOOK" "owner()(address)" --rpc-url "$RPC_URL")"
echo "poolManager:     $(cast call "$HOOK" "poolManager()(address)" --rpc-url "$RPC_URL")"
echo "baseFee:         $(cast call "$HOOK" "baseFee()(uint24)" --rpc-url "$RPC_URL") pips"
echo "treasuryShare:   $(cast call "$HOOK" "treasuryShareBps()(uint16)" --rpc-url "$RPC_URL") bps"
echo "trusted router:  $(cast call "$HOOK" "trustedRouters(address)(bool)" "$ROUTER" --rpc-url "$RPC_URL")"
echo

echo "Pass state for deployment wallet"
cast call "$HOOK" "passes(bytes32,address)(uint128,uint64)" "$POOL_ID" "$DEPLOYMENT_WALLET" --rpc-url "$RPC_URL"
echo

echo "Explorer links"
echo "hook:   $EXPLORER_URL/address/$HOOK"
echo "router: $EXPLORER_URL/address/$ROUTER"
echo "swap:   $EXPLORER_URL/tx/$SWAP_TX"
