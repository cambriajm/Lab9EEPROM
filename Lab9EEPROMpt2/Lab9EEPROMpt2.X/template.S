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

; RAM registers ---------------------------------------------------------------
writeValue       EQU 0x20
readValue        EQU 0x21
selected         EQU 0x22
CountIN          EQU 0x23
Count            EQU 0x24
uhhWhat          EQU 0x25

ee_address       EQU 0x26
ee_data          EQU 0x27
ee_status        EQU 0x28

timer   EQU 0x29
current_address  EQU 0x2A

; Status bits -----------------------------------------------------------------
EEPROM_READ      EQU 0
EEPROM_WRITE     EQU 1
EEPROM_ERROR     EQU 2
GIE_SAVE         EQU 3

; uhhWhat bits: bit 0 = Select pressed, bit 1 = Write pressed
;               bit 2 = Selection mode

PSECT resetVect,class=CODE,delta=2
ResetVector:
    GOTO Setup

PSECT isrVect,class=CODE,delta=2
InterruptVector:
    RETFIE

PSECT code,class=CODE,delta=2

Setup:
    ;bank0----------------------------------------------------------------------
    BANKSEL PORTA
    CLRF PORTA ;porta reset low 
    CLRF PORTB ;portb reset low
    CLRF PORTC ;portc reset low 
    ;bank1----------------------------------------------------------------------
    BANKSEL TRISA
    BCF TRISA,0 ;ra0 outoput
    BCF TRISA,1 ;ra1 output 
    BCF TRISA,2 ;ra2 output 
    BANKSEL TRISB
    BSF TRISB,0 ;rb0 input 
    BSF TRISB,1 ;ra1 input 
    BANKSEL TRISC
    CLRF TRISC ;portc output for ligths 
    ;bank3----------------------------------------------------------------------
    BANKSEL WPUB
    MOVLW 0x03
    MOVWF WPUB ;pull up resistors enabled on rb0 and rb1
    BANKSEL OPTION_REG
    MOVLW 0x07
    MOVWF OPTION_REG       ; Pull-ups ON, Timer0 prescaler 1:256

    BANKSEL ANSEL
    CLRF ANSEL ;clear analog, digital only 
    CLRF ANSELH ;clear analog, digital only 

    ; EEPROM setup-------------------------------------------------------------
    BANKSEL EECON1
    BCF EECON1,7 ;access data memory 
    BCF EECON1,2 ;inhibit write to eeprom 
    BANKSEL PIR2
    BCF PIR2,4 ;write operation not completed 

    ; Initialize variables-----------------------------------------------------
    BANKSEL selected
    MOVLW 0x41
    MOVWF selected ;move default a to output 
    CLRF ee_status
    CLRF uhhWhat
    CLRF timer
    CLRF current_address 

    ; Read saved value----------------------------------------------------------
    MOVF current_address,W
    MOVWF ee_address
    CALL EEPROMRead
    CALL DisplayStored

;-------------------------------------------------------------------------------
Main:
    BANKSEL PORTA
    BSF PORTA,1
    BCF PORTA,1 ;toggle led when main runs 
    BANKSEL ee_status
    BTFSS ee_status,EEPROM_WRITE ;still writing? 
    GOTO ErrorLED
    BANKSEL PIR2
    BTFSS PIR2,4 ;timer write done? 
    GOTO ErrorLED
    CALL EEPROMVerifyWrite 

ErrorLED:
    BANKSEL PORTA
    BCF PORTA,2
    BANKSEL ee_status
    BTFSC ee_status,EEPROM_ERROR
    BSF PORTA,2 ;turns on error light if error present 

    BANKSEL uhhWhat
    BTFSS uhhWhat,2 ;is the display value known? 
    GOTO Buttons

    BANKSEL INTCON
    BTFSS INTCON,2 ;timer overflow flag set? 
    GOTO Buttons ;no flag so no timer so check buttons 
    BCF INTCON,2 ;clear that timer overflow flag

    BANKSEL timer
    INCF timer,F  ;how many times has the timer counted? update it 
    MOVLW 15  ;gonna check against 15
    SUBWF timer,W ;subtract from actual count 
    BTFSS STATUS,0 ;check for carryout 
    GOTO Buttons

    BANKSEL uhhWhat
    BCF uhhWhat,2 ;clear flag for unknown value 
    BANKSEL PORTA
    BCF PORTA,0  ;clear the write led because write is finished 
    BANKSEL timer
    CLRF timer

