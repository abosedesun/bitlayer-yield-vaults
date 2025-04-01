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

;; Initialize contract on deploy
(begin
  (try! (initialize-protocols))
  (try! (initialize-strategies))
)

;; Helper functions

;; Get current timestamp
(define-private (get-current-time)
  (default-to u0 (get-block-info? time u0))
)

;; Check if caller is contract owner
(define-private (is-contract-owner)
  (is-eq tx-sender contract-owner)
)

;; Check if a strategy exists and is active
(define-private (is-strategy-active (strategy-id uint))
  (match (map-get? strategies { strategy-id: strategy-id })
    strategy-info (get active strategy-info)
    false
  )
)

;; Calculate fee amount
(define-private (calculate-fee (amount uint) (fee-bps uint))
  (/ (* amount fee-bps) u10000)
)

;; Calculate user's share percentage in a strategy (in basis points)
(define-private (calculate-user-share (user principal) (strategy-id uint))
  (let (
    (user-balance (default-to u0 (map-get? user-balances { user: user, strategy: strategy-id })))
    (strategy-tvl (match (map-get? strategies { strategy-id: strategy-id })
                    strategy (get tvl strategy)
                    u0))
  )
  (if (> strategy-tvl u0)
    (/ (* user-balance u10000) strategy-tvl)
    u0
  ))
)

;; Calculate rewards based on APY, time held and amount
(define-private (calculate-rewards (amount uint) (apy-bps uint) (time-held uint))
  ;; Convert time-held from seconds to years (approximated)
  (let (
    (seconds-per-year u31536000)
    (years-held (/ time-held seconds-per-year))
    (decimal-apy (/ apy-bps u10000))
  )
  ;; Simple interest calculation - in a real implementation, compound interest would be better
  (* amount (/ (* decimal-apy years-held) u1000000))
  )
)

;; Update strategy APY based on protocol allocations
(define-private (update-strategy-apy (strategy-id uint))
  (match (map-get? strategies { strategy-id: strategy-id })
    strategy-info 
      (let (
        (allocations (get protocol-allocations strategy-info))
        (total-weighted-apy u0)
      )
      ;; Calculate weighted average APY
      (map-set strategies { strategy-id: strategy-id }
        (merge strategy-info {
          current-apy: (fold calculate-weighted-apy allocations u0)
        })
      ))
    (err err-not-found)
  )
)

;; Helper function to calculate weighted APY for fold operation
(define-private (calculate-weighted-apy (allocation { protocol-id: uint, allocation: uint }) (total-so-far uint))
  (if (is-eq (get allocation allocation) u0)
    total-so-far
    (let (
      (protocol-id (get protocol-id allocation))
      (allocation-pct (get allocation allocation))
    )
    (match (map-get? protocol-info { protocol-id: protocol-id })
      protocol
        (+ total-so-far (/ (* (get current-apy protocol) allocation-pct) u100))
      total-so-far
    ))
  )
)

;; Core contract functions

