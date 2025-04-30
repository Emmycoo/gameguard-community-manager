;; game-guard.clar
;; GameGuard Community Manager Contract

;; This contract manages gaming communities on the Stacks blockchain, providing
;; functionality for community creation, membership management, governance,
;; and resource allocation. It offers verifiable membership credentials,
;; role-based permissions, and transparent community operations.

;; ==========================================
;; Constants & Error Codes
;; ==========================================

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-COMMUNITY-EXISTS (err u101))
(define-constant ERR-COMMUNITY-NOT-FOUND (err u102))
(define-constant ERR-MEMBER-EXISTS (err u103))
(define-constant ERR-MEMBER-NOT-FOUND (err u104))
(define-constant ERR-INVALID-ROLE (err u105))
(define-constant ERR-INVALID-PARAMETERS (err u106))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u107))
(define-constant ERR-ALREADY-VOTED (err u108))
(define-constant ERR-PROPOSAL-EXPIRED (err u109))
(define-constant ERR-INSUFFICIENT-FUNDS (err u110))
(define-constant ERR-INVALID-STATE (err u111))

;; Role constants
(define-constant ROLE-FOUNDER u1)
(define-constant ROLE-ADMIN u2)
(define-constant ROLE-MODERATOR u3)
(define-constant ROLE-MEMBER u4)

;; Proposal status constants
(define-constant PROPOSAL-STATUS-ACTIVE u1)
(define-constant PROPOSAL-STATUS-APPROVED u2)
(define-constant PROPOSAL-STATUS-REJECTED u3)
(define-constant PROPOSAL-STATUS-EXECUTED u4)

;; ==========================================
;; Data Maps & Variables
;; ==========================================

;; Community data structure
(define-map communities
  { community-id: uint }
  {
    name: (string-ascii 50),
    description: (string-utf8 500),
    founder: principal,
    created-at: uint,
    member-count: uint,
    treasury-balance: uint,
    metadata-url: (optional (string-ascii 100))
  }
)

;; Membership records
(define-map community-members
  { community-id: uint, member: principal }
  {
    role: uint,
    joined-at: uint,
    status: uint,  ;; 1 = active, 2 = suspended, 3 = banned
    reputation: uint
  }
)

;; Proposals for community governance
(define-map proposals
  { community-id: uint, proposal-id: uint }
  {
    title: (string-ascii 100),
    description: (string-utf8 1000),
    proposer: principal,
    created-at: uint,
    expires-at: uint,
    status: uint,
    yes-votes: uint,
    no-votes: uint,
    execution-params: (optional (list 10 {name: (string-ascii 50), value: (string-utf8 200)}))
  }
)

;; Voting records to prevent double voting
(define-map proposal-votes
  { community-id: uint, proposal-id: uint, voter: principal }
  { vote: bool }  ;; true = yes, false = no
)

;; Community resources/assets
(define-map community-resources
  { community-id: uint, resource-id: uint }
  {
    name: (string-ascii 50),
    description: (string-utf8 200),
    resource-type: (string-ascii 20),
    value: uint,
    controller: principal,
    metadata-url: (optional (string-ascii 100))
  }
)

;; Counter for community IDs
(define-data-var next-community-id uint u1)

;; Counter for proposal IDs (per community)
(define-map next-proposal-id
  { community-id: uint }
  { id: uint }
)

;; Counter for resource IDs (per community)
(define-map next-resource-id
  { community-id: uint }
  { id: uint }
)

;; ==========================================
;; Private Functions
;; ==========================================

;; Get the next community ID and increment the counter
(define-private (get-and-increment-community-id)
  (let ((current-id (var-get next-community-id)))
    (var-set next-community-id (+ current-id u1))
    current-id
  )
)

;; Get the next proposal ID for a community and increment the counter
(define-private (get-and-increment-proposal-id (community-id uint))
  (let ((current-id (default-to u1 (get id (map-get? next-proposal-id {community-id: community-id})))))
    (map-set next-proposal-id {community-id: community-id} {id: (+ current-id u1)})
    current-id
  )
)

