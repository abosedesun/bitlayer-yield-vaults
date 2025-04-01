;; Title: 
;; BitLayer Yield Vaults - Automated Multi-Strategy Management Protocol
;; 
;; Summary:
;; Non-custodial yield optimization engine for Stacks L2, offering institutional-grade strategy management
;; with Bitcoin settlement finality. Features risk-tiered vaults, protocol diversification, and smart auto-compounding.
;;
;; Description:
;; BitLayer Yield Vaults implements a sophisticated yield aggregation system native to Bitcoin via Stacks Layer 2.
;; The protocol offers three core investment strategies:
;; - Conservative (Stablecoin lending, insured positions)
;; - Balanced (Liquid staking, blue-chip LP positions)
;; - Growth (High-yield farming with dynamic exit strategies)
;;
;; Key Features:
;; - Multi-protocol diversification across Stackswap, Arkadiko, ALEX, and Zest
;; - Auto-rebalancing based on real-time APY oracles
;; - Emergency withdrawal triggers with user-defined APY thresholds
;; - Compounding engine with customizable intervals
;; - Bitcoin-native security model with STX settlement
;; - Transparent fee structure (0.5-2% withdrawal fees + 10-20% performance fees)
;; - TVL-weighted protocol allocations for risk mitigation
;;
;; Designed for Bitcoin DeFi compliance:
;; 1. Non-custodial asset management
;; 2. Minimally-extractive fee model
;; 3. Time-locked admin functions
;; 4. On-chain audit trail for all rebalancing
;; 5. Emergency fund for protocol failure scenarios
;;
;; Implements Bitcoin-centric security practices:
;; - All withdrawals settle through Bitcoin-final transactions
;; - Treasury management via multisig timelocks
;; - Strategy freeze capabilities for market turmoil
;; - STX-denominated risk parameters

;; Error codes
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-insufficient-balance (err u103))
(define-constant err-invalid-amount (err u104))
(define-constant err-emergency-active (err u105))
(define-constant err-minimum-not-met (err u106))
(define-constant err-strategy-locked (err u107))
(define-constant err-deposit-disabled (err u108))
(define-constant err-protocol-not-supported (err u109))

;; Strategy risk levels
(define-constant CONSERVATIVE u1)
(define-constant BALANCED u2)
(define-constant GROWTH u3)

;; Protocol identifiers
(define-constant PROTOCOL-STACKSWAP u1)
(define-constant PROTOCOL-ARKADIKO u2)
(define-constant PROTOCOL-ALEX u3)
(define-constant PROTOCOL-ZEST u4)

;; Data maps for storing user and vault information
(define-map user-balances { user: principal, strategy: uint } uint)
(define-map user-strategy-info 
  { user: principal, strategy: uint }
  { 
    deposit-time: uint,
    last-compound: uint,
    compounding-rate: uint,  ;; hours between compounding
    emergency-threshold: uint ;; minimum APY before emergency withdrawal (basis points)
  }
)

(define-map strategies
  { strategy-id: uint }
  {
    name: (string-ascii 50),
    description: (string-ascii 200),
    risk-level: uint,
    active: bool,
    tvl: uint,
    current-apy: uint, ;; basis points (10000 = 100%)
    protocol-allocations: (list 10 { protocol-id: uint, allocation: uint }), ;; allocation in percentage (100 = 100%)
    min-deposit: uint,
    locked-until: uint, ;; block height
    deposit-enabled: bool,
    withdrawal-fee: uint, ;; basis points
    performance-fee: uint, ;; basis points
    emergency-mode: bool
  }
)

(define-map protocol-info
  { protocol-id: uint }
  {
    name: (string-ascii 50),
    contract-address: principal,
    current-apy: uint, ;; basis points
    active: bool,
    last-updated: uint
  }
)

;; Track total vault statistics
(define-data-var total-tvl uint u0)
(define-data-var total-users uint u0)
(define-data-var total-protocols uint u4) ;; Initially supporting 4 protocols
(define-data-var total-compounds uint u0)
(define-data-var treasury-balance uint u0)
(define-data-var emergency-fund uint u0)
(define-data-var last-rebalance uint u0) ;; timestamp

