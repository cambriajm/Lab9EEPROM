//Cambria Morgan
//RCET3373
//First Program
//git
//-Wl,-presetVect=0000h,-pisrVect=0004h,-pcode=0008h
    
; PIC16F883 Configuration Bit Settings
 CONFIG FOSC = XT
 CONFIG WDTE = OFF
 CONFIG PWRTE = OFF
 CONFIG MCLRE = ON
 CONFIG CP = OFF
 CONFIG CPD = OFF
 CONFIG BOREN = OFF
 CONFIG IESO = OFF
 CONFIG FCMEN = OFF
 CONFIG LVP = OFF
 CONFIG BOR4V = BOR40V
 CONFIG WRT = OFF

#include <xc.inc>

; RAM registers (Bank 0) ------------------------------------------------------
 pin_digit1     EQU 0x20 ; First entered PIN digit
    pin_digit2     EQU 0x21 ; Second entered PIN digit
    pin_digit3     EQU 0x22 ; Third entered PIN digit
    pin_digit4     EQU 0x23 ; Fourth entered PIN digit
    Count5ms	   EQU 0x24 ; Outer debounce delay counter
    Count50us      EQU 0x25 ; Inner debounce delay counter

    ; Reusable EEPROM registers (only these 3 GPRs used by EEPROM routines)
    ee_address     EQU 0x26  ; EEPROM address
    ee_data        EQU 0x27  ; Byte to read or write
    ee_status      EQU 0x28  ; EEPROM status bits
    
    ; Additional application registers
    digit_count    EQU 0x29 ; Number of PIN digits entered
    key_held       EQU 0x2A ; Bit 0 = key has been pressed
    key_code       EQU 0x2B ; Scanned key (0-15, FF = none)
    candidate_key  EQU 0x2C ; Key saved during debounce
    keyLow         EQU 0x2D ; Key status bits for keys 1,2,3,A,4,5,6,B
    mode	   EQU 0x2E ; Current lock service mod
    keyHigh        EQU 0x2F ; Key status bits for keys 7,8,9,C,*,0,#,D
    pulse_count    EQU 0x30 ; Timer0 overflow counter
    pin_index      EQU 0x31 ; PIN comparison counter
      
    ; Two copies of the proposed PIN, kept in RAM only
    new_pin1       EQU 0x32
    new_pin2       EQU 0x33
    new_pin3       EQU 0x34
    new_pin4       EQU 0x35
    confirm_pin1   EQU 0x36
    confirm_pin2   EQU 0x37
    confirm_pin3   EQU 0x38
    confirm_pin4   EQU 0x39
    pin_match      EQU 0x3A ; 1 = PIN matched, 0 = not matched
    pin_update     EQU 0x3B ; Bit 0 = EEPROM update in progress
    temp_digit     EQU 0x3C ; Temporary byte for RAM comparisons

    ; Constant (a number, NOT a register)
    TIMEOUT_OVERFLOWS EQU 15 ; 15 x 65.536 ms = about 1 second
    PIN_EE_START   EQU 0x00
    PIN_LENGTH     EQU 0x04
    PIN_MARKER_ADDR EQU 0x04  ; Fifth EEPROM address
    VALID_MARKER   EQU 0xC4  ; Only this value means PIN is valid
   
   ; Part 4 service modes
    MODE_INVALID_NEW      EQU 0x00
    MODE_INVALID_CONFIRM  EQU 0x01
    MODE_LOCKED           EQU 0x02
    MODE_ARMED            EQU 0x03 ; C was pressed; wait for #
    MODE_CHANGE_AUTH      EQU 0x04
    MODE_CHANGE_NEW       EQU 0x05
    MODE_CHANGE_CONFIRM   EQU 0x06

    ; EEPROM status bit positions
    EEPROM_READ    EQU 0
    EEPROM_WRITE   EQU 1
    EEPROM_ERROR   EQU 2
    GIE_SAVED      EQU 3     ; Temporarily save GIE during unlock
      
; Special keypad codes
    NO_KEY         EQU 0xFF
    STAR_KEY       EQU 0x0A
    HASH_KEY       EQU 0x0B
 
; Reset Vector at 0000h. Execution starts here after reset.
PSECT resetVect,class=CODE,delta=2
ResetVector:
    goto Setup

; Interrupt Vector
PSECT isrVect,class=CODE,delta=2

; Main code section starts at 0008h. User code goes here.
PSECT code,class=CODE,delta=2

