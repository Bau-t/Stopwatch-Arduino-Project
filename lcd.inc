;
; lcd.inc
;
;  Created: 3/21/2026 11:29:46 AM
;   Author: pallen
;     Desc: library for a 2x16 LCD with 5x8 characters.
;
;   Pinout: 
;       RS: PB0
;       RW: PB1
;       EN: PB2
;       BF: PD7
;    D7-D4: PD7-PD4
;--------------------------------------------------------

;--------------------------------------------------------
; LCD Constants
;--------------------------------------------------------

; constants for RS pin
.equ DIR_RS = DDRB
.equ OUT_RS = PORTB
.equ IN_RS  = PINB
.equ PIN_RS = 0

; constants for RW pin
.equ DIR_RW = DDRB
.equ OUT_RW = PORTB
.equ IN_RW  = PINB
.equ PIN_RW = 1

; constants for EN pin ('E')
.equ DIR_EN = DDRB
.equ OUT_EN = PORTB
.equ IN_EN  = PINB
.equ PIN_EN = 2
 
; constants for D7-D4 (D7-D4 on Port-D)
.equ DIR_DA = DDRD
.equ OUT_DA = PORTD
.equ IN_DA  = PIND

; constants for 4-bit mode busy flag
.equ DIR_BF = DDRD  
.equ IN_BF  = PIND        
.equ PIN_BF = 7        

; constants for delays
.equ LCD_DELAY_100US  = ((100  * 16) / 5)
.equ LCD_DELAY_2000US = ((2000 * 16) / 5)
.equ LCD_DELAY_4100US = ((4100 * 16) / 5)
.equ LCD_DELAY_15000US = ((15000 * 16) / 5)


;--------------------------------------------------------
; LCD Temporary Registers
; - local function registers that are saved and restored
;--------------------------------------------------------
.def LCD_PINS = R16  ; Data pin states
.def LCD_DATA = R20  ; command register
.def LCD_TEMP = R18  ; temporary register


;--------------------------------------------------------
; Function Definitions
;--------------------------------------------------------

;--------------------------------------------------------
LCD_INIT:
; HD44780U startup initialization
; 4-bit mode, 2-line display, 5x8 font
; display on, cursor off, blink off
; initialization delays used when calling LCD_DELAY_US
; USES: LCD_DATA
;--------------------------------------------------------
          push      LCD_DATA

          ; initialize pin directions first
          rcall     LCD_PORT_INIT

          ; wait for LCD power-up
          ; datasheet notes BF stays busy about 10 ms after VCC reaches 4.5 V
          ldi       R31, HIGH(LCD_DELAY_15000US)    ; 15 ms
          ldi       R30, LOW(LCD_DELAY_15000US)
          rcall     LCD_DELAY_US

          ;--------------------------------
          ; 4-bit startup handshake
          ;--------------------------------
          ; force Function Set in 8-bit style three times
          ; then switch to 4-bit mode
          ; during handshake, send upper nibble only
          ;--------------------------------

          ldi       LCD_DATA, 0x30
          rcall     LCD_WRITE_INIT_NIBBLE
          ldi       R31, HIGH(LCD_DELAY_4100US)     ; > 4.1 ms
          ldi       R30, LOW(LCD_DELAY_4100US)
          rcall     LCD_DELAY_US

          ldi       LCD_DATA, 0x30
          rcall     LCD_WRITE_INIT_NIBBLE
          ldi       R31, HIGH(LCD_DELAY_100US)      ; > 100 us
          ldi       R30, LOW(LCD_DELAY_100US)
          rcall     LCD_DELAY_US

          ldi       LCD_DATA, 0x30
          rcall     LCD_WRITE_INIT_NIBBLE
          ldi       R31, HIGH(LCD_DELAY_100US)
          ldi       R30, LOW(LCD_DELAY_100US)
          rcall     LCD_DELAY_US

          ldi       LCD_DATA, 0x20      ; switch to 4-bit mode
          rcall     LCD_WRITE_INIT_NIBBLE
          ldi       R31, HIGH(LCD_DELAY_100US)
          ldi       R30, LOW(LCD_DELAY_100US)
          rcall     LCD_DELAY_US

          ;--------------------------------
          ; now normal 4-bit commands work
          ;--------------------------------

          ldi       LCD_DATA, 0x28      ; Function Set: 4-bit, 2-line, 5x8
          rcall     LCD_SEND_COMMAND

          ldi       LCD_DATA, 0x08      ; Display OFF, cursor off, blink off
          rcall     LCD_SEND_COMMAND

          rcall     LCD_CLEAR           ; Clear Display

          ldi       LCD_DATA, 0x06      ; Entry Mode Set: increment, no shift
          rcall     LCD_SEND_COMMAND

          ldi       LCD_DATA, 0x0C      ; Display ON, cursor off, blink off
          rcall     LCD_SEND_COMMAND

          ldi       LCD_DATA, 0x80      ; DDRAM address = 0x00, row 1 start
          rcall     LCD_SEND_COMMAND

          pop       LCD_DATA
          ret

