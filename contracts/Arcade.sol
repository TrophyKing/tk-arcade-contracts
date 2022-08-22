// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 < 0.9.0;

import "./access/AccessControl.sol";
import "./token/ERC20/ERC20.sol";
import "./utils/math/SafeMath.sol";

contract Arcade is AccessControl {
    using SafeMath for uint256;
    
    event CloseGame(uint256 id);
    event CreateGame(uint256 id);
    event DeleteGame(uint256 id);
    event Fee(uint256 fee);
    event OpenGame(uint256 id);
    event Payout(uint256 payout);
    event PlacePlayer(address player, uint256 id, bool status);
    event Refund(uint256 id, address player, uint256 amount);
    event Register(address indexed _player, uint256 id);
    event RemovePlayer(address player);

    bytes32 public constant ARCADE_MANAGER = keccak256("ARCADE_MANAGER");
    bytes32 public constant GAME_MASTER = keccak256("GAME_MASTER");

    struct GameInfo {
        bool    exchange;
        uint256 player_count;
        uint256 player_limit;
        uint256 registration_fee;
        uint256 status;
        address arcade_token;
        uint256 total_fee;
        mapping(address => uint256) fee;
        mapping(address => uint256) paid;
        mapping(address => uint256) seats;
    }

    struct ArcadeToken {
        IERC20  native_token;
        bool    active;
        uint256 redemption_rate;
    }

    mapping(address => ArcadeToken) public acceptedArcadeTokens;

    mapping(uint256 => GameInfo) public gameData;

    uint256 public decimals = 18;

    uint256 public fee_percentage;

    uint256 private base = 10**(uint256(decimals));

    address public owner;

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(ARCADE_MANAGER, _msgSender());
        _grantRole(GAME_MASTER, _msgSender());

        owner = _msgSender();

        fee_percentage = 1e17;
    }

    /**
     * @dev Returns {ArcadeToken} struct for `token_address`.
     */
    function arcadeToken(address token_address) public view returns (bool, uint256) {
        return (acceptedArcadeTokens[token_address].active, acceptedArcadeTokens[token_address].redemption_rate);
    }

    /**
     * @dev Returns {active} as boolean value for `token_address`.
     */
    function isAccepted(address token_address) public view returns (bool) {
        return acceptedArcadeTokens[token_address].active;
    }
    

    /**
     * @dev Validates game configuration for caller. Transfers {#}.registration_fee
     * to arcade contract.
     *
     * Requirements:
     *
     * - Valid game configuration
     */
    function register(uint256 game_id) public {
        require(gameData[game_id].seats[msg.sender] == 1, "Trophy King Arcade: Unauthorized.");
        require(gameData[game_id].status == 1, "Trophy King Arcade: Game closed.");
        require(gameData[game_id].player_limit > gameData[game_id].player_count, "Trophy King Arcade: Game full.  Try again.");
        require(gameData[game_id].paid[msg.sender] == 0, "Trophy King Arcade: Already registered.");
        require(gameData[game_id].player_limit > 0, "Trophy King Arcade: Game not found.");
        require(acceptedArcadeTokens[(gameData[game_id].arcade_token)].native_token.transferFrom(_msgSender(), address(this), gameData[game_id].registration_fee), "Trophy King Arcade: Must approve registration fee.");

        _register(game_id, msg.sender, gameData[game_id].registration_fee);
    }


    /**
     * @dev Transfer balance of `arcade_token` to caller.
     *
     * Requirements:
     *
     * - the caller must have admin role.
     */
    function reconcile(address arcade_token) public onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 balance = acceptedArcadeTokens[arcade_token].native_token.balanceOf(address(this));

        if (balance > 0) {
            require(acceptedArcadeTokens[(arcade_token)].native_token.transfer(_msgSender(), balance), "Trophy King Arcade: Reconciliation failed.");
        }
    }

    /**
     * @dev Set fee percentage for arcade contract.
     *
     * Requirements:
     *
     * - the caller must have arcade manager role.     
     */
    function setArcadeFeePercentage(uint256 percentage) public onlyRole(ARCADE_MANAGER) {
        fee_percentage = percentage;
    }

    /**
     * @dev Adds token to {acceptedArcadeTokens} Require `token_address` for proxy balance exchange.  
     * `redemption_rate` is set and determines the rate that proxy balance is exchanged.  
     * Set `active` to reflect status of exchange.
     *
     * Requirements:
     *
     * - the caller must have arcade manager role.
     */
    function addArcadeToken(address token_address, uint256 redemption_rate, bool _active) public onlyRole(ARCADE_MANAGER) {
        acceptedArcadeTokens[token_address].redemption_rate = redemption_rate;
        acceptedArcadeTokens[token_address].active = _active;

        address payable_token_address = payable(token_address);

        acceptedArcadeTokens[token_address].native_token = IERC20(payable_token_address);
        acceptedArcadeTokens[token_address].native_token.approve(_msgSender(), 115792089237316195423570985008687907853269984665640564039457584007913129639935);
    }

    /**
     * @dev Disable token for proxy balance exchange.
     *
     * Requirements:
     *
     * - the caller must have arcade manager role.
     */
    function removeArcadeToken(address token_address) public onlyRole(ARCADE_MANAGER) {
        acceptedArcadeTokens[token_address].active = false;
    }

    /**
     * @dev Changes {#}.status for `game_id`.
     *
     * Requirements:
     *
     * - the caller must have game master role.
     */
    function closeGame(uint256 game_id) public onlyRole(GAME_MASTER) {
        gameData[game_id].status = 0;

        emit CloseGame(game_id);
    }

    /**
     * @dev Mutates {gameData} structure with game configuration.
     * Sets {#} for `game_id`, `registration_fee`, `arcade_token`, `player_limit`, `exchange` 
     *
     * Requirements:
     *
     * - the caller must have game master role.
     */
    function createGame(uint256 game_id, uint256 registration_fee, address arcade_token, uint256 player_limit, bool exchange) public onlyRole(GAME_MASTER) {
        gameData[game_id].status = 1;
        gameData[game_id].total_fee = 0;
        gameData[game_id].registration_fee = registration_fee;
        gameData[game_id].arcade_token = arcade_token;
        gameData[game_id].player_count = 0;
        gameData[game_id].player_limit = player_limit;
        gameData[game_id].exchange = exchange;

        emit CreateGame(game_id);
    }

    /**
     * @dev Deletes {#} for {gameData} for `game_id`.
     *
     * Requirements:
     *
     * - the caller must have game master role.
     */
    function deleteGame(uint256 game_id) public onlyRole(GAME_MASTER) {
        delete gameData[game_id];

        emit DeleteGame(game_id);
    }

    /**
     * @dev Updates {gameData} sets {#}.seats[`player`] to 0.
     */
    function leaveMatch(uint256 game_id) public {
        gameData[game_id].seats[_msgSender()] = 0;

        emit RemovePlayer(_msgSender());
    }

    /**
     * @dev Changes {#}.status for `game_id`.
     *
     * Requirements:
     *
     * - the caller must have game master role.
     */
    function openGame(uint256 game_id) public onlyRole(GAME_MASTER) {
        gameData[game_id].status = 1;

        emit OpenGame(game_id);
    }

    /**
     * @dev Gives `player` access to register for `game_id`.
     *
     * Requirements:
     *
     * - the caller must have game master role.
     */
    function placePlayer(uint256 game_id, address player) public onlyRole(GAME_MASTER) returns (bool) {
        if (gameData[game_id].seats[player] != 1) {
            gameData[game_id].seats[player] = 1;
            
            emit PlacePlayer(player, game_id, true);

            return true;
        } else {
            emit PlacePlayer(player, game_id, false);

            return false;
        }
    }

    /**
     * @dev Returns {#}.registration_fee for `player` at `game_id`.
     *
     * Requirements:
     *
     * - the caller must have game master role.
     * - `player` must be registered.
     * - contract balance should exceed {#}.registration_fee
     */
    function refund(uint256 game_id, address player) public onlyRole(GAME_MASTER) {
        if (gameData[game_id].exchange == false) {
            require(gameData[game_id].paid[player] == 1, "Trophy King Arcade: Not registered for this game.");

            GameInfo storage gi = gameData[game_id];

            require(acceptedArcadeTokens[(gi.arcade_token)].native_token.transfer(player, gi.registration_fee), "Trophy King Arcade: Refund failed.");

            gi.total_fee -= (gi.registration_fee);

            gi.fee[player] = 0;
            gi.paid[player] = 0;
            gi.player_count -= 1;

            emit Refund(game_id, player, gi.registration_fee);
        }
    }

    /**
     * @dev Updates {gameData} sets {#}.seats[`player`] to 0.
     *
     * Requirements:
     *
     * - the caller must have game master role.
     */
    function removePlayer(uint256 game_id, address player) public onlyRole(GAME_MASTER) {
        gameData[game_id].seats[player] = 0;

        emit RemovePlayer(player);
    }

    /**
     * @dev Updates {gameData} defines `winner` as address to receive {#}.total_fee less arcade_fee.
     *
     * Requirements:
     *
     * - the caller must have game master role.
     */
    function setWinner(uint256 game_id, address winner) public onlyRole(GAME_MASTER) {
        if (gameData[game_id].exchange == false) {
            require(gameData[game_id].paid[winner] == 1, "Trophy King Arcade: Not registered for this game");

            uint256 arcade_fee = (gameData[game_id].total_fee * (acceptedArcadeTokens[(gameData[game_id].arcade_token)].redemption_rate + fee_percentage)) / base / base;
            uint256 payout = gameData[game_id].total_fee.sub(arcade_fee);
            uint256 contract_balance = acceptedArcadeTokens[(gameData[game_id].arcade_token)].native_token.balanceOf(address(this));

            if (contract_balance < payout) {
                payout = contract_balance;
            }

            require(acceptedArcadeTokens[(gameData[game_id].arcade_token)].native_token.transfer(winner, payout), "Trophy King Arcade: Payout failed.");

            emit Fee(gameData[game_id].fee[winner]);

            emit Payout(payout);
        }

        closeGame(game_id);
    }

    /**
     * @dev Updates {gameData} [internal].
     */
    function _register(uint256 game_id, address player_address, uint256 amount) internal {
        GameInfo storage gi = gameData[game_id];

        gi.player_count += 1;
        gi.fee[player_address] = amount;
        gi.paid[player_address] = 1;
        gi.total_fee += amount;
        
        emit Register(msg.sender, game_id);
    }
}
