//Cambria Morgan
//RCET3373
//First Program
//git
//-Wl,-presetVect=0000h,-pisrVect=0004h,-pcode=0008h

; PIC16F883 Configuration Bit Settings

; Assembly source line config statements

; CONFIG1
  CONFIG  FOSC = XT             ; Oscillator Selection bits (XT oscillator: Crystal/resonator on RA6/OSC2/CLKOUT and RA7/OSC1/CLKIN)
  CONFIG  WDTE = OFF            ; Watchdog Timer Enable bit (WDT disabled and can be enabled by SWDTEN bit of the WDTCON register)
  CONFIG  PWRTE = OFF           ; Power-up Timer Enable bit (PWRT disabled)
  CONFIG  MCLRE = ON            ; RE3/MCLR pin function select bit (RE3 pin is MCLR)
  CONFIG  CP = OFF              ; Code Protection bit
  CONFIG  CPD = OFF             ; Data Code Protection bit
  CONFIG  BOREN = OFF           ; Brown Out Reset Selection bits
  CONFIG  IESO = OFF            ; Internal External Switchover mode is disabled
  CONFIG  FCMEN = OFF           ; Fail-Safe Clock Monitor is disabled
  CONFIG  LVP = OFF             ; Low Voltage Programming Enable bit

; CONFIG2
  CONFIG  BOR4V = BOR40V        ; Brown-out Reset set to 4.0V
  CONFIG  WRT = OFF             ; Flash Program Memory Self Write Enable bits

#include <xc.inc>
    writeValue EQU	0x20
    readValue EQU	0x21
    selected EQU	0x22
    CountIN EQU		0x23
    Count EQU		0x24
    uhhWhat EQU		0x25
 
    EEDAT EQU		0x00
 
; Reset Vector at 0000h. Execution starts here after reset.
PSECT resetVect,class=CODE,delta=2
ResetVector:
    GOTO Setup

; Interrupt Vector at 0004h. Execution starts here after an interrupt.
PSECT isrVect,class=CODE,delta=2
InterruptVector:

; Main code section starts at 0008h. User code goes here.
PSECT code,class=CODE,delta=2

Setup:
    //bank 0--------------------------------------------------------------------
    BANKSEL PORTA
    CLRF 0x05   ; Setting PORTA on reset to LOW
    CLRF 0x06   ; Setting PORTB on reset to LOW
    CLRF 0x07   ; Setting PORTC on reset to LOW
    CLRF PORTC
    
    //bank 1--------------------------------------------------------------------
    BANKSEL TRISB
    BSF TRISB,0
    BSF TRISB,1
    BCF TRISA,1
    BCF TRISA,2
    CLRF TRISC   ; Setting TRISC on reset to LOW, making PORTc an output
    MOVLW 0x03
    MOVWF WPUB  ; Making PORTB have weak pull-ups
    BCF OPTION_REG,7 ; enable weak pullups  
    
    //bank 3--------------------------------------------------------------------
    BANKSEL ANSEL
    CLRF ANSEL
    CLRF ANSELH
   
    //eecon---------------------------------------------------------------------
    BANKSEL EECON1
    BCF EECON1,7 ; select data eeprom 
    BCF EECON1,2 ; disable eeprom writing
    BCF EECON1,6 //disable eeprom writing
    
    //Initialize variable defaults----------------------------------------------
    BANKSEL selected
    MOVLW 0x41   ; Default choice 'A'
    MOVWF selected
    CLRF uhhWhat ; Clean status register
     
    //restore saved eeprom value -----------------------------------------------
    BANKSEL EEADR
    MOVLW 0x00
    MOVWF EEADR 
    BANKSEL EECON1
    BSF EECON1,0 //Initiate Read
    BANKSEL EEDAT
    MOVF EEDAT,w
    BANKSEL selected
    MOVWF selected  // Move read value directly to display at startup
    
    //what was the prev value if there was one----------------------------------
    SUBLW 0x41  // Is it 'A'?
    BANKSEL STATUS
    BTFSC STATUS,2
    GOTO StartupDisplayOk
    
    BANKSEL selected
    MOVF selected,W
    SUBLW 0x42  //Is it 'B'?
    BANKSEL STATUS
    BTFSC STATUS,2
    GOTO StartupDisplayOk
    
    MOVLW 0x41
    BANKSEL selected
    MOVWF selected

StartupDisplayOk:
    CLRF uhhWhat //reg cleaned wooo
    BANKSEL selected
    MOVF selected,W
    BANKSEL PORTC
    MOVWF PORTC //update the output
    