;------------------------------------------------------------------------------
; SETUP: runs once after reset. Puts every output in a safe OFF state, sets up
; the pins, Timer0 (solenoid time), Timer1 (beep time), clears all RAM
; variables, then checks the EEPROM marker to pick the starting mode.
;------------------------------------------------------------------------------
Setup:
    ; Bank 0: Outputs OFF before the pins become outputs
    BANKSEL PORTA
    CLRF PORTA      ; Solenoid and buzzer OFF
    CLRF PORTB      ; Keep keypad rows LOW
    MOVLW 0x80
    MOVWF PORTC     ; Display Write HIGH
 
    ; Bank 3
    BANKSEL ANSEL
    CLRF ANSEL      ; Disable analog inputs
    CLRF ANSELH
    BCF EECON1,7    ; Select data EEPROM
    BCF EECON1,2    ; Disable EEPROM writing
 
    ; Bank 1
    BANKSEL TRISA
    BCF TRISA,0     ; RA0 simulated solenoid output
    BCF TRISA,1     ; RA1 buzzer output
    BCF TRISA,2     ; RA2 EEPROM error LED output
    BCF TRISA,3     ; FIX: RA3 scope marker output (was left as an input, so it never moved)
    MOVLW 0xFF
    MOVWF TRISB     ; RB0-RB7 start as inputs
    CLRF TRISC      ; Display outputs
    MOVLW 0xFF
    MOVWF WPUB      ; Weak pull-ups on keypad columns
    MOVLW 0x07
    MOVWF OPTION_REG ; RBPU=0 (pull-ups on), internal clock, 1:256 prescaler
 
    ; Bank 0
    BANKSEL TMR0
    CLRF TMR0        ; Clear Timer0 counter
    BCF INTCON,2     ; Clear Timer0 overflow flag
    BCF INTCON,7     ; Leave global interrupts disabled
    CLRF T1CON      ; Timer1 starts OFF (used for nonblocking beeps)
    BCF PIR1,0      ; Clear Timer1 overflow flag
 
    ; Clear all application registers
    CLRF pin_digit1
    CLRF pin_digit2
    CLRF pin_digit3
    CLRF pin_digit4
    CLRF digit_count
    CLRF key_held
    CLRF candidate_key
    CLRF keyLow
    CLRF mode
    CLRF keyHigh
    CLRF pulse_count
    CLRF pin_index
    CLRF pin_match
    CLRF pin_update
    CLRF temp_digit
    CLRF new_pin1
    CLRF new_pin2
    CLRF new_pin3
    CLRF new_pin4
    CLRF confirm_pin1
    CLRF confirm_pin2
    CLRF confirm_pin3
    CLRF confirm_pin4
    CLRF ee_address
    CLRF ee_data
    CLRF ee_status
    MOVLW NO_KEY
    MOVWF key_code
    BCF STATUS,7     ; IRP = 0: indirect addressing uses bank 0/1
 
    ; Check if a valid PIN is stored in EEPROM
    CALL CheckPINRecord
    
GOTO Main
;------------------------------------------------------------------------------
; MAIN LOOP: scan the keypad forever. A new key is debounced (10 ms), counted
; once, beeped, and sent to HandleKey. A held key is ignored until released.
; The longest the loop is ever blocked here is the 10 ms debounce delay.
;------------------------------------------------------------------------------
Main:
    CALL ServiceBeep ; Finish beep without blocking keypad scans
 
    ; Check for a keypad press
    CALL ScanKey
    BANKSEL key_code
    MOVLW NO_KEY
    XORWF key_code,W
    BTFSC STATUS,2
    GOTO KeyReleased
 
    ; Ignore a key that is still being held
    BTFSC key_held,0
    GOTO Main
 
    ; Debounce a new key press
    MOVF key_code,W
    MOVWF candidate_key
    CALL Delay
    CALL ScanKey
    BANKSEL candidate_key
    MOVF candidate_key,W
    XORWF key_code,W
    BTFSS STATUS,2
    GOTO Main        ; Not a stable press
    BSF key_held,0   ; Count this press only once
    CALL BeepKey     ; All 16 keys produce a beep
    CALL HandleKey   ; Process the new key
    GOTO Main
 
KeyReleased:
    ; Wait for a stable release before accepting another press
    BTFSS key_held,0
    GOTO Main
    CALL Delay
    CALL ScanKey
    BANKSEL key_code
    MOVLW NO_KEY
    XORWF key_code,W
    BTFSS STATUS,2
    GOTO Main
    BCF key_held,0
    GOTO Main
