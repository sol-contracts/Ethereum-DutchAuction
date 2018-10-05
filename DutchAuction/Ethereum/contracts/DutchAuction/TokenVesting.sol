pragma solidity 0.4.24;

import '../Libraries/SafeMath.sol';
import '../Libraries/Ownable.sol';

/// Stripped down ERC20 standard token interface.
contract Token {
	function transfer(address _to, uint256 _value) public returns (bool success);
	function approveAndCall(address _spender, uint _amount, bytes _data) public returns (bool success);
}

contract ApproveAndCallFallBack {
  function receiveApproval(address from, uint tokens, address token, bytes data) public;
}

contract TokenVesting is Ownable {
    using SafeMath for *;

    mapping (address => Account) public users;

    address public tokenAddress;

    Token public tokenContract;

		uint256 public monthEpoch = 2629743;

    struct Account {
      uint256 start;
      uint256 duration;
			uint256 cliffReleasePercentage;
			uint256 cliffReleaseAmount;
      uint256 paymentPerMonth;
      uint256 unreleased;
      uint256 released;
      uint256 total;
			uint256 monthCount;
      bool cliffReleased;
    }

    // Validate that this is the true token contract
    constructor(address _tokenWOM)
    public
    notEmptyAddress(_tokenWOM)
    {
      tokenAddress = _tokenWOM;
      tokenContract = Token(_tokenWOM);
    }

    /*
       * @param _start the time (as Unix time) at which point vesting starts
       * @param _duration duration in seconds of the period in which the tokens will vest
       * @para whether the vesting is revocable or not
       */
    function registerPresaleVest(
      address _who,
      uint256 _start,
      uint256 _duration,
			uint256 _cliffReleasePercentage
      )
      public
      only_owner
      notEmptyUint(_start)
      notEmptyUint(_duration)
			notEmptyUint(_cliffReleasePercentage)
      notEmptyAddress(_who)
      notRegistered(_who)
    returns (bool)
    {
      users[_who].start = _start;
      users[_who].duration = _duration;
			users[_who].cliffReleasePercentage = _cliffReleasePercentage;
      emit Registration(_who, _start, _duration);
      return true;
    }

		function returnsCliffReleaseAmount(address _user, uint256 _amount) public view returns(uint256){
			return	_amount * users[_user].cliffReleasePercentage / 100;
		}

		function returnPaymentPerMonth(address _user, uint256 _amount, uint256 _duration, uint256 _epoch) public view returns(uint256){
			return _amount.sub(returnsCliffReleaseAmount(_user, _amount)).div(_duration.div(_epoch));
		}

    function receiveApproval(address from, uint tokens, address token, bytes data)
    public {
      require(data.length == 20);
      require(msg.sender == tokenAddress);
      address _address = bytesToAddress(data);
      uint256 duration = users[_address].duration;
			uint256 cliffReleaseAmount = tokens * users[_address].cliffReleasePercentage / 100;
      uint256 _paymentPerMonth = tokens.sub(cliffReleaseAmount).div(duration.div(monthEpoch));

      users[_address].cliffReleaseAmount = cliffReleaseAmount;
			users[_address].paymentPerMonth = _paymentPerMonth;
      users[_address].unreleased = tokens;
      users[_address].total = tokens;
      emit TokensRecieved(_address, tokens, now);
    }

    // TODO; ensure value is less than given amount
    function release()
    isRegistered(msg.sender)
    public
    payable
    returns (uint256) {
      uint256 currentBalance = users[msg.sender].unreleased;
      uint256 start = users[msg.sender].start;
      uint256 duration = users[msg.sender].duration;
      uint256 paymentPerMonth = users[msg.sender].paymentPerMonth;
      uint256 monthCount = users[msg.sender].monthCount;

      if (now < start) {
        return 0;
      }
      else if (now >= start.add(duration)) {
        users[msg.sender].released += currentBalance;
				users[msg.sender].unreleased = 0;
        tokenContract.transfer(msg.sender, currentBalance);
        delete users[msg.sender];
        return currentBalance;
      }
      else if(now >= start){

        if(users[msg.sender].cliffReleased){

          if(now >= start.add(monthCount.mul(monthEpoch))) {
            users[msg.sender].released += paymentPerMonth;
						users[msg.sender].unreleased -= paymentPerMonth;
            users[msg.sender].monthCount += 1;
            tokenContract.transfer(msg.sender, paymentPerMonth);
            return users[msg.sender].paymentPerMonth;
          }
        }
        else{
          users[msg.sender].released += users[msg.sender].cliffReleaseAmount;
					users[msg.sender].unreleased -= users[msg.sender].cliffReleaseAmount;
          users[msg.sender].cliffReleased = true;
					users[msg.sender].monthCount = 1;
          tokenContract.transfer(msg.sender, users[msg.sender].cliffReleaseAmount);
          delete users[msg.sender].cliffReleaseAmount;
          return 0; // Return % of the cliff
        }
      }
    }

    function bytesToAddress(bytes bys)
    private
    pure
    returns (address addr) {
      assembly {
        addr := mload(add(bys,20))
        }
    }

    modifier isRegistered(address _who) { require (users[_who].start != 0); _; }
    modifier notRegistered(address _who) { require (users[_who].start == 0); _; }
    modifier notEmptyAddress(address _who) { require (_who != address(0)); _; }
    modifier notEmptyUint(uint _uint) { require (_uint != 0); _; }
    modifier notEmptyBytes(bytes _data) { require(_data.length != 0); _; }

    event Registration(address indexed who, uint indexed cliff, uint indexed duration);
    event TokensRecieved(address indexed who, uint indexed amount, uint indexed timestamp);
    event Released(uint256 amount);
    event Revoked();
}
