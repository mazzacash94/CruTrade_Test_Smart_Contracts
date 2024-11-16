// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import './abstracts/Modifiers.sol';
import './interfaces/IPayments.sol';
import './interfaces/IReferrals.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import '@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol';

/**
 * @title Referrals
 * @dev Gestisce un sistema di referral con supporto per influencer
 * 
 * Il contratto permette:
 * - Creazione e assegnazione di codici referral
 * - Tracciamento degli utilizzi dei codici
 * - Gestione dello status influencer
 * - Distribuzione di ricompense tramite il contratto Payments
 *
 * Funzionamento ricompense:
 * - Al primo acquisto di un utente: sia referrer che referral ricevono tokens
 * - Per acquisti successivi: solo il referrer riceve tokens se è influencer
 */
contract Referrals is
    Initializable,
    Modifiers,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    IReferrals
{
    using ECDSA for bytes32;

    // Ruoli per il controllo degli accessi
    bytes32 public constant REFERRING_ROLE = keccak256('REFERRING_ROLE');
    bytes32 public constant PAUSER_ROLE = keccak256('PAUSER_ROLE');

    /**
     * @dev Struttura dati per le informazioni di referral
     * @param code Codice univoco del referral
     * @param referrer Indirizzo del referrer assegnato
     * @param isInfluencer Status influencer (riceve tokens su ogni acquisto dei referral)
     * @param usedCount Numero totale di utilizzi del codice
     * @param used Mapping per tracciare chi ha già usato il codice
     */
    struct Referral {
        bytes32 code;
        address referrer;
        bool isInfluencer;
        uint256 usedCount;
        mapping(address => bool) used;
    }

    // Storage principale
    mapping(address => Referral) private _referralsData;    // Dati referral per indirizzo
    mapping(bytes32 => address) private _referralsCodes;    // Mapping codice -> proprietario



    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Inizializza il contratto
     * @param _roles Indirizzo del contratto dei ruoli
     */
    function initialize(address _roles) public initializer {
        if (_roles == address(0)) revert ZeroAddressProvided();
        __Modifiers_init(_roles);
        __Pausable_init();
        __ReentrancyGuard_init();
    }

    /**
     * @notice Crea un nuovo codice referral e opzionalmente lo collega a un referrer
     * @dev Combina la creazione del codice e il linking al referrer in un'unica operazione
     * @param user Indirizzo che possiederà il codice
     * @param code Codice da assegnare
     * @param referrerCode Codice del referrer (opzionale, può essere bytes32(0))
     */
    function createReferral(
        address user,
        bytes32 code,
        bytes32 referrerCode
    ) external onlyRole(OWNER) whenNotPaused {
        if (user == address(0)) revert ZeroAddressProvided();

        // Verifica che il codice non sia già assegnato
        address currentOwner = _referralsCodes[code];
        if (currentOwner != address(0)) 
            revert CodeAlreadyAssigned(code, currentOwner);

        // Verifica che l'utente non abbia già un codice
        bytes32 existingCode = _referralsData[user].code;
        if (existingCode != bytes32(0)) 
            revert ReferrerAlreadyHasCode(user, existingCode);

        // Assegna il codice
        _referralsCodes[code] = user;
        _referralsData[user].code = code;
        emit ReferralCodeAssigned(user, code);

        // Se fornito, collega al referrer
        if (referrerCode != bytes32(0)) {
            address referrer = _referralsCodes[referrerCode];
            if (referrer == address(0)) revert InvalidReferralCode(referrerCode);
            if (referrer == user) revert SelfReferralNotAllowed(user);

            _referralsData[user].referrer = referrer;
            emit ReferralLinked(user, referrer, referrerCode);
        }
    }

    /**
     * @notice Promuove un referrer allo status di influencer
     * @dev Solo il contratto owner può promuovere influencer
     * @param referrer Indirizzo del referrer da promuovere
     */
    function promoteToInfluencer(
        address referrer
    ) external onlyRole(OWNER) whenNotPaused {
        if (referrer == address(0)) revert ZeroAddressProvided();

        Referral storage referral = _referralsData[referrer];
        if (_referralsCodes[referral.code] != referrer)
            revert UnauthorizedOperation(referrer, referral.code);

        referral.isInfluencer = true;
        emit InfluencerStatusChanged(referrer, true);
    }

    /**
     * @notice Processa l'utilizzo di un referral
     * @dev Gestisce la distribuzione delle ricompense in base alle condizioni:
     * - Primo utilizzo: ricompense a referrer e referral
     * - Usi successivi: ricompense solo se il referrer è influencer
     * @param account Indirizzo dell'utente che usa il referral
     * @param amount Ammontare della ricompensa da distribuire
     */
    function useReferral(
        address account,
        uint256 amount
    ) external onlyDelegatedRole whenNotPaused {
        if (account == address(0)) return;

        Referral storage referral = _referralsData[account];
        address referrer = referral.referrer;
        if (referrer == address(0)) return;

        Referral storage referrerData = _referralsData[referrer];
        bool isFirstUse = !referrerData.used[account];

        // Distribuisce ricompense solo se:
        // 1. È il primo utilizzo (entrambi ricevono)
        // 2. Non è il primo utilizzo ma il referrer è influencer (solo referrer riceve)
        if (isFirstUse || referrerData.isInfluencer) {
            if (isFirstUse) {
                referrerData.used[account] = true;
                referrerData.usedCount++;
            }

            IPayments(roles.getRoleAddress(PAYMENTS)).distributeRewards(
                referrer,                         // indirizzo referrer
                isFirstUse ? account : address(0), // indirizzo referral (solo primo uso)
                amount,                           // ammontare ricompensa
                isFirstUse || referrerData.isInfluencer // se dare ricompensa al referrer
            );

            emit ReferralUsed(account, referrer);
        }
    }

    /**
     * @notice Permette a un referrer di gestire il proprio status influencer
     * @dev Solo il proprietario del codice può modificare il proprio status
     * @param status Nuovo status da impostare
     */
    function setInfluencerStatus(bool status) external whenNotPaused nonReentrant {
        Referral storage referral = _referralsData[msg.sender];
        if (_referralsCodes[referral.code] != msg.sender)
            revert UnauthorizedOperation(msg.sender, referral.code);

        referral.isInfluencer = status;
        emit InfluencerStatusChanged(msg.sender, status);
    }

    /**
     * @notice Recupera le informazioni di referral per un utente
     * @param user Indirizzo dell'utente
     * @return code Codice referral dell'utente
     * @return referrer Indirizzo del suo referrer
     * @return isInfluencer Status influencer
     * @return usedCount Numero di utilizzi del codice
     */
    function getReferralInfo(
        address user
    ) external view returns (
        bytes32 code,
        address referrer,
        bool isInfluencer,
        uint256 usedCount
    ) {
        if (user == address(0)) revert ZeroAddressProvided();

        Referral storage referral = _referralsData[user];
        return (
            referral.code,
            referral.referrer,
            referral.isInfluencer,
            referral.usedCount
        );
    }

    /**
     * @notice Verifica se un codice referral è valido
     * @param code Codice da verificare
     * @return bool True se il codice è valido e assegnato
     */
    function isValidReferralCode(bytes32 code) external view returns (bool) {
        return _referralsCodes[code] != address(0);
    }

    /**
     * @notice Mette in pausa le funzioni del contratto
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Riattiva le funzioni del contratto
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // Gap per future implementazioni
    uint256[50] private __gap;
}