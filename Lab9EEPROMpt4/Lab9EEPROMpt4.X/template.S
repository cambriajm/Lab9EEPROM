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
KeyValue        EQU 0x20
readValue       EQU 0x21
selected        EQU 0x22
CountIN         EQU 0x23
Count           EQU 0x24
lockTimer       EQU 0x25
ee_address      EQU 0x26
ee_data         EQU 0x27
ee_status       EQU 0x28
OldKey          EQU 0x29
current_address EQU 0x2A
PrevKey         EQU 0x31
ticks           EQU 0x32

new_pin1	EQU 0x33
new_pin2	EQU 0x34
new_pin3	EQU 0x35
new_pin4	EQU 0x36
confirm_pin1	EQU 0x37
confirm_pin2	EQU 0x38
confirm_pin3	EQU 0x39
confirm_pin4	EQU 0x3A
pin_match	EQU 0x3B ; 1 = PIN matched, 0 = not matched
pin_update	EQU 0x3C ; Bit 0 = EEPROM update in progress
temp_digit	EQU 0x3D ; Temporary byte for RAM comparisons
	   
; Common RAM registers (Shared across all banks) -------------------------------
Entry0          EQU 0x70
Entry1          EQU 0x71
Entry2          EQU 0x72
Entry3          EQU 0x73
EEPROMAddress   EQU 0x74
EEPROMData      EQU 0x75
DigitCount      EQU 0x76
Temp            EQU 0x79

; Constants -------------------------------------------------------------------
timer           EQU 15
buzzTimer       EQU 4
PinBase         EQU 0x10    ; EEPROM address of the first PIN digit
MarkerAddress	EQU 0x14
MarkerValid	EQU 0xC4
OpenTicks       EQU 100     ; 100 x 10 ms = 1 second
       
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
 

PSECT resetVect,class=CODE,delta=2
ResetVector:
    GOTO Setup

PSECT isrVect,class=CODE,delta=2
InterruptVector:
    RETFIE

PSECT code,class=CODE,delta=2
Setup:
    ; Bank 0 ------------------------------------------------------------------
    BANKSEL PORTA
    CLRF PORTA          ; Reset PORTA (Solenoid OFF, Buzzer OFF)
    CLRF PORTB          ; Reset PORTB
    CLRF PORTC          ; Reset PORTC

    ; Bank 1 ------------------------------------------------------------------
    BANKSEL TRISA
    BCF TRISA,0         ; RA0 output (Buzzer)
    BCF TRISA,1         ; RA1 output (Solenoid)
    MOVLW 0xF0          ; Rows (RB4-RB7) inputs, Columns (RB0-RB3) outputs
    MOVWF TRISB
    BANKSEL TRISC
    CLRF TRISC          ; PORTC output for display (DLG7137)

   ; Bank 3 ------------------------------------------------------------------
    BANKSEL WPUB
    MOVLW 0xF0          ; Enable weak pull-ups on Row inputs (RB4-RB7)
    MOVWF WPUB
    
    BANKSEL OPTION_REG
    BCF OPTION_REG,7    ; Clear RBPU to globally enable PORTB pull-ups
    
    BANKSEL ANSEL
    CLRF ANSEL          ; Clear Bank 0 analog channels (PORTA)
    
    BANKSEL ANSELH
    CLRF ANSELH         ; Clears AN8 through AN13 explicitly.
    MOVLW 0x00          
    MOVWF ANSELH        ; Pins on PORTB act strictly as digital I/O.
    
    ; EEPROM Setup ------------------------------------------------------------
    BANKSEL EECON1
    BCF EECON1,7        ; Access data memory
    BCF EECON1,2        ; Inhibit write to EEPROM
    BANKSEL PIR2
    BCF PIR2,4          ; Clear EEPROM write completion interrupt flag

    ; Initialize variables ----------------------------------------------------
    BANKSEL selected
    MOVLW 0x41
    MOVWF selected
    CLRF ee_status
   ; CLRF timer
    CLRF current_address
    CLRF DigitCount
    CLRF KeyValue
    CLRF OldKey
    CLRF PrevKey
    CLRF lockTimer
    CLRF ticks

    ; Show Initial Locked State -----------------------------------------------
    ;CALL InitializePIN  ; Sets default PIN memory securely
    BANKSEL PORTC
    MOVLW 0x4C          ; Show 'L' for Locked
    MOVWF PORTC
    GOTO Main