;; Get the next resource ID for a community and increment the counter
(define-private (get-and-increment-resource-id (community-id uint))
  (let ((current-id (default-to u1 (get id (map-get? next-resource-id {community-id: community-id})))))
    (map-set next-resource-id {community-id: community-id} {id: (+ current-id u1)})
    current-id
  )
)

;; Check if the principal is a member of the community with the specified role or higher permission
(define-private (has-role (community-id uint) (user principal) (required-role uint))
  (match (map-get? community-members {community-id: community-id, member: user})
    member-data (if (and 
                      (>= required-role (get role member-data))
                      (is-eq (get status member-data) u1)) ;; active status
                  true
                  false)
    false
  )
)

;; Check if community exists
(define-private (community-exists (community-id uint))
  (is-some (map-get? communities {community-id: community-id}))
)

;; ==========================================
;; Read-Only Functions
;; ==========================================

;; Get community details
(define-read-only (get-community (community-id uint))
  (match (map-get? communities {community-id: community-id})
    community-data (ok community-data)
    ERR-COMMUNITY-NOT-FOUND
  )
)

;; Get member details within a community
(define-read-only (get-member (community-id uint) (member principal))
  (match (map-get? community-members {community-id: community-id, member: member})
    member-data (ok member-data)
    ERR-MEMBER-NOT-FOUND
  )
)

;; Get proposal details
(define-read-only (get-proposal (community-id uint) (proposal-id uint))
  (match (map-get? proposals {community-id: community-id, proposal-id: proposal-id})
    proposal-data (ok proposal-data)
    ERR-PROPOSAL-NOT-FOUND
  )
)

;; Check if principal has voted on a specific proposal
(define-read-only (has-voted (community-id uint) (proposal-id uint) (voter principal))
  (is-some (map-get? proposal-votes {community-id: community-id, proposal-id: proposal-id, voter: voter}))
)

;; Get resource details
(define-read-only (get-resource (community-id uint) (resource-id uint))
  (match (map-get? community-resources {community-id: community-id, resource-id: resource-id})
    resource-data (ok resource-data)
    (err u112) ;; resource not found
  )
)

;; ==========================================
;; Public Functions
;; ==========================================

