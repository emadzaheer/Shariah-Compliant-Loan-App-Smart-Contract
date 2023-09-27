// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
// import "hardhat/console.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract Qardh is Ownable, Pausable {
    using EnumerableSet for EnumerableSet.UintSet;

    /*----------------------------------------- STORAGE -------------------------------------------*/
    
    uint256 CryptoBalance;

    EnumerableSet.UintSet ActiveLoans;                                              //? function? needed! in the data migration

    enum E_accountType  {none, mosque, user, suspended }                   
    enum E_CurrencyType {none, crypto, fiat, offPlatform} 
    enum E_donationStatus {none,sentByDonor,accepted,rejected}
    enum E_loanStatus   {
                         none,
                         initiatedByBorrower,
                         acceptedByLender, 
                         returnedByBorrower,
                         completedByLender 
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
        // uint256 balance;
        address mosqueAddress;
        E_accountType accountType;
    }

    struct S_loan {
        E_loanStatus loanStatus;
        E_CurrencyType paymentType;
        E_CurrencyType repaymentType;
        uint256 lenderId;
        uint256 borrowerId;
        address mosqueId;
        // address lender;
        // address borrower;
        uint256 amount;
        uint256 donationToMosque;
        uint256 dueDate;         
    }

    // struct S_installment{
    //     E_installmentStatus lenderStatus;
    //     E_installmentStatus mosqueStatus;
    //     uint256 lenderAmount;
    //     uint256 mosqueAmount;
    //     uint256 dueDate;
    //     string paymentProof;
    // }

    struct S_DonationDetail {
        uint256 amount;
        uint256 mosqueId;
        uint256 donorId;       
        E_CurrencyType currencyType;
        E_donationStatus status;
    }
    
    /*----------------------------------------- HELPING FUNCTIONS -------------------------------------------*/
    
    function checkMosqueIdExists(uint256 _mosqueId) private view returns (bool) {
        return m_mosqueDetails[_mosqueId].accountType == E_accountType.mosque ? true : false; 
    }

    function checkMosqueAddressExists(address _address) private view returns (bool) {
        return m_mosqueId[_address] == 0? false: true;
    }
    
    function checkUserIdExists(uint256 _userId) private view returns (bool) {
        return m_userDetails[_userId].accountType == E_accountType.user 
               // ||  m_userDetails[_userId].accountType == E_accountType.suspended
               ? false : true; 
    }

    function checkUserAddressExists(address _address) private view returns (bool) {
        return m_userId[_address] == 0? false: true;
    }

    function checkAddressExists(address _address) private view returns (bool) {
        return checkMosqueAddressExists(_address) || checkUserAddressExists(_address) ? true: false;
    }

    // function deleteLoanDetails(uint256 _loanId) private {
    //     delete m_loans[_loanId];        
    // }

    // function checkLoanExists(uint256 _loanId) private view returns(bool) {
    //    return m_loans[_loanId].loanStatus == E_loanStatus.none ? false : true; 
    // }

    // function checkAccountExists( uint256 _accountId ) private view returns (bool) {
    //     require (_accountId != 0, "userId can't be 0");
    //     return m_userDetails[_accountId].accountType == E_accountType.none ? false : true; 
    // }

    // function checkIdMapsToAddress(uint256 _userId, address _address) private view returns(bool){
    //     uint256 id = m_userId[_address]; 
    //     return _userId == id? true : false;     
    // }

     
    
    // function modifierLogicForLoans(uint256 _userId) private view {
    //     if (m_userDetails[_userId].userAddress == address(0))
    //         require (msg.sender == owner(), "caller should be admin only"); 
    //     else
    //         require(msg.sender == m_userDetails[_userId].userAddress, "caller is not the borrower" );
    // }

    // function calculatePercentage(uint256 _amount, uint256 _percentageX100) public pure returns(uint256){  //percentage should be 2.5*100
    //     uint256 result = (_amount * _percentageX100)/10000;
    //     require (result > 0 ,  "percentage result can't be 0");
    //     return result;   
    // }

    // function checkIfsuspended(uint256 _userId) private view returns(bool){
    //     return m_userDetails[_userId].accountType == E_accountType.suspended? true: false;
    // }

    // function addLoanToUserRecords(uint256 _lenderId, uint256 _borrowerId, uint256 _loanId) private  {
    //     m_userRecords[_lenderId].loansLent.push(_loanId);
    //     m_userRecords[_lenderId].currentlyLent.add(_loanId);
    //     m_userRecords[_borrowerId].loansBorrowed.push(_loanId);
    //     m_userRecords[_borrowerId].currentlyBorrowed.add(_loanId);
    // }
    
    /*----------------------------------------- POPULATIONS -------------------------------------------*/
    
    function addMosques(uint256[] memory _mosqueIds, address[] memory _mosqueAddresses) external onlyOwner {
        
        require( _mosqueIds.length == _mosqueAddresses.length, "id to address length missmatch");
        uint256 length = _mosqueIds.length;
        require(length < 11, "max 10 inputs allowed");

        for (uint i; i<length; ++i) {    
            require( !checkMosqueIdExists(_mosqueIds[i]), "mosque exists" );
            require( !checkAddressExists(_mosqueAddresses[i]), "address already registered");

            m_mosqueId[_mosqueAddresses[i]] = _mosqueIds[i];
            m_mosqueDetails[_mosqueIds[i]] = S_mosqueDetail({   mosqueAddress: _mosqueAddresses[i], 
                                                                accountType: E_accountType.mosque
                                                            });
        }
        //event
    }

    function updateMosqueAddress(uint256 _mosqueId, address _newAddress) external onlyOwner {

        require( checkMosqueIdExists(_mosqueId), "mosque exists" );
        require( !checkAddressExists(_newAddress), "new address already registered");
        
        address oldAddress = m_mosqueDetails[_mosqueId].mosqueAddress;
        delete m_mosqueId[oldAddress];
        m_mosqueId[_newAddress] = _mosqueId;
        m_mosqueDetails[_mosqueId].mosqueAddress = _newAddress;

        //event
    }

    function addUser( uint256 _userId, address _address ) private onlyOwner {

        require( !checkUserIdExists(_userId), "user exists" );
        require( !checkAddressExists(_address), "address already registered");

        m_userId[_address] = _userId;
        m_userDetails[_userId] = S_userDetail({ userAddress: _address, 
                                                accountType: E_accountType.user
                                            });

        //event
    } 

    function updateUserAddress(uint256 _userId, address _newAddress) external onlyOwner {

        require( checkUserIdExists(_userId), "user exists" );
        require( !checkAddressExists(_newAddress), "new address already registered");
        
        address oldAddress = m_userDetails[_userId].userAddress;
        delete m_userId[oldAddress];
        m_userId[_newAddress] = _userId;
        m_userDetails[_userId].userAddress = _newAddress;

        //event
    }







}
