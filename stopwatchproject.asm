;
; stopwatchproject.asm
;
; Created: 4/20/2026 8:11:02 AM
; Authors: Edwin Bautista, Langley Elg, Gustavo Vega
; Desc   : Creates a digital stopwatch on an LCD screen with two pushbuttons that 
;          can start/pause the timer and record split times.
; ------------------------------------------------------------------------------------


; Creates label for the number of clock ticks needed to create a 10ms delay between instructions
;           (desired delay / ((xtal) * prescaler))
.equ TICK_DELAY =  (10000 / ((1 / 16.0) * 8 )) - 1 ; 19999 ticks = 10ms delay

; Creates labels for Port D's Data Direction and Output registers
.equ BTN_DIR  = DDRD                    ; Used to assign pin direction
.equ BTN_MODE = PORTD                   ; Used to change the voltage state of pins

; Creates labels for the pins of each button
.equ BTN_START = PD2                    ; Start/pause button uses pin 2 of Port D (INT0)
.equ BTN_SPLIT = PD3                    ; Split button uses pin 3 of Port D (INT1)

; Defines flags used to monitor interrupt occurrences (Each ISR sets the corresponding flag to 1)
.def tickFlag = r21                     ; Updated every centisecond (.01 second)
.def startFlag = r22                    ; Updated when start/pause button is pressed
.def splitFlag = r23                    ; Updated when split button is pressed

; Defines flag used to store the state of the stopwatch
.def state = r24                        ; Updated when stopwatch starts or stops

; Creates labels for the two possible states of the stopwatch
.equ stopped = 0                        ; Set as state when stopwatch is paused
.equ running = 1                        ; Set as state when stopwatch starts running

; Creates labels for the addresses storing the current time on the stopwatch
.equ centiseconds = 0x0100
.equ seconds = 0x0101
.equ minutes = 0x0102

; Creates labels for the addresses storing the saved time recorded by the split button
.equ split_centiseconds = 0x0103
.equ split_seconds = 0x0104
.equ split_minutes = 0x0105

; ------------------------------------------------------------
; Vector Table
; ------------------------------------------------------------
.org 0x0000                             ; Reset Vector
          jmp       main

.org INT0addr                           ; External Interrupt Request 0
          jmp       start_ISR

.org INT1addr                           ; External Interrupt Request 1
          jmp       split_ISR

.org OC1Aaddr                           ; Timer/Counter1 Compare Match A
          jmp       tick_ISR

.org INT_VECTORS_SIZE                   ; End of vector table


;--------------------------------------------------------
; Strings and lookup-tables
;--------------------------------------------------------
; Allocates bytes for ASCII characters with terminator(0) to end the string
colon: .db ":", 0
split_text: .db "Split: " , 0

;--------------------------------------------------------
; Includes
;--------------------------------------------------------
.include "lcd.inc"

;--------------------------------------------------------
main:
;--------------------------------------------------------
          ; Initializes stack pointer to the last location in memory
          ldi       r16, high(RAMEND)
          out       SPH, r16
          ldi       r16, low(RAMEND)
          out       SPL, r16

          ; Initializes SRAM variables storing time to zero
          ldi r16, 0
          sts centiseconds, r16
          sts seconds, r16
          sts minutes, r16
          sts split_centiseconds, r16
          sts split_seconds, r16
          sts split_minutes, r16

          ; Initializes the LCD, GPIO, and timer registers
          rcall     LCD_INIT            ; Calls from included file to setup the LCD screen
          rcall     GPIO_init           ; Configures each button's settings
          rcall     timer_init          ; Sets up and starts timer

          ; Initializes interrupt flags to zero
          clr       startFlag           ; startFlag = false
          clr       tickFlag            ; tickFlag = false
          clr       splitFlag           ; splitFlag = false

          ; Initializes stopwatch state to zero
          clr       state               ; Stopwatch will launch in the stopped state until input

          ; Enables global interrupts by setting flag in status register
          sei
              
main_loop:
          ; Tests the value of startFlag and updates the stopwatch state accordingly
          tst       startFlag           ; Checks if the start/pause button has been pressed
          breq      check_tick          ; If not pressed, branches to 'check_tick' to delay one cycle
          
          ; Else if button is pressed
          tst       state               ; Checks if the stopwatch is running
          breq      sw_run              ; If stopped, branches to 'sw_run' to start the stopwatch

sw_stop:
          ; Updates stopwatch state to zero
          ldi       state, stopped      ; Stopwatch is stopped when start/pause button is pressed while running
          clr       startFlag           ; Interrupt flag is reset to zero
          rjmp      check_tick          ; Jumps to 'check_tick' to delay one cycle
          
