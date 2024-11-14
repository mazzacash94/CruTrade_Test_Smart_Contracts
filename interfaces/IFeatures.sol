pragma solidity 0.8.28;

interface IFeatures {
    function processFeature(uint256 featureId, bytes calldata inputData) external returns (bytes memory);
}