;------------------------------------------------------------------------------
; HANDLEKEY: decides what one debounced key means in the current mode.
; * cancels, C/# start a PIN change, # submits, digits 0-9 are stored,
; anything else is a bad entry.
;------------------------------------------------------------------------------
HandleKey:
    ; All keys reach this routine only once per debounced physical press
    BANKSEL mode
    MOVLW STAR_KEY
    XORWF key_code,W
    BTFSC STATUS,2
    GOTO CancelPIN       ; * cancels in every service mode
 
    ; C followed by # starts PIN change (only while locked)
    MOVLW MODE_ARMED
    XORWF mode,W
    BTFSC STATUS,2
    GOTO HandleArmed
 
    MOVLW 0x0E           ; C key
    XORWF key_code,W
    BTFSC STATUS,2
    GOTO HandleC
 
    MOVLW HASH_KEY
    XORWF key_code,W
    BTFSC STATUS,2
    GOTO SubmitPIN
 
    ; A, B, D or other unexpected non-numeric keys abort
    MOVLW 0x0A
    SUBWF key_code,W     ; Carry = 1 when key >= 10
    BTFSC STATUS,0
    GOTO BadEntry
 
    ; Only four digits may be entered before #
    MOVLW PIN_LENGTH
    XORWF digit_count,W
    BTFSC STATUS,2
    GOTO BadEntry
 
    ; Save numeric key in one of four RAM locations
    MOVF digit_count,W
    ADDLW pin_digit1
    MOVWF FSR
    MOVF key_code,W
    MOVWF INDF
    INCF digit_count,F
 
    MOVF digit_count,W
    ADDLW 0x30           ; Display 1, 2, 3 or 4
    CALL DisplayChar
    RETURN
HandleC:
    ; C is allowed only as the first key while normally locked
    MOVLW MODE_LOCKED
    XORWF mode,W
    BTFSS STATUS,2
    GOTO BadEntry
    MOVF digit_count,F   ; Z = 1 when no digits entered
    BTFSS STATUS,2
    GOTO BadEntry
    MOVLW MODE_ARMED
    MOVWF mode
    MOVLW 0x43           ; C = change request
    CALL DisplayChar
    RETURN
 
HandleArmed:
    MOVLW HASH_KEY
    XORWF key_code,W
    BTFSS STATUS,2
    GOTO BadEntry        ; C must be followed immediately by #
    CALL ClearEntry
    MOVLW MODE_CHANGE_AUTH
    MOVWF mode
    MOVLW 0x41           ; A = enter current PIN to authenticate
    CALL DisplayChar
    RETURN
 
; SUBMITPIN: # was pressed. It needs exactly four digits, then the current
; mode decides what to do with them.
SubmitPIN:
    ; A full entry is exactly four digits followed by #
    MOVLW PIN_LENGTH
    XORWF digit_count,W
    BTFSS STATUS,2
    GOTO BadEntry
 
    MOVLW MODE_INVALID_NEW
    XORWF mode,W
    BTFSC STATUS,2
    GOTO SaveFirstNewPIN
 
    MOVLW MODE_INVALID_CONFIRM
    XORWF mode,W
    BTFSC STATUS,2
    GOTO ConfirmNewPIN
 
    MOVLW MODE_LOCKED
    XORWF mode,W
    BTFSC STATUS,2
    GOTO NormalUnlock
 
    MOVLW MODE_CHANGE_AUTH
    XORWF mode,W
    BTFSC STATUS,2
    GOTO AuthenticateChange
 
    MOVLW MODE_CHANGE_NEW
    XORWF mode,W
    BTFSC STATUS,2
    GOTO SaveFirstNewPIN
 
    MOVLW MODE_CHANGE_CONFIRM
    XORWF mode,W
    BTFSC STATUS,2
    GOTO ConfirmNewPIN
 
    GOTO BadEntry
 
NormalUnlock:
    CALL CurrentPINMatch
    BANKSEL pin_match
    MOVF pin_match,F
    BTFSC STATUS,2
    GOTO BadEntry
    CALL ClearEntry
    MOVLW 0x55           ; U = unlocked
    CALL DisplayChar
    CALL SolenoidPulse   ; Only normal locked mode can unlock
    MOVLW 0x4C           ; L = locked again
    CALL DisplayChar
    RETURN
 
AuthenticateChange:
    CALL CurrentPINMatch
    BANKSEL pin_match
    MOVF pin_match,F
    BTFSC STATUS,2
    GOTO BadEntry        ; Incorrect old PIN cancels change
    CALL ClearEntry
    MOVLW MODE_CHANGE_NEW
    MOVWF mode
    MOVLW 0x4E           ; N = enter new PIN
    CALL DisplayChar
    RETURN
 
SaveFirstNewPIN:
    ; Copy first new PIN from entry RAM into new_pin1..new_pin4
    CALL CopyNewPIN
    CALL ClearEntry
    BANKSEL mode
    INCF mode,F          ; A NEW mode is always followed by its CONFIRM mode
    MOVLW 0x46           ; F = enter new PIN again
    CALL DisplayChar
    RETURN
 
ConfirmNewPIN:
    ; Save confirmation in RAM and compare the two groups
    CALL CopyConfirmPIN
    CALL NewPINMatch
    BANKSEL pin_match
    MOVF pin_match,F
    BTFSC STATUS,2
    GOTO BadEntry        ; A mismatch must not write EEPROM
    CALL ClearEntry
    CALL PINWrite        ; Only called after both new PINs match
    RETURN
 
