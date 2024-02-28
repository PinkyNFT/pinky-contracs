- Support erc721 and erc1155

- Direct sell
    - accept native/token
    - time
    - transfer the nft when paid
    - user can cancel listing
    
- Auction
    - accept native/token
    - previous bid + percentage <= New bid price
    - nft will be held in the marketplace contract
    - during auction, user can't direct sell/accept offer for the nft
    - When making auction previous direct sell will be dismissed
    - nft will be sent to the heightest bidder after auction ends
    - if no bids, it will go back to the user

- Offer
    - user can make offer on any nft
    - accept token only
    - limited time offer