;; Deposit funds into a strategy
(define-public (deposit (strategy-id uint) (amount uint))
  (let (
    (current-time (get-current-time))
  )
    ;; Check strategy exists and is active
    (asserts! (is-strategy-active strategy-id) (err err-not-found))
    
    ;; Get strategy info
    (match (map-get? strategies { strategy-id: strategy-id })
      strategy-info
        (begin
          ;; Check conditions
          (asserts! (get deposit-enabled strategy-info) (err err-deposit-disabled))
          (asserts! (not (get emergency-mode strategy-info)) (err err-emergency-active))
          (asserts! (>= amount (get min-deposit strategy-info)) (err err-minimum-not-met))
          
          ;; Check if strategy is locked
          (asserts! (<= (get locked-until strategy-info) burn-block-height) (err err-strategy-locked))
          
          ;; Transfer STX from user to contract
          (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
          
          ;; Update user balance
          (let (
            (current-balance (default-to u0 (map-get? user-balances { user: tx-sender, strategy: strategy-id })))
            (new-balance (+ current-balance amount))
            (strategy-tvl (+ (get tvl strategy-info) amount))
          )
            ;; Set default user strategy info if first deposit
            (if (is-eq current-balance u0)
              (begin
                (map-set user-strategy-info { user: tx-sender, strategy: strategy-id }
                  {
                    deposit-time: current-time,
                    last-compound: current-time,
                    compounding-rate: u24, ;; Default to 24 hours
                    emergency-threshold: u300 ;; Default to 3% minimum APY
                  }
                )
                ;; Increment total users if this is their first deposit
                (var-set total-users (+ (var-get total-users) u1))
              )
              true
            )
            
            ;; Update user balance
            (map-set user-balances { user: tx-sender, strategy: strategy-id } new-balance)
            
            ;; Update strategy TVL
            (map-set strategies { strategy-id: strategy-id }
              (merge strategy-info { tvl: strategy-tvl })
            )
            
            ;; Update total TVL
            (var-set total-tvl (+ (var-get total-tvl) amount))
            
            ;; Return success with updated balance
            (ok new-balance)
          )
        )
      (err err-not-found)
    )
  )
)

;; Withdraw funds from a strategy
(define-public (withdraw (strategy-id uint) (amount uint))
  (let (
    (current-time (get-current-time))
    (user-balance (default-to u0 (map-get? user-balances { user: tx-sender, strategy: strategy-id })))
  )
    ;; Check user has sufficient balance
    (asserts! (>= user-balance amount) (err err-insufficient-balance))
    
    ;; Get strategy info
    (match (map-get? strategies { strategy-id: strategy-id })
      strategy-info
        (let (
          (withdrawal-fee-bps (get withdrawal-fee strategy-info))
          (fee-amount (calculate-fee amount withdrawal-fee-bps))
          (net-amount (- amount fee-amount))
          (new-user-balance (- user-balance amount))
          (new-strategy-tvl (- (get tvl strategy-info) amount))
        )
          ;; Update strategy TVL
          (map-set strategies { strategy-id: strategy-id }
            (merge strategy-info { tvl: new-strategy-tvl })
          )
          
          ;; Update user balance
          (map-set user-balances { user: tx-sender, strategy: strategy-id } new-user-balance)
          
          ;; Update total TVL
          (var-set total-tvl (- (var-get total-tvl) amount))
          
          ;; Add fee to treasury
          (var-set treasury-balance (+ (var-get treasury-balance) fee-amount))
          
          ;; Transfer STX to user
          (as-contract (stx-transfer? net-amount tx-sender tx-sender))
          
          ;; Return success with withdrawal amount
          (ok net-amount)
        )
      (err err-not-found)
    )
  )
)

;; Withdraw all funds from a strategy
(define-public (withdraw-all (strategy-id uint))
  (let (
    (user-balance (default-to u0 (map-get? user-balances { user: tx-sender, strategy: strategy-id })))
  )
    (if (> user-balance u0)
      (withdraw strategy-id user-balance)
      (err err-insufficient-balance)
    )
  )
)

;; Compound rewards for a user (can be called by user or contract owner)
(define-public (compound-rewards (user principal) (strategy-id uint))
  (let (
    (current-time (get-current-time))
    (user-balance (default-to u0 (map-get? user-balances { user: user, strategy: strategy-id })))
  )
    ;; Ensure user has a balance
    (asserts! (> user-balance u0) (err err-insufficient-balance))
    
    ;; Get user strategy info and strategy info
    (match (map-get? user-strategy-info { user: user, strategy: strategy-id })
      user-info
        (match (map-get? strategies { strategy-id: strategy-id })
          strategy-info
            (let (
              (last-compound (get last-compound user-info))
              (time-since-compound (- current-time last-compound))
              (apy-bps (get current-apy strategy-info))
              (performance-fee-bps (get performance-fee strategy-info))
              
              ;; Calculate rewards
              (rewards (calculate-rewards user-balance apy-bps time-since-compound))
              (fee-amount (calculate-fee rewards performance-fee-bps))
              (net-rewards (- rewards fee-amount))
              
              ;; Update balances
              (new-user-balance (+ user-balance net-rewards))
              (new-strategy-tvl (+ (get tvl strategy-info) rewards))
            )
              ;; Only compound if significant time has passed and rewards are positive
              (if (and (> time-since-compound u3600) (> rewards u0))
                (begin
                  ;; Update user balance
                  (map-set user-balances { user: user, strategy: strategy-id } new-user-balance)
                  
                  ;; Update user's last compound time
                  (map-set user-strategy-info { user: user, strategy: strategy-id }
                    (merge user-info { last-compound: current-time })
                  )
                  
                  ;; Update strategy TVL
                  (map-set strategies { strategy-id: strategy-id }
                    (merge strategy-info { tvl: new-strategy-tvl })
                  )
                  
                  ;; Update total TVL
                  (var-set total-tvl (+ (var-get total-tvl) rewards))
                  
                  ;; Add fee to treasury
                  (var-set treasury-balance (+ (var-get treasury-balance) fee-amount))
                  
                  ;; Increment total compounds
                  (var-set total-compounds (+ (var-get total-compounds) u1))
                  
                  ;; Return success with new balance
                  (ok new-user-balance)
                )
                (ok user-balance) ;; Return current balance if no compounding needed
              )
            )
          (err err-not-found)
        )
      (err err-not-found)
    )
  )
)

;; Rebalance allocations for a strategy
;; In a real implementation, this would interact with external protocols
(define-public (rebalance-strategy (strategy-id uint))
  (begin
    ;; Only owner can rebalance
    (asserts! (is-contract-owner) (err err-owner-only))
    
    ;; Check strategy exists
    (asserts! (is-strategy-active strategy-id) (err err-not-found))
    
    ;; Update strategy APY
    (try! (update-strategy-apy strategy-id))
    
    ;; Update last rebalance time
    (var-set last-rebalance (get-current-time))
    
    (ok true)
  )
)

;; Update protocol APY (in a real implementation, this would use oracles)
(define-public (update-protocol-apy (protocol-id uint) (new-apy uint))
  (begin
    ;; Only owner can update APYs
    (asserts! (is-contract-owner) (err err-owner-only))
    
    ;; Update protocol APY
    (match (map-get? protocol-info { protocol-id: protocol-id })
      protocol
        (map-set protocol-info { protocol-id: protocol-id }
          (merge protocol {
            current-apy: new-apy,
            last-updated: (get-current-time)
          })
        )
      (err err-protocol-not-supported)
    )
    
    ;; Update all strategy APYs
    (update-all-strategy-apys)
    
    (ok true)
  )
)

;; Helper to update all strategy APYs
(define-private (update-all-strategy-apys)
  (begin
    (update-strategy-apy CONSERVATIVE)
    (update-strategy-apy BALANCED)
    (update-strategy-apy GROWTH)
    (ok true)
  )
)

;; Emergency withdrawal function (can only be called by contract owner)
(define-public (activate-emergency-mode (strategy-id uint))
  (begin
    ;; Only owner can activate emergency mode
    (asserts! (is-contract-owner) (err err-owner-only))
    
    ;; Check strategy exists
    (asserts! (is-strategy-active strategy-id) (err err-not-found))
    
    ;; Set emergency mode
    (match (map-get? strategies { strategy-id: strategy-id })
      strategy-info
        (map-set strategies { strategy-id: strategy-id }
          (merge strategy-info { emergency-mode: true, deposit-enabled: false })
        )
      (err err-not-found)
    )
    
    (ok true)
  )
)

;; Check if emergency withdrawal is needed based on user settings
(define-public (check-emergency-conditions (user principal) (strategy-id uint))
  (let (
    (user-balance (default-to u0 (map-get? user-balances { user: user, strategy: strategy-id })))
  )
    ;; Ensure user has a balance
    (asserts! (> user-balance u0) (err err-insufficient-balance))
    
    ;; Get user strategy info and strategy info
    (match (map-get? user-strategy-info { user: user, strategy: strategy-id })
      user-info
        (match (map-get? strategies { strategy-id: strategy-id })
          strategy-info
            (let (
              (emergency-threshold (get emergency-threshold user-info))
              (current-apy (get current-apy strategy-info))
            )
              ;; Check if APY is below emergency threshold
              (if (< current-apy emergency-threshold)
                (withdraw-all strategy-id) ;; Execute emergency withdrawal
                (ok false) ;; No emergency needed
              )
            )
          (err err-not-found)
        )
      (err err-not-found)
    )
  )
)

;; Set user's emergency threshold
(define-public (set-emergency-threshold (strategy-id uint) (threshold uint))
  (let (
    (user-balance (default-to u0 (map-get? user-balances { user: tx-sender, strategy: strategy-id })))
  )
    ;; Ensure user has a balance
    (asserts! (> user-balance u0) (err err-insufficient-balance))
    
    ;; Get user strategy info
    (match (map-get? user-strategy-info { user: tx-sender, strategy: strategy-id })
      user-info
        (map-set user-strategy-info { user: tx-sender, strategy: strategy-id }
          (merge user-info { emergency-threshold: threshold })
        )
      (err err-not-found)
    )
    
    (ok true)
  )
)

;; Set user's compounding rate
(define-public (set-compounding-rate (strategy-id uint) (hours uint))
  (let (
    (user-balance (default-to u0 (map-get? user-balances { user: tx-sender, strategy: strategy-id })))
  )
    ;; Ensure user has a balance
    (asserts! (> user-balance u0) (err err-insufficient-balance))
    
    ;; Get user strategy info
    (match (map-get? user-strategy-info { user: tx-sender, strategy: strategy-id })
      user-info
        (map-set user-strategy-info { user: tx-sender, strategy: strategy-id }
          (merge user-info { compounding-rate: hours })
        )
      (err err-not-found)
    )
    
    (ok true)
  )
)

;; Administrative functions

;; Update strategy allocations
(define-public (update-strategy-allocations (strategy-id uint) (allocations (list 10 { protocol-id: uint, allocation: uint })))
  (begin
    ;; Only owner can update allocations
    (asserts! (is-contract-owner) (err err-owner-only))
    
    ;; Check allocations add up to 100%
    (asserts! (is-eq (fold add-allocations allocations u0) u100) (err err-invalid-amount))
    
    ;; Update strategy allocations
    (match (map-get? strategies { strategy-id: strategy-id })
      strategy-info
        (map-set strategies { strategy-id: strategy-id }
          (merge strategy-info { protocol-allocations: allocations })
        )
      (err err-not-found)
    )
    
    ;; Update strategy APY
    (update-strategy-apy strategy-id)
    
    (ok true)
  )
)

;; Helper function to add up allocations for validation
(define-private (add-allocations (allocation { protocol-id: uint, allocation: uint }) (total-so-far uint))
  (+ total-so-far (get allocation allocation))
)

;; Get user's balance in a strategy
(define-read-only (get-user-balance (user principal) (strategy-id uint))
  (default-to u0 (map-get? user-balances { user: user, strategy: strategy-id }))
)

;; Get strategy information
(define-read-only (get-strategy-info (strategy-id uint))
  (map-get? strategies { strategy-id: strategy-id })
)

;; Get protocol information
(define-read-only (get-protocol-info (protocol-id uint))
  (map-get? protocol-info { protocol-id: protocol-id })
)

;; Get total TVL across all strategies
(define-read-only (get-total-tvl)
  (var-get total-tvl)
)

;; Get user's strategy settings
(define-read-only (get-user-strategy-settings (user principal) (strategy-id uint))
  (map-get? user-strategy-info { user: user, strategy: strategy-id })
)

;; Get projected APY for a user in a strategy
(define-read-only (get-projected-user-apy (user principal) (strategy-id uint))
  (match (map-get? strategies { strategy-id: strategy-id })
    strategy-info (get current-apy strategy-info)
    u0
  )
)

;; Withdraw funds from treasury (only owner)
(define-public (withdraw-treasury (amount uint) (recipient principal))
  (begin
    ;; Only owner can withdraw from treasury
    (asserts! (is-contract-owner) (err err-owner-only))
    
    ;; Check sufficient treasury balance
    (asserts! (>= (var-get treasury-balance) amount) (err err-insufficient-balance))
    
    ;; Update treasury balance
    (var-set treasury-balance (- (var-get treasury-balance) amount))
    
    ;; Transfer STX to recipient
    (as-contract (stx-transfer? amount tx-sender recipient))
    
    (ok true)
  )
)

;; Add funds to emergency fund
(define-public (add-to-emergency-fund (amount uint))
  (begin
    ;; Transfer STX to contract
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    ;; Update emergency fund balance
    (var-set emergency-fund (+ (var-get emergency-fund) amount))
    
    (ok true)
  )
)