// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;
import 'https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol';

contract Shop is IERC20 {
    event E(uint256 msg);
    event TokenInfo(string name, string symbol, uint256 decimals, uint256 totalSupply, uint256 ethereumExchangeRate);
    event ContractInfo(address store, address[3] admins, uint256 balance, uint256 pendingBalance);

    string PENDING_REQ = "Pending";
    string ACCEPT_REQ = "Accept";
    string DECLINE_REQ = "Decline";
    string CLIENT_DECLINE_REQ = "User Decline";

    // public data
    address store;                  // owner 0x5B38Da6a701c568545dCfcB03FcB875f56beddC4
    address[3] admins;              // customers EOA
    uint256 balance;                // balance
    uint256 pendingBalance;         // balance from Pending Transactions
    Transaction[] acceptedTransactions;
    Transaction[] declinedTransactions;
    Transaction[] clientDeclinedTransactions;
    WithdrawRequest[] withdrawAccepted;
    WithdrawRequest[] withdrawDeclined;

    // ERC-20 Token properties
    string name = "MyShopToken";
    string symbol = "MST";
    uint256 decimals = 18;
    uint256 totalSupply_ = 1000000000000000000000000; // 1,000,000 + 18 decimals
    uint256 ethereumExchangeRate = 60; // 1 wei = 60 MST
    mapping(address => uint256) balances;
    mapping(address => mapping (address => uint256)) allowed;

    // private
    uint256[] pendingTransaction;
    mapping(address=>address[]) answeredTransactions;
    mapping(address => bool) adminExists;
    mapping(address => uint256) adminIdx;
    mapping(uint256 => Transaction) transactionMap;
    AdminAccountChange public adminAccountChange;
    WithdrawRequest public withdrawRequest;
    uint256 withdrawId = 0;
    uint256 idTransaction = 0;
    // structs
    struct Transaction{
        uint256 productId;
        address from;
        uint256 amount;
        string state;
        bool exists;
    }

    struct AdminAccountChange{
        address currentAccount;
        address newAccount;
        uint accept;
        uint decline;
        address[] answeredAdmins;
        bool exists;
    }

    struct WithdrawRequest{
        bool exists;
        uint256 id;
        address to;
        uint accept;
        uint decline;
        address[] answeredAdmins;
        uint256 amount;
        string state;
    }

    constructor() {
        // initialize the owner and 3 admins
        store = msg.sender;
        admins[0] = 0x5B38Da6a701c568545dCfcB03FcB875f56beddC4;
        adminExists[admins[0]] = true;
        adminIdx[admins[0]] = 0;

        admins[1] = 0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db;
        adminExists[admins[1]] = true;
        adminIdx[admins[1]] = 1;

        admins[2] = 0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2;
        adminExists[admins[2]] = true;
        adminIdx[admins[2]] = 2;

        // On creation of the contract all the tokens go to the owner
        balances[msg.sender] = totalSupply_;
    }
    // ----

    // Modifiers
    modifier withdrawCheck(){
        // check if he is admin
        require(adminExists[msg.sender], "You must be admin to accept this Withdraw");
        // check if the withdraw exists
        require(withdrawRequest.exists, "You dont have any pending withdraw");

        // check if the admin is aswered allready
        address[] memory answered = withdrawRequest.answeredAdmins;
        for(uint i=0; i<answered.length;i++){
            require(answered[i] != msg.sender, "You have aswered allready this Withdraw");
        }
        _;
    }
    modifier onlyStore() {
        // check if he is admin
        require(store == msg.sender, "You must be owner");
        _;
    }
    // ----

    // Withdraw
    function withdraw(uint256 tokenAmount) public returns (uint256 idWithdrawRequest){
        require(tokenAmount <= balance, "The contract does not have the number of tokens you want to withdraw.");

        withdrawId += 1;
        if(adminExists[msg.sender]){
            // if the adming wants to withdraw create request with accept = 1
            address[] memory emptyAddressArray = new address[](1);
            emptyAddressArray[0] = msg.sender;
            withdrawRequest = WithdrawRequest(
                true,
                withdrawId,
                msg.sender,
                1,
                0,
                emptyAddressArray,
                tokenAmount,
                PENDING_REQ
            );
        }else{
            address[] memory emptyAddressArray;
            withdrawRequest = WithdrawRequest(
                    true,
                    withdrawId,
                    msg.sender,
                    0,
                    0,
                    emptyAddressArray,
                    tokenAmount,
                    PENDING_REQ
                );
        }
        return withdrawId;
    }
    function acceptWithdraw() public withdrawCheck returns(string memory){
        // push the adming address
        withdrawRequest.answeredAdmins.push(msg.sender);
        withdrawRequest.accept+=1;

        if(withdrawRequest.accept > 1){
            // make the Withdraw accepted
            withdrawRequest.state = ACCEPT_REQ;
            withdrawAccepted.push(withdrawRequest);
            // move tokents to

            // Transfer the amount
            uint etherAmount = uint(withdrawRequest.amount)/uint(ethereumExchangeRate);
            payable(withdrawRequest.to).transfer(etherAmount);

            balance -= withdrawRequest.amount;
            delete withdrawRequest;
            return "The Withdraw was accepted";
        }

        return "The Transaction still Pending";
    }
    function declineWithdraw() public withdrawCheck returns(string memory){

        // push the withdraw answer
        withdrawRequest.answeredAdmins.push(msg.sender);
        withdrawRequest.decline+=1;

        if(withdrawRequest.decline > 1){
            // make the Transaction declined
            withdrawRequest.state = DECLINE_REQ;
            // add to contract the amount of accepted Transaction
            balance+=withdrawRequest.amount;
            withdrawDeclined.push(withdrawRequest);
            balances[withdrawRequest.to] -= withdrawRequest.amount*ethereumExchangeRate;
            delete withdrawRequest;
            return "The Withdraw was declined";
        }
        return "The Withdraw still Pending";
    }
    // ----

    // return all the Pending Transactios
    function showPendingTransactions() public view returns(Transaction[] memory){
        Transaction[] memory t = new Transaction[](pendingTransaction.length);
        for(uint i=0; i<pendingTransaction.length; i++){
            t[i] = transactionMap[pendingTransaction[i]];
        }
        return (t);
    }
    // Transaction create accept decline
    function createTransaction(uint amountToken) public returns (uint256){
        require(balances[msg.sender]>=amountToken, "You don't have enough tokens for this Transaction");
        // check if the amount is bigger than the product amount

        idTransaction+=1;
        // save the transaction as pending
        pendingBalance += amountToken;
        balances[msg.sender] -= amountToken;

        // save the Transaction
        pendingTransaction.push(idTransaction);
        transactionMap[idTransaction] = Transaction(
            idTransaction,
            msg.sender,
            amountToken,
            PENDING_REQ,
            true
        );
        emit E(amountToken);
        return(idTransaction);
    }
    function acceptTransaction(uint256 id) onlyStore public returns(string memory){
        // check if the transaction exists
        require(transactionMap[id].exists, "This Transaction doenst exist");
        // check if the transaction pending
        require(keccak256(bytes(transactionMap[id].state))==keccak256(bytes(PENDING_REQ)), "This Transaction isn't pending");

        // make the Transaction accepted
        transactionMap[id].state = ACCEPT_REQ;

        // find the index of the address in the pendingTransaction array and delete it
        for(uint i=0; i<pendingTransaction.length;i++){
            if(pendingTransaction[i] == id){
                // delete Pending Transactions
                pendingTransaction = deletePendingTransaction(i);
                // add to contract the amount of accepted Transaction
                balance+=transactionMap[id].amount;
                pendingBalance-=transactionMap[id].amount;
                acceptedTransactions.push(transactionMap[id]);
                delete transactionMap[id];
                break;
            }
        }
        return "The Transaction is accepted";
    }
    function declineYourTransaction(uint256 id) public returns(string memory){
        // check if the transaction exists
        require(transactionMap[id].exists, "You dont have any Transactions");
        // check if the transaction pending
        require(keccak256(bytes(transactionMap[id].state))==keccak256(bytes(PENDING_REQ)), "Your Transaction isn't pending");

        // make the Transaction declined
        transactionMap[id].state = CLIENT_DECLINE_REQ;

        // find the index of the address in the pendingTransaction array and delete it
        for(uint i=0; i<pendingTransaction.length;i++){
            if(pendingTransaction[i] == id){
                pendingTransaction = deletePendingTransaction(i);
                pendingBalance -= transactionMap[id].amount;
                clientDeclinedTransactions.push(transactionMap[id]);
                //return the amount cost of the product
                balances[msg.sender] += transactionMap[id].amount;
                delete transactionMap[id];
                return "Your Transaction declined successfully";
            }
        }

        return "Something Happened";
    }
    function declineTransaction(uint256 id) onlyStore public returns(string memory){
        // check if the transaction exists
        require(transactionMap[id].exists, "This Transaction doenst exist");
        // check if the transaction pending
        require(keccak256(bytes(transactionMap[id].state))==keccak256(bytes(PENDING_REQ)), "This Transaction isn't pending");

        // make the Transaction declined
        transactionMap[id].state = DECLINE_REQ;

        // find the index of the address in the pendingTransaction array and delete it
        for(uint i=0; i<pendingTransaction.length;i++){
            if(pendingTransaction[i] == id){
                pendingTransaction = deletePendingTransaction(i);
                pendingBalance -= transactionMap[id].amount;
                declinedTransactions.push(transactionMap[id]);
                //return the amount cost of the product
                balances[msg.sender] += transactionMap[id].amount;
                delete transactionMap[id];
                break;
            }
        }
        return "The Transaction is declined and the amount of the product is returned to the client";
    }
    // -- -- --

    // -- -- --
    // Admin Account Change
    function changeAdminAccount(address newAddress) public returns(string memory){
        // chech if he is customer
        require(adminExists[msg.sender], "You must be admin to change the account");
        // check if accound change pending
        require(adminAccountChange.exists == false, "Account change is pending for another admin");
        //check if the newAddress is same whith msg.sender
        require(msg.sender != newAddress, "You address is same with the newAddress");
        // check if the new address exists
        require(!adminExists[newAddress], "This account is allready exists");
        address[] memory answeredAdmins;
        adminAccountChange = AdminAccountChange(msg.sender, newAddress, 1, 0, answeredAdmins, true);

        return("Change Account Pending");
    }
    function acceptAccountChange() public returns(string memory){
        // chech if he is customer
        require(adminExists[msg.sender], "You must be admin to change the account");
        // check if accound change pending
        require(adminAccountChange.exists == true, "Account change is not pending for another admin");
        // chech if he is the one who want to change his account
        require(adminAccountChange.currentAccount != msg.sender, "You cannot accept your request for Account Change");
        // check if the admin is aswered allready
        address[] storage answered = adminAccountChange.answeredAdmins;
        for(uint i=0; i<answered.length;i++){
            require(answered[i] != msg.sender, "You have aswered allready this transaction");
        }
        // record admin accept
        answered.push(msg.sender);
        adminAccountChange.answeredAdmins = answered;
        adminAccountChange.accept += 1;
        if(adminAccountChange.accept > 1){
            // change the his address
            admins[adminIdx[adminAccountChange.currentAccount]] = adminAccountChange.newAccount;
            // update exists map
            adminExists[adminAccountChange.newAccount] = true;
            //update idx map
            adminIdx[adminAccountChange.newAccount] = adminIdx[adminAccountChange.currentAccount];
            //delete
            adminIdx[adminAccountChange.currentAccount] = 0;
            adminExists[adminAccountChange.currentAccount] = false;
            delete adminAccountChange;
            return "Account Change accepted";
        }
        return "";
    }
    function declineAccountChange() public returns(string memory){
        // chech if he is customer
        require(adminExists[msg.sender], "You must be admin to change the account");
        // check if accound change pending
        require(adminAccountChange.exists == true, "Account change is not pending for another admin");
        // chech if he is the one who want to change his account
        require(adminAccountChange.currentAccount != msg.sender, "You cannot decline your request for Account Change");
        // check if the admin is aswered allready
        address[] storage answered = adminAccountChange.answeredAdmins;
        for(uint i=0; i<answered.length;i++){
            require(answered[i] != msg.sender, "You have aswered allready this transaction");
        }
        // record admin accept
        answered.push(msg.sender);
        adminAccountChange.answeredAdmins = answered;
        adminAccountChange.decline += 1;
        if(adminAccountChange.decline > 1){
            delete adminAccountChange;
            return "Account Change decline";
        }
        return "";
    }
    // -- -- --
    function destroy() private{
        selfdestruct(payable(store));
    }
    // -- -- --
    // Get value and data from the client
    // called when we have no data
    receive() payable external{
        balances[msg.sender] += msg.value*ethereumExchangeRate;
    }
    // -- -- --
    // Move the last element to the deleted spot.
    // Remove the last element.
    function deletePendingTransaction(uint index) internal returns(uint256[] storage) {
        require(index < pendingTransaction.length);
        pendingTransaction[index] = pendingTransaction[pendingTransaction.length-1];
        pendingTransaction.pop();
        return pendingTransaction;
    }

    /*
        ERC-20 Token methods
    */
    function totalSupply() public override view returns (uint256) {
        return totalSupply_;
    }

    function balanceOf(address tokenOwner) public override view returns (uint256) {
        return balances[tokenOwner];
    }
    function transfer(address receiver, uint256 numTokens) public override returns (bool) {
        require(numTokens <= balances[msg.sender]);
        balances[msg.sender] = balances[msg.sender]-numTokens;
        balances[receiver] = balances[receiver]+numTokens;
        emit Transfer(msg.sender, receiver, numTokens);
        return true;
    }
    function approve(address spender, uint256 numTokens) public override returns (bool) {
        allowed[msg.sender][spender] = numTokens;
        emit Approval(msg.sender, spender, numTokens);
        return true;
    }
    function allowance(address _owner, address spender) public override view returns (uint) {
        return allowed[_owner][spender];
    }
    function transferFrom(address _owner, address buyer, uint256 numTokens) public override returns (bool) {
        require(numTokens <= balances[_owner], "The owner does't have enough tokens.");
        require(numTokens <= allowed[_owner][msg.sender], "You are not allowed to transfer that amount.");

        balances[_owner] = balances[_owner]-numTokens;
        allowed[_owner][msg.sender] = allowed[_owner][msg.sender]-numTokens;
        balances[buyer] = balances[buyer]+numTokens;
        emit Transfer(_owner, buyer, numTokens);
        return true;
    }
    function changeEthereumExchangeRate(uint256 newExchangeRate) public{
        // check if he is an admin
        require(adminExists[msg.sender], "You must be admin to change the account");
        ethereumExchangeRate = newExchangeRate;
    }
    function yourTokensToEth() public returns(uint){
        require(balances[msg.sender]>0, "You dont have any tokens");
        // Transfer the amount to your account
        uint etherAmount = uint(balances[msg.sender])/uint(ethereumExchangeRate);
        payable(msg.sender).transfer(etherAmount);
        delete balances[msg.sender];
        return etherAmount;
    }
    // ----

    // ----
    // rest contract info
    function showAcceptTransactions() public view returns(Transaction[] memory){
        return acceptedTransactions;
    }
    function showDeclineTransactions() public view returns(Transaction[] memory){
        return declinedTransactions;
    }
    function showClientDeclinedTransactions() public view returns(Transaction[] memory){
        return clientDeclinedTransactions;
    }
    function showAcceptedWithdraws() public view returns(WithdrawRequest[] memory){
        return withdrawAccepted;
    }
    function showDeclinedWithdraws() public view returns(WithdrawRequest[] memory){
        return withdrawDeclined;
    }
    function showTokenInfo() public{
        emit TokenInfo(name,symbol,decimals,totalSupply_,ethereumExchangeRate);
    }
    function showContractInfo() public{
        emit ContractInfo(store,admins,balance,pendingBalance);
    }

}