;--------------------------------------------------------
LCD_DELAY_US:
; Delay loop for LCD timing
; PARAM:
;   R31:R30 = loop count
; USES:
;   none
;--------------------------------------------------------
LCD_DELAY_US_LOOP:
          nop
          sbiw      r31:r30, 1
          brne      LCD_DELAY_US_LOOP
          ret

;--------------------------------------------------------
LCD_PORT_INIT:
; Configure LCD control and data pins for output
; PB0 = RS, PB1 = RW, PB2 = EN
; PD7-PD4 = D7-D4
; USES: LCD_PINS
;--------------------------------------------------------
          push      LCD_PINS

          sbi       DIR_RS, PIN_RS
          ;sbi       DIR_RW, PIN_RW
          sbi       DIR_EN, PIN_EN

          in        LCD_PINS, DIR_DA
          ori       LCD_PINS, 0xF0      ; D7-D4 output
          out       DIR_DA, LCD_PINS

          cbi       OUT_RS, PIN_RS
          ;cbi       OUT_RW, PIN_RW
          cbi       OUT_EN, PIN_EN

          ; optional: clear data nibble low
          in        LCD_PINS, OUT_DA
          andi      LCD_PINS, 0x0F
          out       OUT_DA, LCD_PINS

          pop       LCD_PINS
          ret

;--------------------------------------------------------
LCD_WRITE_INIT_NIBBLE:
; Send upper nibble in R17 to D7-D4 and pulse E
; Used only during 4-bit startup handshake
; PARAM:
;   LCD_DATA
; USES: 
;   LCD_PINS
;--------------------------------------------------------
          push      LCD_PINS

          cbi       OUT_RS, PIN_RS
          ;cbi       OUT_RW, PIN_RW
          cbi       OUT_EN, PIN_EN

          in        LCD_PINS, OUT_DA
          andi      LCD_PINS, 0x0F
          or        LCD_PINS, LCD_DATA
          out       OUT_DA, LCD_PINS

          sbi       OUT_EN, PIN_EN
          nop
          cbi       OUT_EN, PIN_EN

          pop       LCD_PINS
          ret

;--------------------------------------------------------
LCD_WAIT_BF:
; Read-side helper
; Wait until busy flag clears in 4-bit mode
; BF is read on DB7 when RS=0 and RW=1
; Two E pulses are required per read in 4-bit mode
; USES: data register
;    LCD_PINS, LCD_TEMP
;--------------------------------------------------------
          ; backup used registers
          push      LCD_PINS
          push      LCD_TEMP
          
          ; change D7-D4 to input
          in        LCD_PINS, DIR_DA
          andi      LCD_PINS, 0x0F      ; clear D7..4
          out       DIR_DA, LCD_PINS
          
          ; disable pull-ups on D7-D4 while reading
          in        LCD_PINS, OUT_DA
          andi      LCD_PINS, 0x0F      ; clear D7..4
          out       OUT_DA, LCD_PINS
          
          cbi       OUT_RS, PIN_RS      ; RS = 0
          sbi       OUT_RW, PIN_RW      ; RW = 1
          cbi       OUT_EN, PIN_EN      ; E = 0

LCD_WAIT_BF_LOOP:                       ; do {
          sbi       OUT_EN, PIN_EN      ;   E = 1
          nop                               
          in        LCD_PINS, IN_DA     ;   read 1st cycle: BF on D7
          cbi       OUT_EN, PIN_EN      ;   E = 0
                                            
          sbi       OUT_EN, PIN_EN      ;   E = 1
          nop                           ;   2nd cycle required in 4-bit mode
          cbi       OUT_EN, PIN_EN      ;   E = 0
          
          sbrc      LCD_PINS, PIN_BF    ; } while (BF==1) // still busy
          rjmp      LCD_WAIT_BF_LOOP

LCD_WAIT_RET:
          ; restore D7-D4 as outputs
          in        LCD_PINS, DIR_DA
          ori       LCD_PINS, 0xF0
          out       DIR_DA, LCD_PINS
          
          cbi       OUT_RW, PIN_RW      ; RW = 0
          
          ; restore used registers
          pop       LCD_TEMP
          pop       LCD_PINS
          
          ret