CancelPIN:
    CALL RestartMode
    MOVLW 0x43           ; C = canceled
    CALL DisplayChar
    RETURN
 
BadEntry:
    CALL RestartMode
    MOVLW 0x45           ; E = incorrect/incomplete/unexpected
    CALL DisplayChar
    RETURN
 
RestartMode:
    ; Invalid-PIN modes (0 and 1) restart at the first new PIN.
    ; Every other mode returns to normal locked mode.
    BANKSEL mode
    MOVLW MODE_LOCKED
    SUBWF mode,W         ; Carry = 1 when mode >= 2
    MOVLW MODE_INVALID_NEW
    BTFSC STATUS,0       ; (MOVLW does not change Carry)
    MOVLW MODE_LOCKED
    MOVWF mode
    CALL ClearEntry
    RETURN
 
ClearEntry:
    BANKSEL digit_count
    CLRF digit_count
    CLRF pin_digit1
    CLRF pin_digit2
    CLRF pin_digit3
    CLRF pin_digit4
    RETURN

;------------------------------------------------------------------------------
; CHECKPINRECORD: at startup read the marker (address 4). Only 0xC4 plus four
; stored digits that are all 0-9 gives normal locked mode; anything else
; starts invalid PIN mode (first-run setup).
;------------------------------------------------------------------------------
CheckPINRecord:
    ; Read the validity marker before allowing normal unlocking
    BANKSEL ee_address
    MOVLW PIN_MARKER_ADDR
    MOVWF ee_address
    CALL EEPROMRead
    BANKSEL ee_data
    MOVLW VALID_MARKER
    XORWF ee_data,W
    BTFSS STATUS,2
    GOTO StartInvalid
 
    ; Even with a valid marker, reject digits outside 0 through 9
    CLRF pin_index
CheckStoredDigit:
    MOVF pin_index,W
    ADDLW PIN_EE_START
    MOVWF ee_address
    CALL EEPROMRead
    BANKSEL ee_data
    MOVLW 0x0A
    SUBWF ee_data,W      ; Carry = 1 when stored digit >= 10
    BTFSC STATUS,0
    GOTO StartInvalid
    INCF pin_index,F
    MOVLW PIN_LENGTH
    XORWF pin_index,W
    BTFSS STATUS,2
    GOTO CheckStoredDigit
 
    ; Valid PIN: start in normal locked mode
    BANKSEL mode
    MOVLW MODE_LOCKED
    MOVWF mode
    CALL ClearEntry
    MOVLW 0x4C           ; L = ready/locked
    CALL DisplayChar
    RETURN
 
StartInvalid:
    BANKSEL mode
    MOVLW MODE_INVALID_NEW
    MOVWF mode
    CALL ClearEntry
    MOVLW 0x4E           ; N = first-use new PIN required
    CALL DisplayChar
    RETURN

;------------------------------------------------------------------------------
; CURRENTPINMATCH: compares the 4 entered digits (pin_digit1..4, reached with
; FSR/INDF) with the 4 EEPROM digits. pin_match = 1 if equal, 0 if not.
;------------------------------------------------------------------------------
CurrentPINMatch:
    ; Compare the four entered digits with the EEPROM PIN.
    ; This routine NEVER operates the solenoid by itself.
    BANKSEL pin_match
    MOVLW 0x01
    MOVWF pin_match
    CLRF pin_index
 
CurrentNextDigit:
    MOVF pin_index,W
    ADDLW PIN_EE_START
    MOVWF ee_address
    CALL EEPROMRead      ; Stored digit returns in ee_data
    BANKSEL pin_index    ; EEPROMRead changes banks
    MOVF pin_index,W
    ADDLW pin_digit1
    MOVWF FSR
    MOVF INDF,W          ; Entered digit
    XORWF ee_data,W      ; Compare with stored EEPROM digit
    BTFSS STATUS,2
    GOTO CurrentMismatch
    INCF pin_index,F
    MOVLW PIN_LENGTH
    XORWF pin_index,W
    BTFSS STATUS,2
    GOTO CurrentNextDigit
    RETURN
 
CurrentMismatch:
    CLRF pin_match
    RETURN
 
CopyNewPIN:
    ; Save the four entered digits as the first new PIN
    BANKSEL pin_digit1
    MOVF pin_digit1,W
    MOVWF new_pin1
    MOVF pin_digit2,W
    MOVWF new_pin2
    MOVF pin_digit3,W
    MOVWF new_pin3
    MOVF pin_digit4,W
    MOVWF new_pin4
    RETURN
 
CopyConfirmPIN:
    ; Save the four entered digits as the confirmation PIN
    BANKSEL pin_digit1
    MOVF pin_digit1,W
    MOVWF confirm_pin1
    MOVF pin_digit2,W
    MOVWF confirm_pin2
    MOVF pin_digit3,W
    MOVWF confirm_pin3
    MOVF pin_digit4,W
    MOVWF confirm_pin4
    RETURN
 
