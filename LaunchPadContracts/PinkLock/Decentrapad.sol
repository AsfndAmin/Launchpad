// SPDX-License-Identifier: MIT
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract DecentraLockNFT is ERC721 {
    constructor() ERC721("DecentraLock NFT", "DLN") {}

    function mint(address user, uint256 id) external returns (bool) {
        _mint(user, id);
        return true;
    }
}