Buttons: ;end up here if the timer is going 
    BANKSEL ee_status
    BTFSC ee_status,EEPROM_READ ;ignore buttons but check flags 
    GOTO UpdateDisplay
    BTFSC ee_status,EEPROM_WRITE
    GOTO UpdateDisplay

    BANKSEL PORTB
    BTFSC PORTB,0 ;is the select button pressed? 
    GOTO SelectReleased

    BANKSEL uhhWhat
    BTFSC uhhWhat,0 ;do we know what the value is in the selected reg? 
    GOTO WriteButton

    CALL Delay
    BANKSEL PORTB
    BTFSC PORTB,0 ;last test but debounce style 
    GOTO WriteButton

    BANKSEL uhhWhat
    BSF uhhWhat,0 ;if it didnt go to the buttons then its an unknown value 
    CALL SelectAction
    GOTO WriteButton

SelectReleased:
    BANKSEL uhhWhat
    BCF uhhWhat,0 ;clear the unknown value flag 

WriteButton:
    BANKSEL PORTB
    BTFSC PORTB,1 ;write button released? 
    GOTO WriteReleased

    BANKSEL uhhWhat
    BTFSC uhhWhat,1 ;known value? 
    GOTO UpdateDisplay

    CALL Delay
    BANKSEL PORTB
    BTFSC PORTB,1 ;debounced for write button released 
    GOTO UpdateDisplay

    BANKSEL uhhWhat
    BSF uhhWhat,1
    BTFSS uhhWhat,2 ;the value is known? 
    GOTO UpdateDisplay ; Ignore outside selection mode

    BCF uhhWhat,2 ;clear the unknown to save the pending character 
    BANKSEL PORTA
    BCF PORTA,0 ;clear the ra0 led because the value has been written 
    BANKSEL timer
    CLRF timer ;clear timer tick 

    BANKSEL current_address
    MOVF current_address,W 
    BANKSEL ee_address
    MOVWF ee_address
    BANKSEL selected
    MOVF selected,W ;move the selected button value to the eeprom data 
    BANKSEL ee_data
    MOVWF ee_data
    CALL EEPROMWrite
    GOTO UpdateDisplay

WriteReleased:
    BANKSEL uhhWhat
    BCF uhhWhat,1 ;clear unknown flag 

UpdateDisplay:
    BANKSEL uhhWhat
    BTFSC uhhWhat,2 ;test unknown 
    GOTO DisplayPending

    BANKSEL ee_status
    BTFSC ee_status,EEPROM_WRITE ;check status of written value 
    GOTO Main

    BANKSEL current_address
    MOVF current_address,W
    BANKSEL ee_address
    MOVWF ee_address ;move the value to the temp reg to move to display
    CALL EEPROMRead 
    CALL DisplayStored
    GOTO Main

DisplayPending:
    BANKSEL selected
    MOVF selected,W ;move the value to display 
    BANKSEL PORTC
    MOVWF PORTC
    GOTO Main

SelectAction:
    BANKSEL uhhWhat
    BTFSC uhhWhat,2
    GOTO Toggle

    BSF uhhWhat,2
    BANKSEL selected
    MOVLW 0x41
    MOVWF selected
    BANKSEL PORTA
    BSF PORTA,0
    GOTO ResetTimer

Toggle:
    BANKSEL selected
    MOVLW 0x03 
    XORWF selected,F

ResetTimer:
    BANKSEL timer
    CLRF timer ;clear the timer tick value 
    BANKSEL TMR0
    CLRF TMR0 ;clear timer 
    BANKSEL INTCON
    BCF INTCON,2 ;clear timer overflow flag 
    RETURN

DisplayStored:
    BANKSEL ee_data
    MOVF ee_data,W
    XORLW 0x41
    BTFSC STATUS,2 ;after being xored is it not zero? 
    GOTO DisplayA ;if its zero go to a 

    BANKSEL ee_data
    MOVF ee_data,W
    XORLW 0x42
    BTFSC STATUS,2 ;after being xored with 42 is it zero? 
    GOTO DisplayB ;if zero it goes to b 

    MOVLW 0x3F ;if a and b arent valid move the questionmark 
    GOTO ShowCharacter