Main:
    BANKSEL PORTB 
    BTFSC PORTB,1   // is button write pushed
    GOTO CheckRead  // NAAAAAAAA its not pushed so main repeats 
    
    CALL Delay      // Yes, debounce the button 
    BANKSEL PORTB
    BTFSC PORTB,1   // is it reaaaaally pushed? check again silly
    GOTO CheckRead
    
   //while write button held it will show the selected value and allow toggle
    BANKSEL selected
    MOVF selected,W
    BANKSEL PORTC
    MOVWF PORTC //the value will show on the display
    
    // is the select button toggling or being pressed 
    BANKSEL PORTB
    BTFSC PORTB,0   //button pressed? 
    GOTO Main      //nope keep spinning
    
    CALL Delay      // no bounce 
    BANKSEL PORTB
    BTFSC PORTB,0
    GOTO Main
    
    //now we toggle
    BANKSEL selected
    MOVLW 0x03
    XORWF selected,1 ; this will toggle :)
    
WaitSelectRelease:
    BANKSEL PORTB
    BTFSS PORTB,0  //chills here until the selection is made 
    GOTO WaitSelectRelease
    GOTO CheckWrite
    CALL Delay     //no bounce 
    GOTO Main 
    
CheckRead:
    BANKSEL uhhWhat //gotta see if the value is known
    BTFSS uhhWhat,1 //write button held down?
    BCF uhhWhat,1
    GOTO ContinuousRead //na jsut read 
     
    CALL Delay //debounce when released 
    BANKSEL PORTB
    BTFSS PORTB,1 //no bounce that guy is an error ! 
    GOTO Main        
    
    BANKSEL uhhWhat
    BCF uhhWhat,1 //clWaitSelectRelease 
//cearing the unknown so no ? 
    GOTO CheckWrite

ContinuousRead:
    BANKSEL PORTA
    BSF PORTA,1    //read diagnostic high 
    BANKSEL uhhWhat
    BSF uhhWhat,1 //for the unknown vlaue 
    
    BANKSEL EEADR
    MOVLW   0x00
    MOVWF   EEADR
    BANKSEL EECON1
    BSF     EECON1,0   //reading what ever is stored in eeprom 
    BANKSEL EEDAT
    MOVF    EEDAT,W
    MOVWF   readValue
    BANKSEL PORTA
    BCF PORTA,1
   //here checks which number it will show 
    BANKSEL readValue
    MOVF    readValue,W
    SUBLW   0x41      //subtract a from the read value 
    BANKSEL STATUS
    BTFSC   STATUS,2    //if its zero then its a
    GOTO    Select      //ITS A 
    
    BANKSEL readValue
    MOVF    readValue,W
    SUBLW   0x42       //ok is the value b
    BANKSEL STATUS
    BTFSC   STATUS,2    //is it zero ?
    GOTO    Select     //ITS B
    
    ///who is this guy? do a question mark 
    BANKSEL uhhWhat
    BSF     uhhWhat,0
    GOTO    Select
 
CheckWrite:
    BANKSEL EEADR
    MOVLW   0x00       //read whats in the eeprom 
    MOVWF   EEADR
    BANKSEL selected
    MOVF    selected,W
    BANKSEL EEDAT
    MOVWF   EEDAT
    BANKSEL PORTA
    BSF     PORTA,2    //write diag 
    BANKSEL EECON1
    BSF     EECON1,2    ; Enable EE writes (WREN = 1)
     
    ; Required Uninterrupted Unlock Sequence
    MOVLW   0x55
    MOVWF   EECON2
    MOVLW   0xAA
    MOVWF   EECON2
    BSF     EECON1,1    ; Trigger Write (WR = 1)
   
Wait:
    BTFSC   EECON1,1    ; Poll WR bit until hardware sets it to 0
    GOTO    Wait
    BCF     EECON1,2    ; Disable further writing (WREN = 0)
    BANKSEL PORTA
    BCF PORTA,2           
    GOTO    Main
      
Select:
    
    BANKSEL uhhWhat
    BTFSC   uhhWhat,0
    GOTO    DisplayHUH
   
    BANKSEL readValue
    MOVF    readValue,W
    SUBLW   0x42
    BANKSEL STATUS
    BTFSC   STATUS,2    ; Is Zero flag set? (Does readValue == 0x42?)
    GOTO    DisplayB    ; Yes, go to B
    GOTO    DisplayA    ; No, go to A
    
DisplayA:
    MOVLW   0x41
    BANKSEL PORTC
    MOVWF   PORTC
    GOTO    Main 
    
DisplayB:
    MOVLW   0x42
    BANKSEL PORTC
    MOVWF   PORTC
    GOTO    Main 
    
DisplayHUH:
    MOVLW   0x3F        ; Show ASCII '?' (0x3F) for unrecognized EEPROM values
    BANKSEL PORTC
    MOVWF   PORTC
    BANKSEL uhhWhat
    BCF     uhhWhat,0   ; Clear bad data flag
    GOTO    Main

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