; NEWPINMATCH: compares new_pin1..4 with confirm_pin1..4 (RAM only).
NewPINMatch:
    ; Compare the two four-digit RAM groups (no EEPROM access)
    BANKSEL pin_match
    MOVLW 0x01
    MOVWF pin_match
    CLRF pin_index
 
NewMatchLoop:
    MOVF pin_index,W
    ADDLW new_pin1
    MOVWF FSR
    MOVF INDF,W
    MOVWF temp_digit
    MOVF pin_index,W
    ADDLW confirm_pin1
    MOVWF FSR
    MOVF INDF,W
    XORWF temp_digit,W
    BTFSS STATUS,2
    GOTO NewMismatch
    INCF pin_index,F
    MOVLW PIN_LENGTH
    XORWF pin_index,W
    BTFSS STATUS,2
    GOTO NewMatchLoop
    RETURN
 
NewMismatch:
    CLRF pin_match
    RETURN

;------------------------------------------------------------------------------
; PINWRITE: the six-step EEPROM sequence. Marker invalid -> 4 digits -> marker
; valid. Every byte is written, waited for, and verified before the next one.
; Everything else is intentionally blocked until it finishes or fails.
; RA3 is HIGH for the whole write so the scope can measure the blocked time.
;------------------------------------------------------------------------------
PINWrite:
    BANKSEL PORTA
    BCF PORTA,0          ; Never unlock during EEPROM updates
    BSF PORTA,3          ; FIX: scope marker moved here from EEPROMWrite (see note there)
    BSF pin_update,0     ; PIN_UPDATE flag
    MOVLW 0x53           ; S = saving
    CALL DisplayChar
 
    ; Step 1: Invalidate marker before touching the stored digits
    BANKSEL ee_address
    MOVLW PIN_MARKER_ADDR
    MOVWF ee_address
    CLRF ee_data
    CALL WritePINByte
 
    ; Steps 2-5: Write and verify each new digit
    BANKSEL pin_index
    CLRF pin_index
 
PINWriteDigitLoop:
    MOVF pin_index,W
    ADDLW PIN_EE_START
    MOVWF ee_address
    MOVF pin_index,W
    ADDLW new_pin1
    MOVWF FSR
    MOVF INDF,W
    MOVWF ee_data
    CALL WritePINByte
    BANKSEL pin_index    ; WritePINByte changes banks
    INCF pin_index,F
    MOVLW PIN_LENGTH
    XORWF pin_index,W
    BTFSS STATUS,2
    GOTO PINWriteDigitLoop
 
    ; Step 6: Valid marker written LAST
    BANKSEL ee_address
    MOVLW PIN_MARKER_ADDR
    MOVWF ee_address
    MOVLW VALID_MARKER
    MOVWF ee_data
    CALL WritePINByte
 
    ; All six steps verified
    BANKSEL pin_update
    BCF pin_update,0     ; Writing completed and verified
    BANKSEL PORTA
    BCF PORTA,3          ; FIX: scope marker OFF, blocking is over
    CALL ClearEntry
    MOVLW MODE_LOCKED
    MOVWF mode
    MOVLW 0x50           ; P = new PIN programmed successfully
    CALL DisplayChar
    RETURN
 
WritePINByte:
    ; Write one byte, wait for it, verify it.
    ; EEPROMWrite may skip an unchanged byte, so always verify.
    CALL EEPROMWrite
 
WaitPINWrite:
    BANKSEL EECON1
    BTFSC EECON1,1       ; WR=1 while write is in progress
    GOTO WaitPINWrite
    CALL EEPROMVerifyWrite
 
    ; Any failure stops the whole sequence (no more bytes are written)
    BANKSEL ee_status
    BTFSC ee_status,EEPROM_ERROR
    GOTO PINWriteError
    RETURN
 
PINWriteError:
    ; Stop permanently until a power cycle. No further PIN attempts.
    BANKSEL PORTA
    BCF PORTA,0          ; Solenoid OFF
    BSF PORTA,2          ; RA2 error LED ON
    BCF PORTA,1          ; Buzzer OFF
    BCF PORTA,3          ; FIX: scope marker OFF
    MOVLW 0x45           ; E = EEPROM error
    CALL DisplayChar
 
PINErrorHalt:
    GOTO PINErrorHalt

;------------------------------------------------------------------------------
; BEEP and SOLENOID: the beep uses Timer1 (150 ms) and is turned off later by
; ServiceBeep, so the keypad is never blocked. The solenoid output is held ON
; for ~1 s using 15 Timer0 overflows (allowed to block the keypad).
;------------------------------------------------------------------------------
BeepKey:
    BANKSEL T1CON
    CLRF T1CON         ; Stop Timer1 before reloading
    MOVLW 0xB6
    MOVWF TMR1H
    MOVLW 0xC2
    MOVWF TMR1L        ; 0xB6C2 -> 18750 counts of 8 us = 150 ms
    BCF PIR1,0         ; Clear TMR1IF
    BANKSEL PORTA
    BSF PORTA,1        ; Active buzzer ON
    BANKSEL T1CON
    MOVLW 0x31         ; Timer1 on, Fosc/4, 1:8 prescaler
    MOVWF T1CON
    RETURN
 
