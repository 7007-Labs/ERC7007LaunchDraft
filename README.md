## ERC7007Launch

### Architecture

```mermaid
graph TD;
    B[ERC7007Launch]-->C[PairFactory];
    C-->D[PairERC7007ETH];
    B-->E[NFTCollectionFactory]
    E-->F[ORAERC7007Impl]
    F-->G[RandOracle]
    F-->J[AIOracle]
    D-->H[RoyaltyExecutor]
    D-->I[FeeManager]
    D-->F
```