DisplayA: ;disoplay a just moves the ascii value 
    MOVLW 0x41
    GOTO ShowCharacter

DisplayB:; display b jsut moves the ascii value 
    MOVLW 0x42

ShowCharacter: ;take the moved value to display it 
    BANKSEL PORTC
    MOVWF PORTC
    RETURN

EEPROMRead: ;read eeprom 
    BANKSEL ee_status
    BSF ee_status,EEPROM_READ

    BANKSEL ee_address
    MOVF ee_address,W
    BANKSEL EEADR
    MOVWF EEADR

    BANKSEL EECON1
    BCF EECON1,7
    BSF EECON1,0
    BANKSEL EEDATA
    MOVF EEDATA,W
    BANKSEL ee_data
    MOVWF ee_data

    BANKSEL ee_status
    BCF ee_status,EEPROM_READ
    RETURN

EEPROMWrite:
    BANKSEL ee_status
    BTFSC ee_status,EEPROM_WRITE
    RETURN

    BANKSEL PIR2
    BTFSC PIR2,4
    RETURN

    BANKSEL ee_address
    MOVF ee_address,W
    BANKSEL EEADR
    MOVWF EEADR
    BANKSEL EECON1
    BCF EECON1,7
    BSF EECON1,0
    BANKSEL EEDATA
    MOVF EEDATA,W
    BANKSEL ee_data
    XORWF ee_data,W
    BTFSC STATUS,2
    RETURN

    BANKSEL ee_status
    BSF ee_status,EEPROM_WRITE
    BCF ee_status,GIE_SAVE

    BANKSEL INTCON
    BTFSS INTCON,7
    GOTO StartWrite
    BANKSEL ee_status
    BSF ee_status,GIE_SAVE
    BANKSEL INTCON
    BCF INTCON,7

StartWrite:
    BANKSEL ee_address
    MOVF ee_address,W
    BANKSEL EEADR
    MOVWF EEADR
    BANKSEL ee_data
    MOVF ee_data,W
    BANKSEL EEDATA
    MOVWF EEDATA

    BANKSEL EECON1
    BCF EECON1,7
    BSF EECON1,2

    BANKSEL EECON2
    MOVLW 0x55
    MOVWF EECON2
    MOVLW 0xAA
    MOVWF EECON2
    BSF EECON1,1

    BANKSEL ee_status
    BTFSS ee_status,GIE_SAVE
    GOTO RestoreDone
    BANKSEL INTCON
    BSF INTCON,7 ;set the global interrutps again back to normal 

RestoreDone:
    BANKSEL ee_status
    BCF ee_status,GIE_SAVE ;clear the flag for the gie save 
    RETURN

EEPROMVerifyWrite:
    BANKSEL ee_address
    MOVF ee_address,W
    BANKSEL EEADR
    MOVWF EEADR
    BANKSEL EECON1
    BCF EECON1,7
    BSF EECON1,0

    BANKSEL EEDATA
    MOVF EEDATA,W
    
    ;MOVLW 0xFF 
    
    BANKSEL ee_data
    XORWF ee_data,W
    
    BTFSC STATUS,2
    GOTO VerifyOK

    BANKSEL ee_status
    BCF ee_status,EEPROM_WRITE
    BSF ee_status,EEPROM_ERROR
    GOTO VerifyEnd

VerifyOK:
    BANKSEL ee_status
    CLRF ee_status ;clear the status of the ee flag 

VerifyEnd:
    BANKSEL PIR2
    BCF PIR2,4 ;clear int flag 
    BANKSEL EECON1
    BCF EECON1,2 ;disable write 
    RETURN
    
; debounce delay------------------------------------------------------
Delay:
    CALL Delay5ms
    CALL Delay5ms
    RETURN

Delay5ms:
    MOVLW 0x5E
    MOVWF Count
Delay5msLoop:
    CALL Delay50usLoop
    DECFSZ Count,F
    GOTO Delay5msLoop
    RETURN

Delay50usLoop:
    MOVLW 0x0F
    MOVWF CountIN
Delay50usLoopInner:
    DECFSZ CountIN,F
    GOTO Delay50usLoopInner
    RETURN

END