;------------------------------------------------------------------------------
Main:
    CALL Timers

    ; Do not scan keypad while the solenoid output is active
    BANKSEL lockTimer
    MOVF lockTimer,F
    BTFSS STATUS,2
    GOTO OpenWait

    CALL ButtonTest
    CALL Delay
    CALL Delay
    CALL KeyCheck
    GOTO Main

OpenWait:
    ; Fixed delay while output is active
    CALL Delay
    CALL Delay
    GOTO Main
;------------------------------------------------------------------------------
KeyCheck:
    BANKSEL KeyValue
    MOVF KeyValue,W
    BTFSC STATUS,2      ; Is KeyValue == 0? (No key pressed)
    GOTO NO
    
    XORWF PrevKey,W     ; Debounce check
    BTFSS STATUS,2
    GOTO Wait
    
    MOVF KeyValue,W
    XORWF OldKey,W
    BTFSC STATUS,2      ; Is it the same key as before?
    RETURN              ; Yes, do nothing (waiting for release)
    
    MOVF KeyValue,W
    MOVWF OldKey        ; Save new key
    GOTO DisplayPending

;------------------------------------------------------------------------------
Timers:
    BANKSEL ticks
    MOVF ticks,F
    BTFSC STATUS,2      ; Is buzzer timer 0?
    GOTO CheckLock
    DECFSZ ticks,F      ; Decrement buzzer timer
    GOTO CheckLock
    BANKSEL PORTA
    BCF PORTA,0         ; Turn OFF buzzer after pulse expires

CheckLock:
    BANKSEL lockTimer
    MOVF lockTimer,F
    BTFSS STATUS,2      ; Is lockTimer running (> 0)?
    GOTO DecLock        ; Yes, process down-tick
    RETURN              ; Safe Exit! lockTimer is 0, do not modify PORTC!

DecLock:
    DECFSZ lockTimer,F
    RETURN              ; Still ticking down...
    BANKSEL PORTA
    BCF PORTA,1         ; Lock window expired! Turn OFF Solenoid output
    BANKSEL PORTC
    MOVLW 0x4C          ; Return display to L (Locked)
    MOVWF PORTC
    RETURN

;------------------------------------------------------------------------------
Wait:
    BANKSEL KeyValue
    MOVF KeyValue,W
    MOVWF PrevKey
    RETURN

NO:
    BANKSEL PrevKey
    CLRF PrevKey
    CLRF OldKey
    RETURN

;------------------------------------------------------------------------------
DisplayPending:
    BANKSEL PORTA
    BSF PORTA,0         ; Turn ON buzzer for keypress feedback
    MOVLW buzzTimer
    BANKSEL ticks
    MOVWF ticks
    
    BANKSEL lockTimer
    MOVF lockTimer,F
    BTFSS STATUS,2      ; If lock is active (solenoid open), block key inputs
    RETURN

    MOVF OldKey,W
    XORLW 0x23          ; Is it # ?
    BTFSC STATUS,2
    GOTO Submit

    MOVF OldKey,W
    XORLW 0x2A          ; Is it * ?
    BTFSC STATUS,2
    GOTO Cancel

      ; A-D have ASCII bit 6 set; numeric digits do not
    BTFSC OldKey,6
    RETURN              ; A-D buttons: beep only, ignore action

    ; Numeric processing: accept 0-9 only
    BTFSS OldKey,4
    RETURN              ; Non-numeric key: ignore action
    ; Numeric processing
    MOVF DigitCount,W
    XORLW 4             ; Already have 4 digits typed?
    BTFSC STATUS,2
    GOTO TooMany        ; Yes -> Error
    
    MOVLW Entry0        ; Base RAM pointer
    ADDWF DigitCount,W  ; Add offset
    MOVWF FSR           ; Point to RAM destination
    
    MOVF OldKey,W
    ANDLW 0x0F          ; Strip ASCII offset to extract clean integer value
    MOVWF INDF          ; Save numeric value
    INCF DigitCount,F   ; Move forward tracking index
    
    MOVF DigitCount,W
    IORLW 0x30          ; Convert count integer to character (0x31 - 0x34)
    BANKSEL PORTC
    MOVWF PORTC         ; Feedback: show input count (1, 2, 3, 4) on display
    RETURN

TooMany:
    CLRF DigitCount     ; Reject the entire entry
    MOVLW 0x45          ; Show E (Error) on display
    BANKSEL PORTC
    MOVWF PORTC
    RETURN