ServiceBeep:
    BANKSEL T1CON
    BTFSS T1CON,0      ; Timer1 not running?
    RETURN
    BTFSS PIR1,0       ; Not 150 ms yet?
    RETURN
    BCF T1CON,0        ; Stop timer
    BCF PIR1,0
    BANKSEL PORTA
    BCF PORTA,1        ; Active buzzer OFF
    RETURN
 
SolenoidPulse:
    ; Turn on the simulated solenoid for about one second
    BANKSEL PORTA
    BSF PORTA,0          ; Unlock output HIGH
    CLRF pulse_count
    CLRF TMR0
    BCF INTCON,2
 
SolenoidWait:
    CALL ServiceBeep     ; Turn buzzer OFF after 150 ms
    BANKSEL TMR0
    BTFSS INTCON,2
    GOTO SolenoidWait
    BCF INTCON,2
    INCF pulse_count,F
    MOVLW TIMEOUT_OVERFLOWS
    XORWF pulse_count,W
    BTFSS STATUS,2
    GOTO SolenoidWait
    BCF PORTA,0          ; Lock output LOW
    RETURN

;------------------------------------------------------------------------------
; EEPROM routines (Part 2). Interfaces unchanged.
; EEPROMFetch reads one byte, EEPROMRead wraps it with status bits,
; EEPROMWrite starts a write (skips if the byte is already correct),
; EEPROMVerifyWrite reads back and sets EEPROM_ERROR on a mismatch.
;------------------------------------------------------------------------------
EEPROMFetch:
    ; Internal helper: read the EEPROM byte at ee_address, return it in W
    BANKSEL ee_address
    MOVF ee_address,W
    BANKSEL EEADR
    MOVWF EEADR
    BANKSEL EECON1
    BCF EECON1,7         ; EEPGD = 0, data EEPROM
    BSF EECON1,0         ; RD = 1
    BANKSEL EEDATA
    MOVF EEDATA,W
    RETURN
 
EEPROMRead:
    ; Mark EEPROM read as active
    BANKSEL ee_status
    BSF ee_status,EEPROM_READ
 
    ; Read the byte and return it in ee_data
    CALL EEPROMFetch
    BANKSEL ee_data
    MOVWF ee_data
 
    ; Read is finished
    BANKSEL ee_status
    BCF ee_status,EEPROM_READ
    RETURN
 
EEPROMWrite:
    ; FIX: the RA3 marker lines were removed from here. They set RA3 at the top
    ; but the early RETURN paths (same value / write busy / EEIF set) never
    ; cleared it, so RA3 got stuck HIGH. RA3 is now handled in PINWrite.

    ; Do not start if a write is already active
    BANKSEL ee_status
    BTFSC ee_status,EEPROM_WRITE
    RETURN
 
    ; Do not start if EEIF is already set
    BANKSEL PIR2
    BTFSC PIR2,4
    RETURN
 
    ; Read the currently stored byte (EEADR is now loaded)
    CALL EEPROMFetch
 
    ; Compare stored data with requested data (ee_data is not changed)
    BANKSEL ee_data
    XORWF ee_data,W
    BTFSC STATUS,2
    RETURN               ; Same value, skip the write
 
    ; Copy requested data into EEPROM data register
    MOVF ee_data,W
    BANKSEL EEDATA
    MOVWF EEDATA
 
    ; Mark the write as active and remember if GIE was on
    BANKSEL ee_status
    BSF ee_status,EEPROM_WRITE
    BCF ee_status,GIE_SAVED
    BTFSC INTCON,7       ; INTCON can be read from any bank
    BSF ee_status,GIE_SAVED
 
    ; Enable EEPROM writing
    BANKSEL EECON1
    BCF EECON1,7         ; EEPGD = 0
    BSF EECON1,2         ; WREN = 1
 
    ; Disable global interrupts for unlock
    BCF INTCON,7
 
WaitGIEOff:
    BTFSC INTCON,7
    GOTO WaitGIEOff
 
    ; Required uninterrupted EEPROM unlock
    MOVLW 0x55
    MOVWF EECON2
    MOVLW 0xAA
    MOVWF EECON2
    BSF EECON1,1         ; WR = 1, start writing
 
    ; Restore previous global interrupt state
    BANKSEL ee_status
    BTFSC ee_status,GIE_SAVED
    BSF INTCON,7         ; Turn GIE back on only if it was on before
    BCF ee_status,GIE_SAVED
    RETURN               ; Do not wait for completion
 