;--------------------------------------------------------
; LCD_DELAY_BUSY
;
; Simple fixed delay used in place of busy flag polling.
; Assumes RW is tied to GND (write-only mode).
;
; Replace all calls to LCD_WAIT_BF with this routine.
;
; Uses ~100 us delay, which is sufficient for most LCD
; commands during normal operation.
;
; Registers used: r30, r31 (preserved)
;--------------------------------------------------------
LCD_DELAY_BUSY:

          push      r30
          push      r31

          ldi       r31, HIGH(LCD_DELAY_100US)
          ldi       r30, LOW(LCD_DELAY_100US)
          rcall     LCD_DELAY_US

          pop       r31
          pop       r30

          ret

;--------------------------------------------------------
; LCD_DELAY_BUSY_LONG
;
; Long fixed delay for slow LCD commands such as
; Clear Display and Return Home.
; Assumes RW is tied to GND.
;
; Registers used: r30, r31 (preserved)
;--------------------------------------------------------
LCD_DELAY_BUSY_LONG:

          push      r30
          push      r31

          ldi       r31, HIGH(LCD_DELAY_2000US)
          ldi       r30, LOW(LCD_DELAY_2000US)
          rcall     LCD_DELAY_US

          pop       r31
          pop       r30

          ret

;--------------------------------------------------------
LCD_WRITE_NIBBLE:
; Write-side helper
; Write upper nibble of NIB_REG to LCD D7-D4 and pulse E
; Assumes RS and RW are already set correctly by caller
; PARAM:
;   LCD_DATA
; USES: 
;   LCD_TEMP
;--------------------------------------------------------
          ; backup used registers
          push      LCD_TEMP

          ; merge nibble into PORTD upper nibble, preserve PORTD low nibble
          in        LCD_TEMP, OUT_DA
          andi      LCD_TEMP, 0x0F      ; keep PD3-PD0
          or        LCD_TEMP, LCD_DATA  ; add nibble to PD7-PD4
          out       OUT_DA, LCD_TEMP

          ; pulse E
          cbi       OUT_EN, PIN_EN      ; E = 0
          nop
          sbi       OUT_EN, PIN_EN      ; E = 1
          nop
          cbi       OUT_EN, PIN_EN      ; E = 0

          ; restore used registers
          pop       LCD_TEMP

          ret

;--------------------------------------------------------
LCD_DISPLAY_ON:
          push      LCD_DATA
          ldi       LCD_DATA, 0x0C
          rcall     LCD_SEND_COMMAND
          pop       LCD_DATA
          ret

LCD_DISPLAY_OFF:
          push      LCD_DATA
          ldi       LCD_DATA, 0x08
          rcall     LCD_SEND_COMMAND
          pop       LCD_DATA
          ret

LCD_CURSOR_ON:
          push      LCD_DATA
          ldi       LCD_DATA, 0x0E
          rcall     LCD_SEND_COMMAND
          pop       LCD_DATA
          ret

LCD_CURSOR_BLINK:
          push      LCD_DATA
          ldi       LCD_DATA, 0x0F
          rcall     LCD_SEND_COMMAND
          pop       LCD_DATA
          ret

;--------------------------------------------------------
LCD_CLEAR:
; Clear display and reset cursor to (0,0)
; USES:
;   LCD_DATA
;--------------------------------------------------------
          push      LCD_DATA

          ldi       LCD_DATA, 0x01      ; Clear Display
          rcall     LCD_SEND_COMMAND
          rcall     LCD_DELAY_BUSY_LONG

          pop       LCD_DATA
          ret

;--------------------------------------------------------
LCD_HOME:
; Return cursor to home position (0,0)
; USES:
;   LCD_DATA
;--------------------------------------------------------
          push      LCD_DATA

          ldi       LCD_DATA, 0x02      ; Return Home
          rcall     LCD_SEND_COMMAND
          rcall     LCD_DELAY_BUSY_LONG

          pop       LCD_DATA
          ret

;--------------------------------------------------------
LCD_GOTO_LINE2:
; Move cursor to start of second line
; USES:
;   LCD_DATA
;--------------------------------------------------------
          push      LCD_DATA

          ldi       LCD_DATA, 0xC0      ; DDRAM = 0x40
          rcall     LCD_SEND_COMMAND

          pop       LCD_DATA
          ret