Cancel:
 
    CLRF DigitCount     ; Reset tracking sequence completely
    MOVLW 0x43          ; Show C (Canceled) on display
    BANKSEL PORTC
    MOVWF PORTC
    RETURN

Submit:
    MOVF DigitCount,W
    XORLW 4             ; Exactly 4 digits present?
    BTFSS STATUS,2
    GOTO Reject         ; Wrong length -> Reject
    
    MOVLW Entry0
    MOVWF FSR           ; Reset FSR pointer to user data array
    MOVLW PinBase
    MOVWF ee_address    ; Match with initial address in EEPROM
    MOVLW 4
    MOVWF Temp          ; Loop counter across 4 locations

CompareLoop:
    CALL EEPROMRead     ; Warning: This subroutine completely switches banks!
    
    ; --- CRITICAL FIX FOR INDIRECT ADDRESS STABILITY ---
    BANKSEL KeyValue    ; Force Bank 0 back explicitly. This preserves the 
                        ; integrity of FSR indirect evaluation of Common RAM addresses!
                        
    MOVF INDF,W         ; Fetch user input digit safely
    XORWF ee_data,W     ; Compare with verification byte loaded from EEPROM
    BTFSS STATUS,2
    GOTO Reject         ; Mismatch -> Abort loop and fail
    INCF FSR,F
    INCF ee_address,F
    DECFSZ Temp,F
    GOTO CompareLoop

    ; SUCCESS: Code Verification Passed
    CLRF DigitCount
    BANKSEL KeyValue    ; Wipe button tracking system completely upon successful open
    CLRF KeyValue
    CLRF OldKey
    CLRF PrevKey
    BANKSEL PORTA
    BSF PORTA,1         ; ENGAGE SOLENOID OUTPUT HIGH
    MOVLW OpenTicks
    BANKSEL lockTimer
    MOVWF lockTimer     ; Arm automatic 1-second pulse window
    MOVLW 0x4F          ; Show O (Open) on display
    BANKSEL PORTC
    MOVWF PORTC
    RETURN

Reject:
 CLRF DigitCount     ; Wipe entry configuration sequence
    MOVLW 0x45          ; Show E (Error) on display
    BANKSEL PORTC
    MOVWF PORTC
    RETURN

;------------------------------------------------------------------------------
EEPROMRead:
    ; Read the requested EEPROM address from Bank 0 FIRST
    BANKSEL ee_address
    MOVF ee_address,W

    ; Select EEPROM address register bank
    BANKSEL EEADR
    MOVWF EEADR

    ; Access data EEPROM, not program memory
    BANKSEL EECON1
    BCF EECON1,7
    BSF EECON1,0          ; Start EEPROM read

    ; Fetch the returned data
    BANKSEL EEDATA
    MOVF EEDATA,W

    ; Save the byte in the Bank 0 return register
    BANKSEL ee_data
    MOVWF ee_data
    RETURN

;------------------------------------------------------------------------------
Delay:
    CALL Delay5ms
    CALL Delay5ms
    RETURN

Delay5ms:
    MOVLW 0x5E
    BANKSEL Count
    MOVWF Count
Delay5msLoop:
    CALL Delay50usLoop
    DECFSZ Count,F
    GOTO Delay5msLoop
    RETURN

Delay50usLoop:
    MOVLW 0x0F
    BANKSEL CountIN
    MOVWF CountIN
Delay50usLoopInner:
    DECFSZ CountIN,F
    GOTO Delay50usLoopInner
    RETURN

;------------------------------------------------------------------------------
ButtonTest:
    BANKSEL TRISB
    MOVLW 0xF0          
    MOVWF TRISB

BANKSEL PORTB
MOVLW 0x00          ; Ground all columns
CALL Delay
MOVF PORTB,W
ANDLW 0xF0          ; Check if any Row goes low
XORLW 0xF0
BTFSC STATUS,2      ; If 0, no keys pressed
GOTO NoKeyFound
; Test Column 0 (RB0)
BANKSEL PORTB
MOVLW 0xFE
MOVWF PORTB
CALL Delay
MOVF PORTB,W
ANDLW 0xF0
XORLW 0xF0
BTFSS STATUS,2
GOTO DecodeCol0
; Test Column 1 (RB1)
MOVLW 0xFD
MOVWF PORTB
CALL Delay
MOVF PORTB,W
ANDLW 0xF0
XORLW 0xF0
BTFSS STATUS,2
GOTO DecodeCol1
; Test Column 2 (RB2)
MOVLW 0xFB
MOVWF PORTB
CALL Delay
MOVF PORTB,W
ANDLW 0xF0
XORLW 0xF0
BTFSS STATUS,2
GOTO DecodeCol2
; Test Column 3 (RB3)
MOVLW 0xF7
MOVWF PORTB
CALL Delay
MOVF PORTB,W
ANDLW 0xF0
XORLW 0xF0
BTFSS STATUS,2
GOTO DecodeCol3
GOTO MatrixExit
NoKeyFound:
    BANKSEL KeyValue
    CLRF KeyValue
    GOTO MatrixExit
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
Display0:   
    BANKSEL KeyValue 
    MOVLW 0x30 
    MOVWF KeyValue 
    GOTO MatrixExit