sw_run:
          ; Updates stopwatch state to one
          ldi       state, running      ; Stopwatch is started when start/pause button is pressed while stopped
          clr       startFlag           ; Interrupt flag is reset to zero

check_tick:
          ; Ensures that tickFlag = 1 before moving onto the next instruction 
          tst       tickFlag            ; Checks if 10ms have passed
          breq      main_loop           ; If 10ms hasn't been reached, branches to 'main_loop' to restart loop

run_logic:
          ; Iterates to count each centisecond while stopwatch is running
          tst       state               ; Checks if the stopwatch is running 
          brne      PC+2                ; Inverted condition with PC+2 prevents out of reach error
          rjmp      stop_logic          ; If stopped, jumps to 'stop_logic' to restart loop

          ; Sets cursor at the start of the LCD screen
          rcall LCD_HOME

          ; Updates recorded value of centiseconds
          lds       r17, centiseconds   ; Loads current value of centiseconds
          inc       r17                 ; Increments centiseconds by 1

          ; Compares updated value of centiseconds with its max value
          cpi       r17, 100            ; Checks if the timer has counted 100 centiseconds 
          breq      update_seconds      ; If centiseconds = 100, branch to 'update_seconds' to increment seconds

          ; Else if centiseconds <> 100
          sts       centiseconds, r17   ; Stores current value of centiseconds in variable
          rjmp      output              ; Jumps to 'output' to continue the loop 

update_seconds:
          ; Iterates to count each second when centiseconds = 100
          clr       r17
          sts       centiseconds, r17   ; Resets recorded value of centiseconds to zero
          
          ; Updates recorded value of seconds
          lds       r18, seconds        ; Loads current value of seconds
          inc       r18                 ; Increments seconds by 1

          ; Compares updated value of seconds with its max value
          cpi       r18, 60             ; Checks if the timer has counted 60 seconds
          breq      update_minutes      ; If seconds = 60, branch to 'update_minutes' to increment minutes

          ; Else if seconds <> 60
          sts       seconds, r18        ; Stores current value of seconds in variable
          rjmp      output              ; Jumps to 'output' to continue the loop

update_minutes:
          ; Iterates to count each minute when seconds = 60
          clr       r18
          sts       seconds, r18 ; Resets recorded value of seconds to zero

          ; Updates recorded value of minutes
          lds       r19, minutes        ; Loads current value of minutes
          inc       r19                 ; Increments minutes by 1

          sts       minutes, r19        ; Stores current value of minutes in variable

          rcall     LCD_CLEAR           ; Clears the LCD screen

output:
          ; Tests the value of splitFlag and updates the split time accordingly
          tst       splitFlag           ; Checks if the split button has been pressed
          breq      display             ; If not pressed, branches to 'display' to print the current time

          ; Updates the split time with each recorded value of the current time
          lds       r20, centiseconds
          sts       split_centiseconds, r20
          lds       r20, seconds
          sts       split_seconds, r20
          lds       r20, minutes
          sts       split_minutes, r20

          ; Calls 'output_split' to print the split time before continuing with the loop
          rcall     output_split

display:
          ; Prints current time on the LCD screen every 10ms
          
          ; Sets cursor at the start of the LCD screen
          ldi       LCD_DATA, 0x80      ; Loads address of row 1 col 0 to the command register in lcd.inc
          rcall     LCD_SEND_COMMAND

          ; Updates the current time with the recorded values of each unit
          lds       r19, minutes
          lds       r18, seconds
          lds       r17, centiseconds

          ; Prints the current minute count to the LCD screen
          clr       r31
          mov       r30, r19
          rcall     LCD_PRINT_UINT16

          ; Prints the colon between minutes and seconds
          ldi       ZH, high(colon << 1)
          ldi       ZL, low(colon << 1)
          rcall     LCD_WRITE_STRING_PM

          ; Prints the current second count to the LCD screen
          clr       r31
          mov       r30, r18
          rcall     LCD_PRINT_UINT16

          ; Prints the colon between seconds and centiseconds
          ldi       ZH, high(colon << 1)
          ldi       ZL, low(colon << 1)
          rcall     LCD_WRITE_STRING_PM

          ; Prints the current centisecond count to the LCD screen
          clr       r31
          mov       r30, r17
          rcall     LCD_PRINT_UINT16

stop_logic:
          ; Checks stopwatch state and branches if it is running
          tst       state
          brne      end_loop

end_loop:
          ; Clears interrupt flags before restarting the loop
          clr       tickFlag            ; tickFlag = false
          clr       splitFlag           ; splitFlag = false

end_main:
          rjmp      main_loop