;--------------------------------------------------------
LCD_GOTO_XY:
; Move cursor to (row, col)
; PARAM:
;   R21 = row (0 or 1)
;   R23 = column (0-15)
; USES:
;   LCD_DATA
;   R16 - temp
;--------------------------------------------------------
          push      LCD_DATA
          push      r16

          mov       r16, R22            ; base = column

          tst       R21
          breq      LCD_GOTO_ROW0

          ; row 1 ? add 0x40
          ldi       LCD_DATA, 0x40
          add       r16, LCD_DATA

LCD_GOTO_ROW0:
          ; command = 0x80 | address
          ldi       LCD_DATA, 0x80
          or        LCD_DATA, r16

          rcall     LCD_SEND_COMMAND

          pop       r16
          pop       LCD_DATA
          ret

;--------------------------------------------------------
LCD_CURSOR_RIGHT:
; Move cursor right
; USES:
;   LCD_DATA
;--------------------------------------------------------
          push      LCD_DATA

          ldi       LCD_DATA, 0x14
          rcall     LCD_SEND_COMMAND

          pop       LCD_DATA
          ret

;--------------------------------------------------------
LCD_CURSOR_LEFT:
; Move cursor left
; USES:
;   LCD_DATA
;--------------------------------------------------------
          push      LCD_DATA

          ldi       LCD_DATA, 0x10
          rcall     LCD_SEND_COMMAND

          pop       LCD_DATA
          ret

;--------------------------------------------------------
LCD_SCROLL_LEFT:
; USES:
;   LCD_DATA
;--------------------------------------------------------
          push      LCD_DATA
          ldi       LCD_DATA, 0x18
          rcall     LCD_SEND_COMMAND
          pop       LCD_DATA
          ret

;--------------------------------------------------------
LCD_SCROLL_RIGHT:
; Shift entire display right
; USES:
;   LCD_DATA
;--------------------------------------------------------
          push      LCD_DATA

          ldi       LCD_DATA, 0x1C
          rcall     LCD_SEND_COMMAND

          pop       LCD_DATA
          ret

;--------------------------------------------------------
LCD_SEND_COMMAND:
; Send command byte in LCD_DATA to LCD in 4-bit mode
; High nibble first, then low nibble
; PARAM:
;   LCD_DATA
;--------------------------------------------------------

          ; wait until LCD is ready
          ; rcall     LCD_WAIT_BF
          rcall     LCD_DELAY_BUSY

          ; command write: RS = 0, RW = 0
          cbi       OUT_RS, PIN_RS
          ;cbi       OUT_RW, PIN_RW

          ; save original byte
          push      LCD_DATA

          ; send high nibble
          andi      LCD_DATA, 0xF0
          rcall     LCD_WRITE_NIBBLE

          ; send low nibble
          pop       LCD_DATA
          swap      LCD_DATA
          andi      LCD_DATA, 0xF0
          rcall     LCD_WRITE_NIBBLE

          ret

;--------------------------------------------------------
LCD_SEND_DATA:
; Send data byte in LCD_DATA to LCD in 4-bit mode
; High nibble first, then low nibble
; PARAM: 
;   LCD_DATA
;--------------------------------------------------------

          ; wait until LCD is ready
          ;rcall     LCD_WAIT_BF
          rcall     LCD_DELAY_BUSY

          ; data write: RS = 1, RW = 0
          sbi       OUT_RS, PIN_RS
          ;cbi       OUT_RW, PIN_RW

          ; save original byte
          push      LCD_DATA

          ; send high nibble
          andi      LCD_DATA, 0xF0
          rcall     LCD_WRITE_NIBBLE

          ; send low nibble
          pop       LCD_DATA
          swap      LCD_DATA
          andi      LCD_DATA, 0xF0
          rcall     LCD_WRITE_NIBBLE

          ret

;--------------------------------------------------------
LCD_WRITE_STRING:
; Write a null-terminated string from SRAM to LCD
; PARAM:
;   ZH:ZL = pointer to string in SRAM
; USES:
;   LCD_DATA
;--------------------------------------------------------
          push      LCD_DATA

LCD_WRITE_STRING_LOOP:
          ld        LCD_DATA, Z+        ; load next byte from SRAM
          tst       LCD_DATA            ; end if zero terminator
          breq      LCD_WRITE_STRING_RET

          rcall     LCD_SEND_DATA           ; write character to LCD
          rjmp      LCD_WRITE_STRING_LOOP

LCD_WRITE_STRING_RET:
          pop       LCD_DATA
          ret

