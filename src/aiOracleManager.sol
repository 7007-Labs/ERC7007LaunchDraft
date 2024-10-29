contract aiOracleManager {
// function reveal(uint256[] memory tokenIds) external payable {
//     // todo: 改成初次售出后任意用户可以调用,理论上pair会判断是否初次交易，如果是初次交易，就会调用此函数。
//     // todo: 考虑初次售出后生成seed,不调用aiOracle
//     require(msg.sender == pair, "Only Pair can reveal");
//     uint256 size = tokenIds.length;
//     require(size > 0);
//     bytes[] memory prompts = new bytes[](size);
//     uint256[] memory seeds = new uint256[](size);
//     bytes memory batchPrompt = "[";
//     for (uint256 i = 0; i < size; i++) {
//         if (i > 0) {
//             batchPrompt = bytes.concat(batchPrompt, ",");
//         }
//         uint256 seed = getSeed(tokenIds[i]);
//         bytes memory prompt = ORAUtils.buildPrompt(basePrompt, seed);
//         prompts[i] = prompt;
//         seeds[i] = seed;
//         batchPrompt = bytes.concat(batchPrompt, prompt);
//     }
//     batchPrompt = bytes.concat(batchPrompt, "]");

//     uint64 gasLimit = getGasLimit(tokenIds.length);
//     uint256 requestId = aiOracle.requestBatchInference{value: msg.value}(
//         size, modelId, bytes(batchPrompt), address(this), gasLimit, "", IAIOracle.DA.Calldata, IAIOracle.DA.Calldata
//     );

//     for (uint256 i = 0; i < size; i++) {
//         uint256 tokenId = tokenIds[i];
//         seedOf[tokenId] = seeds[i];
//         tokenIdToRequestId[tokenId] = requestId;
//     }

//     requests[requestId] = tokenIds;
// }
}