; ------------------------------------------------------------
GPIO_init:
; ------------------------------------------------------------
          ; Initializes and configures buttons
          cbi       BTN_DIR, BTN_START  ; Clears start/pause button to input mode
          sbi       BTN_MODE, BTN_START ; Sets for pull-up
          sbi       EIMSK, INT0         ; Enables external interrupt 0
          ldi       r20, (0b10 << ISC00); Defines falling edge as pin's interrupt trigger

          cbi       BTN_DIR, BTN_SPLIT  ; Clears split button to input mode
          sbi       BTN_MODE, BTN_SPLIT ; Sets for pull-up
          sbi       EIMSK, INT1         ; Enables external interrupt 1
          ori       r20, (0b10 << ISC10); Defines falling edge as pin's interrupt trigger
          
          sts       EICRA, r20          ; Sets sense bits for both INT0 and INT1

          ret

; ------------------------------------------------------------
timer_init:
; ------------------------------------------------------------
          ; Initializes timer in Timer/Counter1 Register with initial count of zero
          clr       r20
          sts       TCNT1H, r20
          sts       TCNT1L, r20

          ; Sets stop count for a 10ms delay in Output Compare1 Register
          ldi       r20, high(TICK_DELAY)
          sts       OCR1AH, r20         ; Loads upper byte into high register
          ldi       r20, low(TICK_DELAY)
          sts       OCR1AL, r20         ; Loads lower byte into low register

          ; Defines timer mode and sets prescaler in Timer/Counter1 Control Registers A and B
          clr       r20
          sts       TCCR1A, r20         ; Loads zero into Register A
          ldi       r20, (0b01 << WGM12); Defines timer mode as CTC
          ori       r20, (0b10 << CS10) ; Selects clock prescaler as clk/8
          sts       TCCR1B, r20         ; Sets clock bits, which starts the timer

          ; Enables interrupt in Timer/Counter Interrupt Mask Register
          ldi       r20, (1 << OCIE1A)
          sts       TIMSK1, r20         ; Sets interrupt to trigger when timer reaches stop count
          
          ret

; ------------------------------------------------------------
tick_ISR:
; ------------------------------------------------------------
          ; Saves a working register and a copy of the status register to the stack
          push      r20
          in        r20, SREG
          push      r20

          ; Sets interrupt flag to one during interrupt
          ldi       tickFlag, 1         ; tickFlag = true

          ; Restores saved status register and working register from stack
          pop       r20
          out       SREG, r20
          pop       r20

          ; Returns to main program and restores global interrupt
          reti

; ------------------------------------------------------------
start_ISR:
; ------------------------------------------------------------
          ; Saves a working register and a copy of the status register to the stack
          push      r20
          in        r20, SREG
          push      r20

          ; Sets interrupt flag to one during interrupt
          ldi       startFlag, 1        ; startFlag = true 

          ; Restores saved status register and working register from stack
          pop       r20
          out       SREG, r20
          pop       r20
          
          ; Returns to main program and restores global interrupt
          reti

; ------------------------------------------------------------
split_ISR:
; ------------------------------------------------------------
          ; Saves a working register and a copy of the status register to the stack
          push      r20
          in        r20, SREG
          push      r20

          ; Sets interrupt flag to one during interrupt
          ldi       splitFlag, 1        ; splitFlag = true

          ; Restores saved status register and working register from stack
          pop       r20
          out       SREG, r20
          pop       r20
          
          ; Returns to main program and restores global interrupt
          reti

; ------------------------------------------------------------
output_split:
; ------------------------------------------------------------
          ; Prints current split time on the LCD screen every 10ms

          ; Sets cursor at the start of the second row of the LCD screen
          ldi       LCD_DATA, 0xC0 ; Loads address of row 2 col 0 to the command register in lcd.inc
          rcall     LCD_SEND_COMMAND

          ; Ensures "Split: " is written in the second row before the time
          ldi       ZH, high(split_text << 1)
          ldi       ZL, low(split_text << 1)
          rcall    LCD_WRITE_STRING_PM

          ; Prints the split minute count to the LCD screen
          clr       r31
          lds       r30, split_minutes
          rcall     LCD_PRINT_UINT16
          
          ; Prints the colon between minutes and seconds
          ldi       ZH, high(colon << 1)
          ldi       ZL, low(colon << 1)
          rcall     LCD_WRITE_STRING_PM
          
          ; Prints the split second count to the LCD screen
          clr       r31
          lds       r30, split_seconds
          rcall     LCD_PRINT_UINT16
          
          ; Prints the colon between seconds and centiseconds
          ldi       ZH, high(colon << 1)
          ldi       ZL, low(colon << 1)
          rcall     LCD_WRITE_STRING_PM
          
          ; Prints the split centisecond count to the LCD screen
          clr       r31
          lds       r30, split_centiseconds
          rcall     LCD_PRINT_UINT16
          
          ret