;; Initialize protocols with default values
(define-private (initialize-protocols)
  (begin
    (map-set protocol-info { protocol-id: PROTOCOL-STACKSWAP }
      { 
        name: "Stackswap", 
        contract-address: 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM,
        current-apy: u500, ;; 5%
        active: true,
        last-updated: (get-block-info? time u0)
      }
    )
    (map-set protocol-info { protocol-id: PROTOCOL-ARKADIKO }
      { 
        name: "Arkadiko", 
        contract-address: 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM,
        current-apy: u700, ;; 7%
        active: true,
        last-updated: (get-block-info? time u0)
      }
    )
    (map-set protocol-info { protocol-id: PROTOCOL-ALEX }
      { 
        name: "ALEX", 
        contract-address: 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM,
        current-apy: u900, ;; 9%
        active: true,
        last-updated: (get-block-info? time u0)
      }
    )
    (map-set protocol-info { protocol-id: PROTOCOL-ZEST }
      { 
        name: "Zest", 
        contract-address: 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM,
        current-apy: u800, ;; 8%
        active: true,
        last-updated: (get-block-info? time u0)
      }
    )
    (ok true)
  )
)

;; Initialize strategies with default configurations
(define-private (initialize-strategies)
  (begin
    ;; Conservative Strategy
    (map-set strategies { strategy-id: CONSERVATIVE }
      {
        name: "Conservative Vault",
        description: "Stablecoin pools with insured lending positions for lower risk",
        risk-level: CONSERVATIVE,
        active: true,
        tvl: u0,
        current-apy: u650, ;; 6.5%
        protocol-allocations: (list 
          { protocol-id: PROTOCOL-ZEST, allocation: u50 }
          { protocol-id: PROTOCOL-ARKADIKO, allocation: u50 }
          { protocol-id: u0, allocation: u0 }
          { protocol-id: u0, allocation: u0 }
          { protocol-id: u0, allocation: u0 }
          { protocol-id: u0, allocation: u0 }
          { protocol-id: u0, allocation: u0 }
          { protocol-id: u0, allocation: u0 }
          { protocol-id: u0, allocation: u0 }
          { protocol-id: u0, allocation: u0 }
        ),
        min-deposit: u1000000, ;; 1 STX minimum
        locked-until: u0,
        deposit-enabled: true,
        withdrawal-fee: u50, ;; 0.5%
        performance-fee: u1000, ;; 10%
        emergency-mode: false
      }
    )
    
    ;; Balanced Strategy
    (map-set strategies { strategy-id: BALANCED }
      {
        name: "Balanced Vault",
        description: "BTC/STX LP positions and leveraged staking for moderate risk",
        risk-level: BALANCED,
        active: true,
        tvl: u0,
        current-apy: u1200, ;; 12%
        protocol-allocations: (list 
          { protocol-id: PROTOCOL-STACKSWAP, allocation: u40 }
          { protocol-id: PROTOCOL-ALEX, allocation: u40 }
          { protocol-id: PROTOCOL-ARKADIKO, allocation: u20 }
          { protocol-id: u0, allocation: u0 }
          { protocol-id: u0, allocation: u0 }
          { protocol-id: u0, allocation: u0 }
          { protocol-id: u0, allocation: u0 }
          { protocol-id: u0, allocation: u0 }
          { protocol-id: u0, allocation: u0 }
          { protocol-id: u0, allocation: u0 }
        ),
        min-deposit: u10000000, ;; 10 STX minimum
        locked-until: u0,
        deposit-enabled: true,
        withdrawal-fee: u100, ;; 1%
        performance-fee: u1500, ;; 15%
        emergency-mode: false
      }
    )
    
    ;; Growth Strategy
    (map-set strategies { strategy-id: GROWTH }
      {
        name: "Growth Vault",
        description: "High APY farming on new protocols with dynamic exit strategies",
        risk-level: GROWTH,
        active: true,
        tvl: u0,
        current-apy: u2000, ;; 20%
        protocol-allocations: (list 
          { protocol-id: PROTOCOL-ALEX, allocation: u60 }
          { protocol-id: PROTOCOL-STACKSWAP, allocation: u40 }
          { protocol-id: u0, allocation: u0 }
          { protocol-id: u0, allocation: u0 }
          { protocol-id: u0, allocation: u0 }
          { protocol-id: u0, allocation: u0 }
          { protocol-id: u0, allocation: u0 }
          { protocol-id: u0, allocation: u0 }
          { protocol-id: u0, allocation: u0 }
          { protocol-id: u0, allocation: u0 }
        ),
        min-deposit: u50000000, ;; 50 STX minimum
        locked-until: u0,
        deposit-enabled: true,
        withdrawal-fee: u200, ;; 2%
        performance-fee: u2000, ;; 20%
        emergency-mode: false
      }
    )
    (ok true)
  )
)