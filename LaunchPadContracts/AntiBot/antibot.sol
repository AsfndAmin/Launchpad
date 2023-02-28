// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IPinkAntiBot.sol";
import "https://github.com/pancakeswap/pancake-smart-contracts/blob/master/projects/exchange-protocol/contracts/interfaces/IPancakeRouter02.sol";
import "https://github.com/pancakeswap/pancake-smart-contracts/blob/master/projects/exchange-protocol/contracts/interfaces/IPancakeFactory.sol";


contract PinkAntiBot {

   // Anti-bot and anti-whale mappings and variables
    mapping(address => mapping(address => uint256)) public _holderLastTransferTimestamp;
    mapping(address => mapping(address => bool)) public _isExcludedMaxTransactionAmount;
    mapping(address => mapping(address => bool)) public automatedMarketMakerPairs;
    mapping(address => mapping(address => bool)) public blocked;


      struct tokenData {
        address owner;
        address routerAddress;
        address pairAddress;
        uint256 maxAmountPerTrade;
        uint256 amountAddedPerBlock;
        uint256 maxWallet;
        uint256 timeLimitPerTrade;
        uint256 launchBlock;
        uint256 deadBlocks;
        bool transferDelayEnabled;
        bool limitsInEffect;
        bool tradingEnabled;
    }

    mapping(address => tokenData) _tokenAntiBotData;

    event BoughtEarly(address indexed sniper);

    constructor(){}

    function setTokenOwner(address _owner) external {
        require(_tokenAntiBotData[msg.sender].owner == address(0), "already set");
        _tokenAntiBotData[msg.sender].owner = _owner;
    }

        function setTradingEnabled(address tokenAddress, address _tokenB, address _v2router, bool status) external {
        require(_tokenAntiBotData[tokenAddress].owner == msg.sender, "caller not owner of token");
        IPancakeRouter02 router = IPancakeRouter02(_v2router);
        address pair = IPancakeFactory(router.factory()).getPair(tokenAddress, _tokenB);
        require(pair != address(0), "no pair created");
            if(IERC20(pair).totalSupply() == 0){
                _tokenAntiBotData[tokenAddress].tradingEnabled = status;
            }else{
                require(status != true, "liquidity already added");
                _tokenAntiBotData[tokenAddress].tradingEnabled = status;
            }
        

    }

    function onPreTransferCheck(
        address from,
        address to,
        uint256 amount
    ) external {
        address tokenAddress = msg.sender;
        if(_tokenAntiBotData[tokenAddress].tradingEnabled){
        require(!blocked[tokenAddress][from], "Sniper blocked");
        _tokenAntiBotData[tokenAddress].maxAmountPerTrade += ((block.number - _tokenAntiBotData[tokenAddress].launchBlock)*_tokenAntiBotData[tokenAddress].amountAddedPerBlock);

        if (_tokenAntiBotData[tokenAddress].limitsInEffect) {
            if (
                from != _tokenAntiBotData[tokenAddress].owner &&
                to != _tokenAntiBotData[tokenAddress].owner &&
                to != address(0) &&
                to != address(0xdead)
                
            ) {


                if (
                    block.number <= _tokenAntiBotData[tokenAddress].launchBlock + _tokenAntiBotData[tokenAddress].deadBlocks &&
                    from == address(_tokenAntiBotData[tokenAddress].pairAddress) &&
                    to != _tokenAntiBotData[tokenAddress].routerAddress &&
                    to != address(this) &&
                    to != address(_tokenAntiBotData[tokenAddress].pairAddress)
                ) {
                    blocked[tokenAddress][to] = true;
                    emit BoughtEarly(to);
                }

                // at launch if the transfer delay is enabled, ensure the block timestamps for purchasers is set -- during launch.
                if (_tokenAntiBotData[tokenAddress].transferDelayEnabled) {
                    if (
                        to != _tokenAntiBotData[tokenAddress].owner &&
                        to != address(_tokenAntiBotData[tokenAddress].routerAddress) &&
                        to != address(_tokenAntiBotData[tokenAddress].pairAddress)
                    ) {
                        require(
                            _holderLastTransferTimestamp[tokenAddress][tx.origin] + _tokenAntiBotData[tokenAddress].timeLimitPerTrade <
                                block.number,
                            "_transfer:: Transfer Delay enabled.  Only one purchase per block allowed."
                        );
                        _holderLastTransferTimestamp[tokenAddress][tx.origin] = block.number;
                    }
                }

                //when buy
                if (
                    automatedMarketMakerPairs[tokenAddress][from] &&
                    !_isExcludedMaxTransactionAmount[tokenAddress][to]
                ) {
                    require(
                        amount <= _tokenAntiBotData[tokenAddress].maxAmountPerTrade,
                        "Buy transfer amount exceeds the maxTransactionAmount."
                    );
                    require(
                        amount + IERC20(tokenAddress).balanceOf(to) <=  _tokenAntiBotData[tokenAddress].maxWallet,
                        "Max wallet exceeded"
                    );
                }
                //when sell
                else if (
                    automatedMarketMakerPairs[tokenAddress][to] &&
                    !_isExcludedMaxTransactionAmount[tokenAddress][from]
                ) {
                    require(
                        amount <= _tokenAntiBotData[tokenAddress].maxAmountPerTrade,
                        "Sell transfer amount exceeds the maxTransactionAmount."
                    );
                } else if (!_isExcludedMaxTransactionAmount[tokenAddress][to]) {
                    require(
                        amount + IERC20(tokenAddress).balanceOf(to) <=  _tokenAntiBotData[tokenAddress].maxWallet,
                        "Max wallet exceeded"
                    );
                }
            
        }
        }
        }   

}

    function setValues(
        address tokenAddress,
        address _tokenB,
        address _v2router,
        uint256 _limitPerTrade,
        uint256 _maxWallet,
        uint256 _deadBlocks,
        uint256 _timeLimitPerTrade,
        uint256 _amountAddedPerBlock )external{
        require(_tokenAntiBotData[tokenAddress].owner == msg.sender, "caller not owner of token");
        IPancakeRouter02 router = IPancakeRouter02(_v2router);
        // Create a PANCAKE pair for this new token 
        if(IPancakeFactory(router.factory()).getPair(tokenAddress, _tokenB) == address(0)){
            address panCakeSwapPair = IPancakeFactory(router.factory()).createPair(tokenAddress, _tokenB);
             _tokenAntiBotData[tokenAddress].pairAddress = panCakeSwapPair;
             automatedMarketMakerPairs[tokenAddress][panCakeSwapPair] = true;
        }else{
            address pairAddress = IPancakeFactory(router.factory()).getPair(tokenAddress, _tokenB);
            automatedMarketMakerPairs[tokenAddress][pairAddress] = true;
            _tokenAntiBotData[tokenAddress].pairAddress = pairAddress;
        }
             _tokenAntiBotData[tokenAddress].routerAddress = _v2router;
             _tokenAntiBotData[tokenAddress].maxAmountPerTrade = _limitPerTrade;
             _tokenAntiBotData[tokenAddress].timeLimitPerTrade = _timeLimitPerTrade;
             _tokenAntiBotData[tokenAddress].amountAddedPerBlock = _amountAddedPerBlock;
             _tokenAntiBotData[tokenAddress].maxWallet =  _maxWallet;
             _tokenAntiBotData[tokenAddress].launchBlock = block.number;
             _tokenAntiBotData[tokenAddress].deadBlocks = _deadBlocks;
             _tokenAntiBotData[tokenAddress].transferDelayEnabled = true;
             _tokenAntiBotData[tokenAddress].limitsInEffect = true;
    }

        function BlocKunBlockUsers(address tokenAddress, address[] memory _users, bool _status) external{
            require(_tokenAntiBotData[tokenAddress].owner == msg.sender, "caller not owner of token");
            for(uint256 i=0; i <_users.length; i++){
            blocked[tokenAddress][_users[i]] = _status;
            }
        }


}