EEPROMVerifyWrite:
    ; Read back the byte at ee_address
    CALL EEPROMFetch
 
    ; Compare with the expected ee_data (ee_data is not changed)
    BANKSEL ee_data
    ;MOVLW 0xFF           ; Testing Error
    XORWF ee_data,W
    BTFSC STATUS,2
    GOTO VerifySuccess
 
    ; Verification failed
    BANKSEL ee_status
    BCF ee_status,EEPROM_WRITE
    BSF ee_status,EEPROM_ERROR
    GOTO VerifyFinished
 
VerifySuccess:
    ; Verification passed, clear all status flags
    BANKSEL ee_status
    CLRF ee_status
 
VerifyFinished:
    BANKSEL EECON1
    BCF EECON1,2         ; WREN = 0
    BANKSEL PIR2
    BCF PIR2,4           ; EEIF = 0
    RETURN
 
;------------------------------------------------------------------------------
; DISPLAYCHAR: send the ASCII code in W to the DLG7137 (pulse Write LOW).
;------------------------------------------------------------------------------
DisplayChar:
    ; DLG7137 Display
    ANDLW 0x7F            ; Keep the seven ASCII data bits
    IORLW 0x80            ; Keep RC7 Write HIGH
    BANKSEL PORTC
    MOVWF PORTC           ; Put character on the data pins
    NOP                   ; Allow data to settle
    BCF PORTC,7           ; Pulse display Write LOW
    NOP
    BSF PORTC,7           ; Finish the display write
    RETURN
 
; Delay = about 10 ms, used ONLY for key debounce (under the 20 ms limit)
Delay:
    CALL Delay5ms
    CALL Delay5ms
    RETURN
 
Delay5ms:
    BANKSEL Count5ms
    MOVLW   0x5E
    MOVWF   Count5ms
 
Delay5msLoop:
    CALL    Delay50usLoop
    DECFSZ  Count5ms,F
    GOTO    Delay5msLoop
    MOVLW   0x04
    MOVWF   Count5ms
    DECFSZ  Count5ms,F
    GOTO    $-1
    RETURN
 
Delay50usLoop:
    ; Delay loop is equal to 44 Tcy when count is 15
    MOVLW 0x0F             ; 1 Tcy move W=15 to count
    MOVWF Count50us        ; 1 Tcy make count equal 15
    DECFSZ Count50us,F     ; 1 Tcy if not zero, 2 Tcy if zero
    GOTO $-1               ; 2 Tcy delay runs 15 times before skipping
    RETURN

;------------------------------------------------------------------------------
; SCANSETTLE: about 0.5 ms (10 x 50 us). Gives the weak pull-ups time to pull a
; row back HIGH after a column changes. 5 settles x 0.5 ms = ~2.5 ms per scan,
; well under the 20 ms limit. Reuses Count5ms (the 5 ms delay is never running
; at the same time).
;------------------------------------------------------------------------------
ScanSettle:
    BANKSEL Count5ms
    MOVLW 0x0A
    MOVWF Count5ms
ScanSettleLoop:
    CALL Delay50usLoop
    DECFSZ Count5ms,F
    GOTO ScanSettleLoop
    RETURN

;------------------------------------------------------------------------------
; SCANKEY: drives one column low at a time (RB0-RB3) and reads the rows
; (RB4-RB7). Returns key_code = 0-9 digits, 0x0A *, 0x0B #, 0x0C A, 0x0D B,
; 0x0E C, 0x0F D, or NO_KEY (0xFF) when nothing is pressed.
; FIX: it used to call the 10 ms Delay 5 times (50 ms per scan, far over the
; 20 ms limit). It now waits ~0.5 ms per column (ScanSettle), so a scan takes ~2.5 ms.
;------------------------------------------------------------------------------
ScanKey:
    BANKSEL key_code
    MOVLW NO_KEY
    MOVWF key_code      ; FIX: assume "no key" first, so no path leaves an old key behind
    BANKSEL TRISB
    MOVLW 0xF0          
    MOVWF TRISB