;--------------------------------------------------------
LCD_WRITE_STRING_PM:
; Write a null-terminated string from program memory to LCD
; PARAM:
;   ZH:ZL = byte-addressed pointer to string in program memory
; USES:
;   LCD_DATA
;--------------------------------------------------------
          push      LCD_DATA

LCD_WRITE_STRING_PM_LOOP:
          lpm       LCD_DATA, Z+        ; load next byte from program memory
          tst       LCD_DATA            ; end if zero terminator
          breq      LCD_WRITE_STRING_PM_RET

          rcall     LCD_SEND_DATA           ; write character to LCD
          rjmp      LCD_WRITE_STRING_PM_LOOP

LCD_WRITE_STRING_PM_RET:
          pop       LCD_DATA
          ret

;--------------------------------------------------------
DIV16U_BY_10:
; Divide unsigned 16-bit integer by 10
; PARAM:
;   R31:R30 = value
; RETURNS:
;   R31:R30 = quotient
;   R22     = remainder (0-9)
; USES:
;   R20, R21, R23
;--------------------------------------------------------
          push      R20
          push      R21
          push      R23

          clr       R20                 ; quotient low
          clr       R21                 ; quotient high
          clr       R23                 ; zero register for compare

DIV16_LOOP:
          ; if value < 10 ? done
          cpi       R30, 10
          cpc       R31, R23
          brlo      DIV16_DONE

          ; subtract 10
          subi      R30, 10
          sbci      R31, 0

          ; quotient++
          inc       R20
          brne      DIV16_LOOP
          inc       R21
          rjmp      DIV16_LOOP

DIV16_DONE:
          mov       R22, R30       ; remainder

          mov       R30, R20       ; quotient ? return regs
          mov       R31, R21

          pop       R23
          pop       R21
          pop       R20

          ret

;--------------------------------------------------------
LCD_PRINT_UINT16:
; Print unsigned 16-bit integer in R31:R30
; PARAM:
;   R31:R30 = value
; USES:
;   LCD_DATA, R22, R23
;--------------------------------------------------------
          push      LCD_DATA
          push      R22
          push      R23

          ; if value == 0
          sbiw      r30, 0
          brne      PRINT_LOOP_START

          ldi       LCD_DATA, '0'
          rcall     LCD_SEND_DATA
          rjmp      PRINT_DONE

PRINT_LOOP_START:
          clr       R23            ; digit count

PRINT_LOOP:
          rcall     DIV16U_BY_10

          push      R22            ; remainder
          inc       R23

          sbiw      r30, 0
          brne      PRINT_LOOP

PRINT_POP_LOOP:
          pop       LCD_DATA
          ldi       R22, '0'
          add       LCD_DATA, R22
          rcall     LCD_SEND_DATA

          dec       R23
          brne      PRINT_POP_LOOP

PRINT_DONE:
          pop       R23
          pop       R22
          pop       LCD_DATA

          ret

;--------------------------------------------------------
LCD_DEFINE_CHAR:
; Define a custom char from an array of bytes in data or
; program memory
; PARAM:
;   R24   - custom character slot (0..7)
;   ZH:ZL - address of 8-byte pattern in EPROM
;   R23   - Z is in data (0) or program (1) memory
; USES:
;   R18, R19, LCD_DATA
;--------------------------------------------------------
          push      r18
          push      r19
          push      LCD_DATA

          ; keep only low 3 bits so slot is 0..7
          andi      r24, 0x07

          ; CGRAM address = slot * 8
          lsl       r24
          lsl       r24
          lsl       r24

          ; Set CGRAM address command: 0b01000000 | addr
          ldi       LCD_DATA, 0x40
          or        LCD_DATA, r24
          rcall     LCD_SEND_COMMAND

          ; write 8 pattern bytes from SRAM
          ldi       r18, 8
LCD_DEFINE_CHAR_LOOP:

          tst       r23                 ; which memory
          brne      LCD_DEFINE_CHAR_PM

          ld        LCD_DATA, Z+        ; from data memory
          rjmp      LCD_DEFINE_CHAR_SEND
LCD_DEFINE_CHAR_PM:
          lpm       LCD_DATA, Z+        ; from program memory

LCD_DEFINE_CHAR_SEND:
          andi      LCD_DATA, 0x1F      ; only 5 pixel bits used
          rcall     LCD_SEND_DATA
          dec       r18
          brne      LCD_DEFINE_CHAR_LOOP

          ; restore DDRAM addressing to row 1, col 0
          ; optional but usually helpful
          ldi       LCD_DATA, 0x80
          rcall     LCD_SEND_COMMAND

          pop       LCD_DATA
          pop       r19
          pop       r18
          ret