;; Create a new gaming community
(define-public (create-community (name (string-ascii 50)) (description (string-utf8 500)) (metadata-url (optional (string-ascii 100))))
  (let 
    (
      (new-community-id (get-and-increment-community-id))
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    
    (map-set communities 
      {community-id: new-community-id}
      {
        name: name,
        description: description,
        founder: tx-sender,
        created-at: current-time,
        member-count: u1, ;; Founder is the first member
        treasury-balance: u0,
        metadata-url: metadata-url
      }
    )
    
    ;; Add founder as the first member with founder role
    (map-set community-members
      {community-id: new-community-id, member: tx-sender}
      {
        role: ROLE-FOUNDER,
        joined-at: current-time,
        status: u1, ;; Active
        reputation: u100 ;; Initial reputation
      }
    )
    
    ;; Initialize counters
    (map-set next-proposal-id {community-id: new-community-id} {id: u1})
    (map-set next-resource-id {community-id: new-community-id} {id: u1})
    
    (ok new-community-id)
  )
)

;; Add a new member to the community
(define-public (add-member (community-id uint) (new-member principal))
  (let
    (
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    
    ;; Check authorization (only founder, admin, or moderator can add members)
    (asserts! (has-role community-id tx-sender ROLE-MODERATOR) ERR-NOT-AUTHORIZED)
    
    ;; Check if community exists
    (asserts! (community-exists community-id) ERR-COMMUNITY-NOT-FOUND)
    
    ;; Check if member already exists
    (asserts! (is-none (map-get? community-members {community-id: community-id, member: new-member})) ERR-MEMBER-EXISTS)
    
    ;; Add the new member
    (map-set community-members
      {community-id: community-id, member: new-member}
      {
        role: ROLE-MEMBER,
        joined-at: current-time,
        status: u1, ;; Active
        reputation: u50 ;; Initial reputation
      }
    )
    
    ;; Update community member count
    (match (map-get? communities {community-id: community-id})
      community-data 
        (map-set communities 
          {community-id: community-id}
          (merge community-data {member-count: (+ (get member-count community-data) u1)})
        )
      (err u113) ;; This should never happen since we checked community exists
    )
    
    (ok true)
  )
)

;; Update member role in community
(define-public (update-member-role (community-id uint) (member principal) (new-role uint))
  (begin
    ;; Check authorization (only founder or admin can update roles)
    (asserts! (has-role community-id tx-sender ROLE-ADMIN) ERR-NOT-AUTHORIZED)
    
    ;; Check if community exists
    (asserts! (community-exists community-id) ERR-COMMUNITY-NOT-FOUND)
    
    ;; Validate role value
    (asserts! (and (>= new-role ROLE-FOUNDER) (<= new-role ROLE-MEMBER)) ERR-INVALID-ROLE)
    
    ;; Get member data
    (match (map-get? community-members {community-id: community-id, member: member})
      member-data 
        (begin
          ;; Special check: Only founder can appoint a new founder
          (if (is-eq new-role ROLE-FOUNDER)
            (asserts! (has-role community-id tx-sender ROLE-FOUNDER) ERR-NOT-AUTHORIZED)
            true
          )
          
          ;; Update the role
          (map-set community-members
            {community-id: community-id, member: member}
            (merge member-data {role: new-role})
          )
          
          (ok true)
        )
      ERR-MEMBER-NOT-FOUND
    )
  )
)

;; Remove a member from the community
(define-public (remove-member (community-id uint) (member principal))
  (begin
    ;; Check authorization (only founder, admin, or moderator can remove members)
    (asserts! (has-role community-id tx-sender ROLE-MODERATOR) ERR-NOT-AUTHORIZED)
    
    ;; Additional check: can't remove founder
    (match (map-get? community-members {community-id: community-id, member: member})
      member-data 
        (asserts! (not (is-eq (get role member-data) ROLE-FOUNDER)) ERR-NOT-AUTHORIZED)
      ERR-MEMBER-NOT-FOUND
    )
    
    ;; Check if community exists
    (asserts! (community-exists community-id) ERR-COMMUNITY-NOT-FOUND)
    
    ;; Remove the member
    (map-delete community-members {community-id: community-id, member: member})
    
    ;; Update community member count
    (match (map-get? communities {community-id: community-id})
      community-data 
        (map-set communities 
          {community-id: community-id}
          (merge community-data {member-count: (- (get member-count community-data) u1)})
        )
      (err u113) ;; This should never happen since we checked community exists
    )
    
    (ok true)
  )
)

;; Create a new governance proposal
(define-public (create-proposal 
  (community-id uint) 
  (title (string-ascii 100)) 
  (description (string-utf8 1000))
  (expires-in uint)
  (execution-params (optional (list 10 {name: (string-ascii 50), value: (string-utf8 200)}))))
  
  (let
    (
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
      (proposal-id (get-and-increment-proposal-id community-id))
    )
    
    ;; Check authorization (only members can create proposals)
    (asserts! (has-role community-id tx-sender ROLE-MEMBER) ERR-NOT-AUTHORIZED)
    
    ;; Check if community exists
    (asserts! (community-exists community-id) ERR-COMMUNITY-NOT-FOUND)
    
    ;; Create the proposal
    (map-set proposals
      {community-id: community-id, proposal-id: proposal-id}
      {
        title: title,
        description: description,
        proposer: tx-sender,
        created-at: current-time,
        expires-at: (+ current-time expires-in),
        status: PROPOSAL-STATUS-ACTIVE,
        yes-votes: u0,
        no-votes: u0,
        execution-params: execution-params
      }
    )
    
    (ok proposal-id)
  )
)

;; Vote on a proposal
(define-public (vote-on-proposal (community-id uint) (proposal-id uint) (vote bool))
  (let
    (
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    
    ;; Check authorization (only members can vote)
    (asserts! (has-role community-id tx-sender ROLE-MEMBER) ERR-NOT-AUTHORIZED)
    
    ;; Check if community exists
    (asserts! (community-exists community-id) ERR-COMMUNITY-NOT-FOUND)
    
    ;; Check if already voted
    (asserts! (is-none (map-get? proposal-votes {community-id: community-id, proposal-id: proposal-id, voter: tx-sender})) ERR-ALREADY-VOTED)
    
    ;; Check if proposal exists and is active
    (match (map-get? proposals {community-id: community-id, proposal-id: proposal-id})
      proposal-data
        (begin
          ;; Check if proposal is still active
          (asserts! (is-eq (get status proposal-data) PROPOSAL-STATUS-ACTIVE) ERR-INVALID-STATE)
          
          ;; Check if proposal hasn't expired
          (asserts! (<= current-time (get expires-at proposal-data)) ERR-PROPOSAL-EXPIRED)
          
          ;; Record the vote
          (map-set proposal-votes
            {community-id: community-id, proposal-id: proposal-id, voter: tx-sender}
            {vote: vote}
          )
          
          ;; Update vote counts
          (if vote
            (map-set proposals 
              {community-id: community-id, proposal-id: proposal-id}
              (merge proposal-data {yes-votes: (+ (get yes-votes proposal-data) u1)})
            )
            (map-set proposals 
              {community-id: community-id, proposal-id: proposal-id}
              (merge proposal-data {no-votes: (+ (get no-votes proposal-data) u1)})
            )
          )
          
          (ok true)
        )
      ERR-PROPOSAL-NOT-FOUND
    )
  )
)

;; Finalize a proposal (changes status based on votes)
(define-public (finalize-proposal (community-id uint) (proposal-id uint))
  (begin
    ;; Check authorization (only admins or higher or the proposer can finalize)
    (match (map-get? proposals {community-id: community-id, proposal-id: proposal-id})
      proposal-data
        (asserts! (or 
                    (has-role community-id tx-sender ROLE-ADMIN)
                    (is-eq tx-sender (get proposer proposal-data))
                  ) 
                  ERR-NOT-AUTHORIZED)
      ERR-PROPOSAL-NOT-FOUND
    )
    
    ;; Check if community exists
    (asserts! (community-exists community-id) ERR-COMMUNITY-NOT-FOUND)
    
    ;; Check if proposal exists and is active
    (match (map-get? proposals {community-id: community-id, proposal-id: proposal-id})
      proposal-data
        (begin
          ;; Check if proposal is still active
          (asserts! (is-eq (get status proposal-data) PROPOSAL-STATUS-ACTIVE) ERR-INVALID-STATE)
          
          ;; Check if expired or has sufficient votes
          (let
            (
              (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
              (new-status (if (> (get yes-votes proposal-data) (get no-votes proposal-data))
                            PROPOSAL-STATUS-APPROVED
                            PROPOSAL-STATUS-REJECTED))
            )
            
            (asserts! (>= current-time (get expires-at proposal-data)) ERR-INVALID-STATE)
            
            ;; Update proposal status
            (map-set proposals 
              {community-id: community-id, proposal-id: proposal-id}
              (merge proposal-data {status: new-status})
            )
            
            (ok new-status)
          )
        )
      ERR-PROPOSAL-NOT-FOUND
    )
  )
)

;; Add a community resource
(define-public (add-resource 
  (community-id uint) 
  (name (string-ascii 50)) 
  (description (string-utf8 200))
  (resource-type (string-ascii 20))
  (value uint)
  (metadata-url (optional (string-ascii 100))))
  
  (let
    (
      (resource-id (get-and-increment-resource-id community-id))
    )
    
    ;; Check authorization (only admins or higher can add resources)
    (asserts! (has-role community-id tx-sender ROLE-ADMIN) ERR-NOT-AUTHORIZED)
    
    ;; Check if community exists
    (asserts! (community-exists community-id) ERR-COMMUNITY-NOT-FOUND)
    
    ;; Create the resource
    (map-set community-resources
      {community-id: community-id, resource-id: resource-id}
      {
        name: name,
        description: description,
        resource-type: resource-type,
        value: value,
        controller: tx-sender,
        metadata-url: metadata-url
      }
    )
    
    (ok resource-id)
  )
)

;; Deposit STX to community treasury
(define-public (deposit-to-treasury (community-id uint) (amount uint))
  (begin
    ;; Check if community exists
    (asserts! (community-exists community-id) ERR-COMMUNITY-NOT-FOUND)
    
    ;; Transfer STX from sender to contract
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    ;; Update treasury balance
    (match (map-get? communities {community-id: community-id})
      community-data 
        (map-set communities 
          {community-id: community-id}
          (merge community-data {treasury-balance: (+ (get treasury-balance community-data) amount)})
        )
      ERR-COMMUNITY-NOT-FOUND
    )
    
    (ok true)
  )
)

;; Withdraw STX from community treasury
(define-public (withdraw-from-treasury (community-id uint) (amount uint) (recipient principal))
  (begin
    ;; Check authorization (only admins or higher can withdraw)
    (asserts! (has-role community-id tx-sender ROLE-ADMIN) ERR-NOT-AUTHORIZED)
    
    ;; Check if community exists
    (asserts! (community-exists community-id) ERR-COMMUNITY-NOT-FOUND)
    
    ;; Check if treasury has enough funds
    (match (map-get? communities {community-id: community-id})
      community-data 
        (begin
          (asserts! (>= (get treasury-balance community-data) amount) ERR-INSUFFICIENT-FUNDS)
          
          ;; Update treasury balance
          (map-set communities 
            {community-id: community-id}
            (merge community-data {treasury-balance: (- (get treasury-balance community-data) amount)})
          )
          
          ;; Transfer STX from contract to recipient
          (as-contract (stx-transfer? amount tx-sender recipient))
        )
      ERR-COMMUNITY-NOT-FOUND
    )
    
    (ok true)
  )
)

;; Update member reputation
(define-public (update-reputation (community-id uint) (member principal) (new-reputation uint))
  (begin
    ;; Check authorization (only moderators or higher can update reputation)
    (asserts! (has-role community-id tx-sender ROLE-MODERATOR) ERR-NOT-AUTHORIZED)
    
    ;; Check if community exists
    (asserts! (community-exists community-id) ERR-COMMUNITY-NOT-FOUND)
    
    ;; Update the member's reputation
    (match (map-get? community-members {community-id: community-id, member: member})
      member-data 
        (map-set community-members
          {community-id: community-id, member: member}
          (merge member-data {reputation: new-reputation})
        )
      ERR-MEMBER-NOT-FOUND
    )
    
    (ok true)
  )
)

;; Update community details
(define-public (update-community 
  (community-id uint) 
  (name (string-ascii 50)) 
  (description (string-utf8 500))
  (metadata-url (optional (string-ascii 100))))
  
  (begin
    ;; Check authorization (only admins or higher can update community)
    (asserts! (has-role community-id tx-sender ROLE-ADMIN) ERR-NOT-AUTHORIZED)
    
    ;; Check if community exists
    (asserts! (community-exists community-id) ERR-COMMUNITY-NOT-FOUND)
    
    ;; Update community details
    (match (map-get? communities {community-id: community-id})
      community-data 
        (map-set communities 
          {community-id: community-id}
          (merge community-data {
            name: name,
            description: description,
            metadata-url: metadata-url
          })
        )
      ERR-COMMUNITY-NOT-FOUND
    )
    
    (ok true)
  )
)