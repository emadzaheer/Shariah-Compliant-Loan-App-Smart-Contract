// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
// import "hardhat/console.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract Qardh is Ownable, Pausable {
    using EnumerableSet for EnumerableSet.UintSet;
    /*----------------------------------------- STORAGE -------------------------------------------*/

    //```````````````   
    uint256 PlatformFee = 0;   //1.5 * 100
    uint256 ZakatPercentage = 0;  // 2.5 * 100 

    //```````````````

    uint256 CryptoBalance;

    EnumerableSet.UintSet ActiveLoans;                                              //? function? needed! in the data migration
    address QardhV2Address;

    enum E_accountType  {none, mosque, user, suspended }                   
    enum E_CurrencyType {none, crypto, fiat, offPlatform} 
    enum E_donationStatus {none, sentByDonor, accepted, rejected}
    enum E_loanStatus   {
                         none,
                         initiatedByBorrower,
                         acceptedByLender, 
                         returnedByBorrower,
                         completedByLender,
                         forgivenByLender,
                         assignedToMosque,
                         completedByAdmin 
                        }
    
    mapping (uint256 => S_userDetail)   public m_userDetails; 
    mapping (address => uint256)        public m_userId;
    mapping (uint256 => S_userActivityDetail)  m_userRecords;

    mapping (uint256 => S_mosqueDetail) public m_mosqueDetails;
    mapping (address => uint256)        public m_mosqueId;

    mapping (uint256 => S_loan)  public m_loans; 
    mapping (uint256 => S_DonationDetail) public m_donations;
    

    struct S_userActivityDetail {
        uint256[] loansLent;
        uint256[] loansBorrowed;
        uint256[] donations;
        EnumerableSet.UintSet currentlyBorrowed;                
        EnumerableSet.UintSet currentlyLent;                      
    }
    
    struct S_userDetail {
        address userAddress;
        E_accountType accountType;
    }

    struct S_mosqueDetail {
        uint256[]acceptedDonations;
        address mosqueAddress;
        E_accountType accountType;
    }

    struct S_loan {
        E_loanStatus loanStatus;
        E_CurrencyType paymentType;
        E_CurrencyType repaymentType;
        bool mosqueDonationAccepted;
        uint256 lenderId;
        uint256 borrowerId;
        uint256 mosqueId;   
        uint256 amount;     
        uint256 mosqueDonationPercentage;     
        uint256 dueDate;         
    }

    struct S_DonationDetail {
        uint256 amount;
        uint256 mosqueId;
        uint256 donorId;       
        E_CurrencyType currencyType;
        E_donationStatus status;
    }
    
    modifier whenNotSuspended(uint256 _userId) {
        if(m_userDetails[_userId].accountType == E_accountType.suspended){
            revert("suspended account");
        }
        _;
    }

    /*----------------------------------------- HELPING FUNCTIONS -------------------------------------------*/
    
    function checkMosqueIdExists(uint256 _mosqueId) private view returns (bool) {
        return m_mosqueDetails[_mosqueId].accountType == E_accountType.mosque; 
    }

    function checkMosqueAddressExists(address _address) private view returns (bool) {
        return m_mosqueId[_address] == 0? false: true;
    }
    
    function checkUserIdExists(uint256 _userId) private view returns (bool) {
        return m_userDetails[_userId].accountType == E_accountType.user 
               ||  m_userDetails[_userId].accountType == E_accountType.suspended
               ; 
    }

    function checkUserAddressExists(address _address) private view returns (bool) {
        
        return m_userId[_address] == 0? false: true;
    }

    function checkUserIsNotSuspended(uint256 _userId) private view {
        if ( m_userDetails[_userId].accountType == E_accountType.suspended)
            revert("user is suspended");
    }

    function checkIdAndAddressMatch(uint256 _id, address _address, E_accountType _accountType) private view returns (bool) {
        if ( _accountType == E_accountType.user || _accountType == E_accountType.suspended ){
            return _id == m_userId[_address];
        }
        if ( _accountType == E_accountType.mosque ){
            return _id == m_mosqueId[_address];
        }
        else 
            return false;
    }

    function checkAddressExists(address _address) private view returns (bool) {
        return checkMosqueAddressExists(_address) || checkUserAddressExists(_address) ? true: false;
    }

    function deleteLoanDetails(uint256 _loanId) private {
        delete m_loans[_loanId];
        ActiveLoans.remove(_loanId);        
    }

    function checkLoanIdExists(uint256 _loanId) private view returns(bool) {
       return m_loans[_loanId].loanStatus == E_loanStatus.none ? false : true; 
    }

    function checkDonationIdExists(uint256 _donationId) private view returns(bool) {
       return m_donations[_donationId].status == E_donationStatus.none ? false : true; 
    }

    function storeLoanDetails(  uint256 _loanId,
                                E_loanStatus _loanStatus, 
                                E_CurrencyType _paymentType,
                                E_CurrencyType _repaymentType,
                                uint256 _lenderId,
                                uint256 _borrowerId,
                                uint256 _mosqueId,
                                uint256 _amount,
                                uint256 _mosqueDonationPercentage,
                                uint256 _dueDate
                            ) private {
        
        m_loans[_loanId] = S_loan(  _loanStatus,
                                    _paymentType,
                                    _repaymentType,
                                    false,
                                    _lenderId,
                                    _borrowerId,
                                    _mosqueId,
                                    _amount,
                                    _mosqueDonationPercentage,
                                    _dueDate
                                );
        ActiveLoans.add(_loanId);
    }


    function addLoanToUserRecords(uint256 _lenderId, uint256 _borrowerId, uint256 _loanId) private  {
        m_userRecords[_lenderId].loansLent.push(_loanId);
        m_userRecords[_lenderId].currentlyLent.add(_loanId);
        m_userRecords[_borrowerId].loansBorrowed.push(_loanId);
        m_userRecords[_borrowerId].currentlyBorrowed.add(_loanId);
    }

    function removeLoanFromUserRecords(uint256 _lenderId, uint256 _borrowerId, uint256 _loanId) private  {
        m_userRecords[_lenderId].currentlyLent.remove(_loanId);
        m_userRecords[_borrowerId].currentlyBorrowed.remove(_loanId);
    }
    
    function calculatePercentage(uint256 _amount, uint256 _percentage) public pure returns(uint256){  //percentage should be 2.5*100
        _amount = (_amount * _percentage)/10000;
        return _amount; 
    }
    /*----------------------------------------- POPULATIONS -------------------------------------------*/
    function updatePlatformfeePercentage(uint256 _newPercentage ) public onlyOwner {
        PlatformFee = _newPercentage;
        emit platformFeeUpdated(_newPercentage);
    }
    event platformFeeUpdated(uint256 _newPercentage);

    function updateZakatPercentage(uint256 _newPercentage ) public onlyOwner {
        ZakatPercentage = _newPercentage;
        emit zakatPercentageUpdated(_newPercentage);
    }
    event zakatPercentageUpdated(uint256 _newPercentage);

    function addMosques(uint256[] memory _mosqueIds, address[] memory _mosqueAddresses) external onlyOwner {
        
        require( _mosqueIds.length == _mosqueAddresses.length, "id to address length missmatch");
        uint256 length = _mosqueIds.length;
        require(length < 11, "max 10 inputs allowed");

        for (uint i; i<length; ++i) {    
            require( !checkMosqueIdExists(_mosqueIds[i]), "mosque exists" );
            require( !checkAddressExists(_mosqueAddresses[i]), "address already registered");

            if (_mosqueAddresses[i] != address(0))
                m_mosqueId[_mosqueAddresses[i]] = _mosqueIds[i];
            uint256[] memory arr;
            m_mosqueDetails[_mosqueIds[i]] = S_mosqueDetail({   mosqueAddress: _mosqueAddresses[i], 
                                                                accountType: E_accountType.mosque,
                                                                acceptedDonations: arr 
                                                            });
        }
        emit addedMosques(_mosqueIds, _mosqueAddresses);
    }
    event addedMosques(uint256[] _mosqueIds, address[] _mosqueAddresses);


    function updateMosqueAddress(uint256 _mosqueId, address _newAddress) external onlyOwner {

        require( checkMosqueIdExists(_mosqueId), "mosque does not exist" );
        require( !checkAddressExists(_newAddress), "new address already registered");
        
        address oldAddress = m_mosqueDetails[_mosqueId].mosqueAddress;
        delete m_mosqueId[oldAddress];
        if (_newAddress != address(0))
            m_mosqueId[_newAddress] = _mosqueId;
        m_mosqueDetails[_mosqueId].mosqueAddress = _newAddress;

        emit updatedMosqueAddress(_mosqueId, oldAddress, _newAddress );
    }
    event updatedMosqueAddress(uint256 _mosqueId, address oldAddress, address _newAddress );


    function addUser( uint256 _userId, address _address ) private  {

        require( !checkUserIdExists(_userId), "user exists" );
        require( !checkAddressExists(_address), "address already registered");

        if (_address != address(0))
            m_userId[_address] = _userId;
        m_userDetails[_userId] = S_userDetail({ userAddress: _address, 
                                                accountType: E_accountType.user
                                            });

        emit addedUser(_userId, _address);
    } 
    event addedUser(uint256 indexed _userId, address _userAddress);


    function updateUserAddress(uint256 _userId, address _newAddress) external onlyOwner{

        require( checkUserIdExists(_userId), "user does not exist" );
        require( !checkAddressExists(_newAddress), "new address already registered");
        
        address oldAddress = m_userDetails[_userId].userAddress;
        delete m_userId[oldAddress];
        if (_newAddress != address(0))   
            m_userId[_newAddress] = _userId;
        
        m_userDetails[_userId].userAddress = _newAddress;

        emit updatedUserAddress(_userId, oldAddress, _newAddress );
    }
    event  updatedUserAddress(uint256 _userId, address  oldAddress, address _newAddress );


    function setQardhV2Address(address _address) external onlyOwner {
        QardhV2Address = _address;
    }

    /*----------------------------------------- LOANS -------------------------------------------*/

    function initiateCryptoLoan(uint256 _loanId, 
                                uint256 _lenderId,
                                uint256 _borrowerId,
                                address _lenderAddress,
                                uint256 _mosqueId,
                                uint256 _amount,
                                uint256 _mosqueDonationPercentage,
                                uint256 _dueDate) external whenNotPaused whenNotSuspended(_borrowerId) {

        require( !checkLoanIdExists(_loanId), "loanId exists");
        require( checkMosqueIdExists(_mosqueId), "invalid mosqueId" );
        require(_dueDate > block.timestamp, "due date invalid");
        
        if ( !checkUserIdExists(_lenderId))
            addUser(_lenderId, _lenderAddress);
        if ( !checkUserIdExists(_borrowerId))
            addUser(_borrowerId, msg.sender);

        require( checkIdAndAddressMatch(_borrowerId, msg.sender, E_accountType.user), "Id and address do not match");
        require( checkIdAndAddressMatch(_lenderId, _lenderAddress, E_accountType.user), "Id and address do not match");

        checkUserIsNotSuspended(_borrowerId); 
        checkUserIsNotSuspended(_lenderId);

        storeLoanDetails(   _loanId, 
                            E_loanStatus.initiatedByBorrower,
                            E_CurrencyType.crypto,
                            E_CurrencyType.crypto,
                            _lenderId,
                            _borrowerId,
                            _mosqueId,
                            _amount,
                            _mosqueDonationPercentage,
                            _dueDate
        );

        emit loanStatusUpdated(_loanId,m_loans[_loanId]);
    }
    event loanStatusUpdated(uint256 indexed _loanId, S_loan _loan);


    function acceptCryptoLoanTerms(uint256 _loanId ) external payable whenNotPaused whenNotSuspended(m_userId[msg.sender]){
        
        require( checkLoanIdExists(_loanId), "loan does not exist");
        S_loan memory loan = m_loans[_loanId];
        require(loan.loanStatus == E_loanStatus.initiatedByBorrower, "invalid loan status");
        require(loan.paymentType == E_CurrencyType.crypto, "wrong payment type");
        require( m_userDetails[loan.lenderId].userAddress == msg.sender, "invalid lender");
        require( msg.value == loan.amount, "insufficient amount" );
        require(loan.dueDate > block.timestamp, "due date has passed");

        m_loans[_loanId].loanStatus = E_loanStatus.acceptedByLender;
        ActiveLoans.add(_loanId);
        addLoanToUserRecords(loan.lenderId, loan.borrowerId, _loanId);

        payable(m_userDetails[loan.borrowerId].userAddress).transfer(msg.value);
        
        emit loanStatusUpdated(_loanId, m_loans[_loanId]);
    }

    function acceptCryptoLoanDonation(uint256 _loanId) external whenNotPaused{
        address mosque = m_mosqueDetails[m_loans[_loanId].mosqueId].mosqueAddress;  
        require(msg.sender == mosque || msg.sender == owner(), "caller should be mosque or admin");

        m_loans[_loanId].mosqueDonationAccepted = true;

        emit loanStatusUpdated(_loanId, m_loans[_loanId]);
    }

    function repayCryptoLoan(uint256 _loanId, uint256 _amount) external payable whenNotPaused {
        
        require( checkLoanIdExists(_loanId), "loan does not exist");
        S_loan memory loan = m_loans[_loanId];
        require(loan.loanStatus == E_loanStatus.acceptedByLender
                || loan.loanStatus == E_loanStatus.assignedToMosque, "invalid loan status");
        require( loan.repaymentType == E_CurrencyType.crypto, "wrong repayment type");
        require( checkIdAndAddressMatch(loan.borrowerId, msg.sender, m_userDetails[loan.borrowerId].accountType), "invalid borrower");
        require( _amount <= loan.amount && _amount != 0, "invalid amount" );

        uint256 platformFee = calculatePercentage(loan.amount, PlatformFee);
        uint256 mosqueZakatAmount = calculatePercentage(loan.amount, ZakatPercentage);
        uint256 mosqueDonation = calculatePercentage(loan.amount, loan.mosqueDonationPercentage);

        require(msg.value == (platformFee + mosqueZakatAmount + mosqueDonation + _amount)
                ,"insufficient amount" );

        if (loan.mosqueDonationAccepted){
            payable(m_mosqueDetails[loan.mosqueId].mosqueAddress).transfer(mosqueDonation);
        }
        else{
            payable(m_userDetails[loan.lenderId].userAddress).transfer(mosqueDonation);
        }

        m_loans[_loanId].amount -= _amount;
        
        if (loan.dueDate < block.timestamp){
            m_userDetails[loan.borrowerId].accountType =  E_accountType.suspended;
        }

        if ( m_loans[_loanId].amount == 0 ){
            deleteLoanDetails(_loanId);
            m_loans[_loanId].loanStatus = E_loanStatus.completedByLender;
            removeLoanFromUserRecords(loan.lenderId, loan.borrowerId, _loanId);
        }

        payable(m_mosqueDetails[loan.mosqueId].mosqueAddress).transfer(mosqueZakatAmount);
        payable(m_userDetails[loan.lenderId].userAddress).transfer(_amount);
    
        emit loanStatusUpdated(_loanId, m_loans[_loanId]);
    }

    function forceCompleteLoan(uint256 _loanId ) external  onlyOwner {
        require( checkLoanIdExists(_loanId), "loan does not exist");

        S_loan memory loan = m_loans[_loanId];
            
        deleteLoanDetails(_loanId);
        m_loans[_loanId].loanStatus = E_loanStatus.completedByAdmin ;
        removeLoanFromUserRecords(loan.lenderId, loan.borrowerId, _loanId);

        emit loanStatusUpdated(_loanId, m_loans[_loanId]);
    }

    function forgiveLoan(uint256 _loanId) external onlyOwner {
        require( checkLoanIdExists(_loanId), "loan does not exist");
        S_loan memory loan = m_loans[_loanId];
        require (loan.loanStatus == E_loanStatus.acceptedByLender
                || loan.loanStatus == E_loanStatus.assignedToMosque , "cannot forgive unaccepted loan");

        deleteLoanDetails(_loanId);
        m_loans[_loanId].loanStatus = E_loanStatus.forgivenByLender ;
        removeLoanFromUserRecords(loan.lenderId, loan.borrowerId, _loanId);

        emit loanStatusUpdated(_loanId,m_loans[_loanId]);
    }

    function giveReliefToLoanBorrower(uint256 _loanId, uint256 _newDueDate) external onlyOwner {
        require( checkLoanIdExists(_loanId), "loan does not exist");
        require (m_loans[_loanId].loanStatus == E_loanStatus.acceptedByLender, "cannot give relief on unaccepted loan");
        require (_newDueDate > m_loans[_loanId].dueDate && _newDueDate > block.timestamp, "invalid new date");

        m_loans[_loanId].dueDate = _newDueDate;

        emit loanStatusUpdated(_loanId,m_loans[_loanId]);
    }

    function assignLoanToMosque(uint256 _loanId, uint256 _mosqueId) external onlyOwner {
        require( checkLoanIdExists(_loanId), "loan does not exist");
        S_loan memory loan = m_loans[_loanId];
        require (loan.loanStatus == E_loanStatus.acceptedByLender, "cannot assign unaccepted loan");

        m_loans[_loanId].loanStatus = E_loanStatus.assignedToMosque;
        m_loans[_loanId].lenderId = _mosqueId;

        emit loanStatusUpdated(_loanId, m_loans[_loanId]);
    }

    function initiateOffChainLoan(  uint256 _loanId, 
                                    E_CurrencyType _paymentType,
                                    E_CurrencyType _repaymentType,
                                    uint256 _lenderId,
                                    uint256 _borrowerId,
                                    uint256 _mosqueId,
                                    uint256 _amount,
                                    uint256 _mosqueDonationPercentage,
                                    uint256 _dueDate) external whenNotPaused onlyOwner whenNotSuspended(_borrowerId) {
    
        require( !checkLoanIdExists(_loanId), "loanId exists");
        require( checkMosqueIdExists(_mosqueId), " invalid mosqueId" );
        require(_dueDate > block.timestamp, "due date invalid");
        require(_paymentType == E_CurrencyType.fiat ||  _paymentType == E_CurrencyType.offPlatform, "invalid payment type" );
        require(_amount > 0, "invalid amount");
        
        if ( !checkUserIdExists(_lenderId))
            addUser(_lenderId, address(0));
        if ( !checkUserIdExists(_borrowerId))
            addUser(_borrowerId, address(0));

        checkUserIsNotSuspended(_borrowerId); 
        checkUserIsNotSuspended(_lenderId);

        storeLoanDetails(   _loanId, 
                            E_loanStatus.initiatedByBorrower,
                            _paymentType,
                            _repaymentType,
                            _lenderId,
                            _borrowerId,
                            _mosqueId,
                            _amount,
                            _mosqueDonationPercentage,
                            _dueDate
        );

        emit loanStatusUpdated(_loanId, m_loans[_loanId]);
    }

    function acceptOffChainLoanTerms(uint256 _loanId ) external whenNotPaused onlyOwner whenNotSuspended(m_loans[_loanId].lenderId){
        
        require( checkLoanIdExists(_loanId), "loan does not exist");
        S_loan memory loan = m_loans[_loanId];
        require(loan.loanStatus == E_loanStatus.initiatedByBorrower, "invalid loan status");
        require(loan.paymentType == E_CurrencyType.fiat ||  loan.paymentType == E_CurrencyType.offPlatform, "invalid payment type" );
        require(loan.dueDate > block.timestamp, "due date has passed");

        m_loans[_loanId].loanStatus = E_loanStatus.acceptedByLender;
        ActiveLoans.add(_loanId);
        addLoanToUserRecords(loan.lenderId, loan.borrowerId, _loanId);

        emit loanStatusUpdated(_loanId, m_loans[_loanId]);
    }


    function repayOffChainLoan(uint256 _loanId) external whenNotPaused onlyOwner {
        
        require( checkLoanIdExists(_loanId), "loan does not exist");
        S_loan memory loan = m_loans[_loanId];
        require(loan.loanStatus == E_loanStatus.acceptedByLender
                || loan.loanStatus == E_loanStatus.assignedToMosque , "invalid loan status");
        require(loan.repaymentType == E_CurrencyType.fiat || loan.repaymentType == E_CurrencyType.offPlatform, "invalid repayment type");
        
        if (loan.dueDate < block.timestamp){
            m_userDetails[loan.borrowerId].accountType =  E_accountType.suspended;
        }
        m_loans[_loanId].loanStatus = E_loanStatus.returnedByBorrower;

        emit loanStatusUpdated(_loanId, m_loans[_loanId]);
    }

    function confirmOffChainLoanRepayment(uint256 _loanId) external whenNotPaused onlyOwner {
        
        require( checkLoanIdExists(_loanId), "loan does not exist");
        S_loan memory loan = m_loans[_loanId];
        require(loan.loanStatus == E_loanStatus.acceptedByLender || loan.loanStatus == E_loanStatus.returnedByBorrower , "invalid loan status");
        require(loan.repaymentType == E_CurrencyType.fiat || loan.repaymentType == E_CurrencyType.offPlatform, "invalid repayment type");
    
        deleteLoanDetails(_loanId);
        m_loans[_loanId].loanStatus = E_loanStatus.completedByLender;
        removeLoanFromUserRecords(loan.lenderId, loan.borrowerId, _loanId);

        emit loanStatusUpdated(_loanId, m_loans[_loanId]);
    }

    /*----------------------------------------- DONATIONS -------------------------------------------*/    

    function donateCryptoToMosque(uint256 _donationId, uint256 _donorId, uint256 _mosqueId ) payable external {
        if ( !checkUserIdExists(_donorId))
            addUser(_donorId, msg.sender);
        
        require( checkMosqueIdExists(_mosqueId), "mosque does not exist");
        require( !checkDonationIdExists(_donationId), "donationId already exists" );
        require(msg.value > 0, "no funds provided");
        checkUserIsNotSuspended(_donorId);

        require( checkMosqueAddressExists(m_mosqueDetails[_mosqueId].mosqueAddress ), "Mosque does not have a wallet address" );
        m_donations[_donationId] = S_DonationDetail({   amount: msg.value,
                                                        mosqueId: _mosqueId,
                                                        donorId: _donorId,     
                                                        currencyType: E_CurrencyType.crypto,
                                                        status: E_donationStatus.sentByDonor                                                
                                                    });
        CryptoBalance += msg.value;

        emit donationStatusUpdated(_donationId, m_donations[_donationId]);
    }
    event donationStatusUpdated(uint256 _donationId, S_DonationDetail _donationDetail);

    function acceptCryptoDonation (uint256 _donationId ) external {   
        S_DonationDetail memory donation = m_donations[_donationId];
        require(donation.status == E_donationStatus.sentByDonor, "cannot accept" );
        require( m_mosqueDetails[donation.mosqueId].mosqueAddress == msg.sender, "caller is not the mosque" );

        m_userRecords[donation.donorId].donations.push(_donationId);
        m_mosqueDetails[donation.mosqueId].acceptedDonations.push(_donationId);
        m_donations[_donationId].status =  E_donationStatus.accepted;

        payable (msg.sender).transfer(donation.amount);

        emit donationStatusUpdated(_donationId, m_donations[_donationId]); 
    }

    function rejectCryptoDonation (uint256 _donationId ) external {   
        S_DonationDetail memory donation = m_donations[_donationId];
        require(donation.status == E_donationStatus.sentByDonor, "cannot reject" );
        require( m_mosqueDetails[donation.mosqueId].mosqueAddress == msg.sender, "caller is not the mosque" );

        m_donations[_donationId].status =  E_donationStatus.rejected;

        payable(m_userDetails[donation.donorId].userAddress).transfer(donation.amount);

        emit donationStatusUpdated(_donationId, m_donations[_donationId]);
    }

    /*----------------------------------------- view functions -------------------------------------------*/

    function getUserLoansLent(uint256 userId) external view returns (uint256[] memory) {
        return m_userRecords[userId].loansLent;
    }

    function getUserLoansBorrowed(uint256 userId) external view returns (uint256[] memory) {
        return m_userRecords[userId].loansBorrowed;
    }

    function getUserDonations(uint256 userId) external view returns (uint256[] memory) {
        return m_userRecords[userId].donations;
    }

    function getUserCurrentlyBorrowed(uint256 userId) external view returns (uint256[] memory) {
        return m_userRecords[userId].currentlyBorrowed.values();
    }

    function getUserCurrentlyLent(uint256 userId) external view returns (uint256[] memory) {
        return m_userRecords[userId].currentlyLent.values();
    }

}