BANKSEL PORTB
MOVLW 0x00          ; Ground all columns
MOVWF PORTB         ; FIX: the MOVWF was missing, W was never written to the port
CALL ScanSettle     ; FIX: ~0.5 ms settle time instead of the 10 ms Delay
MOVF PORTB,W
ANDLW 0xF0          ; Check if any Row goes low
XORLW 0xF0
BTFSC STATUS,2      ; If 0, no keys pressed
GOTO NoKeyFound
; Test Column 0 (RB0)
BANKSEL PORTB
MOVLW 0xFE
MOVWF PORTB
CALL ScanSettle
MOVF PORTB,W
ANDLW 0xF0
XORLW 0xF0
BTFSS STATUS,2
GOTO DecodeCol0
; Test Column 1 (RB1)
MOVLW 0xFD
MOVWF PORTB
CALL ScanSettle
MOVF PORTB,W
ANDLW 0xF0
XORLW 0xF0
BTFSS STATUS,2
GOTO DecodeCol1
; Test Column 2 (RB2)
MOVLW 0xFB
MOVWF PORTB
CALL ScanSettle
MOVF PORTB,W
ANDLW 0xF0
XORLW 0xF0
BTFSS STATUS,2
GOTO DecodeCol2
; Test Column 3 (RB3)
MOVLW 0xF7
MOVWF PORTB
CALL ScanSettle
MOVF PORTB,W
ANDLW 0xF0
XORLW 0xF0
BTFSS STATUS,2
GOTO DecodeCol3
GOTO MatrixExit
NoKeyFound:
    GOTO MatrixExit     ; FIX: key_code is already NO_KEY (it was being cleared to 0 before)
; --- Updated Lookups Adjusted for Keypad Orientation Mismatch ---
DecodeCol0:
BTFSS PORTB,4 
    GOTO DisplayD
BTFSS PORTB,5 
    GOTO DisplayC
BTFSS PORTB,6  
    GOTO DisplayB
BTFSS PORTB,7 
    GOTO DisplayA
GOTO MatrixExit
DecodeCol1:
BTFSS PORTB,4 
    GOTO DisplayPound
BTFSS PORTB,5 
    GOTO Display9
BTFSS PORTB,6 
    GOTO Display6
BTFSS PORTB,7 
    GOTO Display3
GOTO MatrixExit
DecodeCol2:
BTFSS PORTB,4 
    GOTO Display0
BTFSS PORTB,5 
    GOTO Display8
BTFSS PORTB,6 
    GOTO Display5
BTFSS PORTB,7 
    GOTO Display2
GOTO MatrixExit
DecodeCol3:
BTFSS PORTB,4 
    GOTO DisplayStar
BTFSS PORTB,5 
    GOTO Display7
BTFSS PORTB,6 
    GOTO Display4
BTFSS PORTB,7 
    GOTO Display1
GOTO MatrixExit
MatrixExit:
BANKSEL TRISB
MOVLW 0xF0
MOVWF TRISB
BANKSEL PORTB
MOVLW 0x00
MOVWF PORTB
RETURN
;------------------------------------------------------------------------------
; Key code loaders.
; FIX: these used to load ASCII ('0' = 0x30, 'A' = 0x41, '*' = 0x2A, '#' = 0x23),
; but HandleKey compares against 0-9, STAR_KEY (0x0A), HASH_KEY (0x0B) and
; C = 0x0E, so no key was ever recognized. They now return the 0-15 codes.
;------------------------------------------------------------------------------
Display0:   
    BANKSEL key_code 
    MOVLW 0x00 
    MOVWF key_code 
    GOTO MatrixExit
Display1:   
    BANKSEL key_code 
    MOVLW 0x01 
    MOVWF key_code 
    GOTO MatrixExit
Display2:    
    BANKSEL key_code 
    MOVLW 0x02 
    MOVWF key_code 
    GOTO MatrixExit
Display3:  
    BANKSEL key_code 
    MOVLW 0x03 
    MOVWF key_code 
    GOTO MatrixExit
Display4:    
    BANKSEL key_code 
    MOVLW 0x04 
    MOVWF key_code 
    GOTO MatrixExit
Display5:  
    BANKSEL key_code 
    MOVLW 0x05 
    MOVWF key_code 
    GOTO MatrixExit
Display6:    
    BANKSEL key_code 
    MOVLW 0x06 
    MOVWF key_code 
    GOTO MatrixExit
Display7:     
    BANKSEL key_code 
    MOVLW 0x07 
    MOVWF key_code 
    GOTO MatrixExit
Display8:   
    BANKSEL key_code 
    MOVLW 0x08 
    MOVWF key_code 
    GOTO MatrixExit
Display9:   
    BANKSEL key_code 
    MOVLW 0x09 
    MOVWF key_code 
    GOTO MatrixExit
DisplayA:   
    BANKSEL key_code 
    MOVLW 0x0C 
    MOVWF key_code 
    GOTO MatrixExit
DisplayB:   
    BANKSEL key_code 
    MOVLW 0x0D 
    MOVWF key_code 
    GOTO MatrixExit
DisplayC:  
    BANKSEL key_code 
    MOVLW 0x0E 
    MOVWF key_code 
    GOTO MatrixExit
DisplayD:  
    BANKSEL key_code 
    MOVLW 0x0F 
    MOVWF key_code 
    GOTO MatrixExit
DisplayStar: 
    BANKSEL key_code 
    MOVLW STAR_KEY 
    MOVWF key_code 
    GOTO MatrixExit
DisplayPound:
    BANKSEL key_code 
    MOVLW HASH_KEY 
    MOVWF key_code 
    GOTO MatrixExit

END