Display1:   
    BANKSEL KeyValue 
    MOVLW 0x31 
    MOVWF KeyValue 
        GOTO MatrixExit

Display2:    
    BANKSEL KeyValue 
    MOVLW 0x32 
    MOVWF KeyValue 
        GOTO MatrixExit

Display3:  
    BANKSEL KeyValue 
    MOVLW 0x33 
    MOVWF KeyValue 
        GOTO MatrixExit

Display4:    
    BANKSEL KeyValue 
    MOVLW 0x34 
    
    MOVWF KeyValue 
        GOTO MatrixExit

Display5:  
    BANKSEL KeyValue 
    MOVLW 0x35 
    MOVWF KeyValue 
        GOTO MatrixExit

Display6:    
    BANKSEL KeyValue 
    MOVLW 0x36 
    MOVWF KeyValue 
        GOTO MatrixExit

Display7:     
    BANKSEL KeyValue 
    MOVLW 0x37 
    MOVWF KeyValue 
        GOTO MatrixExit

Display8:   
    BANKSEL KeyValue 
    MOVLW 0x38 
    MOVWF KeyValue 
        GOTO MatrixExit

Display9:   
    BANKSEL KeyValue 
    MOVLW 0x39 
    MOVWF KeyValue 
        GOTO MatrixExit

DisplayA:   
    BANKSEL KeyValue 
    MOVLW 0x41 
    MOVWF KeyValue 
        GOTO MatrixExit

DisplayB:   
    BANKSEL KeyValue 
    MOVLW 0x42 
    MOVWF KeyValue 
        GOTO MatrixExit

DisplayC:  
    BANKSEL KeyValue 
    MOVLW 0x43 
    MOVWF KeyValue 
        GOTO MatrixExit

DisplayD:  
    BANKSEL KeyValue 
    MOVLW 0x44 
    MOVWF KeyValue 
        GOTO MatrixExit

DisplayStar: 
    BANKSEL KeyValue 
    MOVLW 0x2A 
    
    MOVWF KeyValue 
        GOTO MatrixExit

DisplayPound:
    BANKSEL KeyValue 
    MOVLW 0x23 
    MOVWF KeyValue 
    
        GOTO MatrixExit

;------------------------------------------------------------------------------

CurrentPINMatch:
    
    
NewPINMatch:
    
    
PINWrite:
    
    






InitializePIN:
MOVLW PinBase
MOVWF EEPROMAddress
MOVLW 0x01          ; Store '1'
MOVWF EEPROMData
CALL EEPROMWriteINIT
MOVLW PinBase+1
MOVWF EEPROMAddress
MOVLW 0x02          ; Store '2'
MOVWF EEPROMData
CALL EEPROMWriteINIT
MOVLW PinBase+2
MOVWF EEPROMAddress
MOVLW 0x03          ; Store '3'
MOVWF EEPROMData
CALL EEPROMWriteINIT
MOVLW PinBase+3
MOVWF EEPROMAddress
MOVLW 0x04          ; Store '4'
MOVWF EEPROMData
CALL EEPROMWriteINIT
RETURN
EEPROMWriteINIT:
BANKSEL EEADR
MOVF EEPROMAddress,W
MOVWF EEADR
MOVF EEPROMData,W
MOVWF EEDATA
BANKSEL EECON1
BCF EECON1,7
BSF EECON1,2
GieOff:
BCF INTCON,7
BTFSC INTCON,7
GOTO GieOff
MOVLW 0x55
MOVWF EECON2
MOVLW 0xAA
MOVWF EECON2
BSF EECON1,1
BANKSEL PIR2
LoopWrite:
BTFSS PIR2,4
GOTO LoopWrite
BCF PIR2,4
BANKSEL EECON1
BCF EECON1,2
RETURN
END