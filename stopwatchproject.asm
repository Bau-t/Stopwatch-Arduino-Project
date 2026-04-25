;
; stopwatchproject.asm
;
; Created: 4/20/2026 8:11:02 AM
; Author : Edwin Bautista, Gustavo Vega, Langley Elg
; Desc   : Stopwatch that utilizes interrupts and timers to output lap times on a lcd screen

                 ; desired /    xtal * prescaler
.equ TICK_DELAY =  (10000 / ((1 / 16.0) * 8 )) - 1; 19,999/20,000-1 ticks, prescaler can change

; Buttons defined
.equ BTN_DIR  = DDRD
.equ BTN_MODE = PORTD
.equ BTN_START = PD2                    ; Port D Pin 2, INT0?
.equ BTN_LAP = PD3                      ; Port D Pin 3, INT1?
;.equ BTN_RESET = PD?                   ; Port D Pin 2, might be NOT NEEDED?,
                                        ; there isnt a third external to use for reset?
; Flags defined, if flag is set to 1(set in the ISRs), then that interrupt happened
.def tickFlag = r21                     ; every centisecond .01
.def startFlag = r22                    ; start/pause flag
.def lapFlag = r23                      ; lapFlag

; state of stopwatch
.def state = r24                        ; holds the state of the stopwatch
.equ stopped = 0                        ; zero if it's paused/stopped
.equ running = 1                        ; one if it's running

; store time values
.equ centiseconds = 0x0100              ; (0-99)
.equ seconds = 0x0101                   ; (0-59)
.equ minutes = 0x0102                   ; (0-59)

; ------------------------------------------------------------
; Vector Table
; ------------------------------------------------------------
.org 0x0000                             ; Reset Vector
          jmp       main

.org INT0addr                           ; External Interrupt Request 0
          jmp       start_ISR

.org INT1addr                           ; External Interrupt Request 1
          jmp       lap_ISR

.org OC1Aaddr                           ; Timer/Counter1 Compare Match A
          jmp       tick_ISR

.org INT_VECTORS_SIZE                   ; End of vector table


;--------------------------------------------------------
; Strings and lookup-tables
;--------------------------------------------------------
colon: .db ":", 0                       ; allocates bytes for ascii chars with terminator(0) ending the string
lap: .db "Lap: " , 0

;--------------------------------------------------------
; Inculdes
;--------------------------------------------------------
.include "lcd.inc"

.include "util.inc"

;--------------------------------------------------------
main:
;--------------------------------------------------------
          ; init stack pointer, set the stack pointer to the top of SRAM
          ldi       r16, high(RAMEND)
          out       SPH, r16
          ldi       r16, low(RAMEND)
          out       SPL, r16

          ;init timer, lcd and gpio registers
          rcall     gpio_init           ; buttons
          rcall     LCD_INIT            ; LCD screen
          ;rcall     RAND_INIT           ; random number generator, NOT NEEDED?
          rcall     timer_init          ; initi

          clr       startFlag           ; startFlag = false
          clr       tickFlag            ; tickFlag = false
          clr       lapFlag             ; lapFlag = false

          sei                           ; enable global interrupts   
                 
main_loop:
          ; Checks if start/pause button was pressed, updates the state
          tst       startFlag           ; checks if start/pause button was pressed
          breq      check_tick
          
          ; test the state, if its running, then change it to stop
          tst       state
          breq      sw_run              ; branch if current state is stopped

sw_stop:
          ; updates state to stopped
          ldi       state, stopped
          clr       startFlag
          rjmp      check_tick
          
sw_run:
          ; updates state to running
          ldi       state, running
          clr       startFlag


check_tick:
          ; occurs every 10 ms, 0.01
          tst       tickFlag            ; wait for next tick
          breq      end_main            ; back to loop if tick hasn't occurred

run_logic:
          tst       state               
          ;breq      stop_logic          ; branch if stopwatch is stopped

          ;Logic when stopwatch is running
          
          ; reset LCD screen
          rcall     LCD_HOME

          ;update centiseconds
          lds       r0, centiseconds
          
          inc       r0
          
          sts       centiseconds, r0

          mov       r30, r0
          rcall     LCD_PRINT_UINT16



          ; init Z pointer to message and write it
          ldi       ZH, high(colon << 1);z is r31?
          ldi       ZL, low(colon << 1)
          rcall     LCD_WRITE_STRING_PM


;stop_logic:
;          tst       state
;          brne      end_loop            ; 'redundant' check, not necessary?
;
;          ; reset LCD screen
;          rcall     LCD_CLEAR
;          rcall     LCD_HOME




;          ; init Z pointer to message and write it
;          ldi       ZH, high(message << 1)
;          ldi       ZL, low(message << 1)
;          rcall     LCD_WRITE_STRING_PM
;          
;          ;-----------------------NOT NEEDED?---
;          ; min = 100
;          ldi       r26, low(100)
;          ldi       r27, high(100)
;
;          ; max = 300
;          ldi       r28, low(300)
;          ldi       r29, high(300)
;
;          rcall     RAND_BETWEEN
;          ;--------------------------------------
;
;          ; used for displaying numbers?
;          mov       r31, r27
;          mov       r30, r26
;          rcall     LCD_PRINT_UINT16

end_loop:

          clr       tickFlag            ; tickFlag = false

end_main:
          rjmp      main_loop


; ------------------------------------------------------------
gpio_init:
; ------------------------------------------------------------
          ; initialize buttons
          cbi       BTN_DIR, BTN_START  ; input mode
          sbi       BTN_MODE, BTN_START ; pull-up
          sbi       EIMSK, INT0         ; enable INT0, pd2?
          ldi       r20, (0b10 << ISC00); fall-edge trigger
          sts       EICRA, r20          ; set sense bits

          cbi       BTN_DIR, BTN_LAP    ; input mode
          sbi       BTN_MODE, BTN_LAP   ; pull-up
          sbi       EIMSK, INT1         ; enable INT1, pd3?
          ori       r20, (0b10 << ISC10); fall-edge trigger

          sts       EICRA, r20          ; set sense bits

          ret


; ------------------------------------------------------------
timer_init:
; ------------------------------------------------------------
          ; Load TCNT1H:TCNT1L with initial count, timer/compare registers
          clr       r20
          sts       TCNT1H, r20
          sts       TCNT1L, r20

          ; Load OCR1AH:OCR1AL with stop count, output compare registers with TICK_DELAY = 624
          ldi       r20, high(TICK_DELAY); load upper byte into high register
          sts       OCR1AH, r20
          ldi       r20, low(TICK_DELAY)
          sts       OCR1AL, r20

          ; Load TCCR1A & TCCR1B
          clr       r20                 ; should be cleared, CTC mode
          sts       TCCR1A, r20         ; stores r20 into the timer/compare register 1A

          ; Clock Prescaler   setting the clock starts the timer
          ldi       r20, (0b01 << WGM12); CTC mode, WGM12 need to be set ode
          ori       r20, (0b10 << CS10) ; clk/8, CS11 needs to be set
          sts       TCCR1B, r20         ; stores r20 into the timer/compare register 1B

          ; enable interrupts
          ldi       r20, (1 << OCIE1A)
          sts       TIMSK1, r20
          ret

; ------------------------------------------------------------
tick_ISR:
; ------------------------------------------------------------
          push      r20

          ldi       tickFlag, 1         ; tickFlag = true

          ; Load TCNT1H:TCNT1L with initial count, timer/compare registers
          clr       r20
          sts       TCNT1H, r20
          sts       TCNT1L, r20

          pop       r20
          reti

; ------------------------------------------------------------
start_ISR:
; ------------------------------------------------------------
          ldi       startFlag, 1        ; startFlag = true 
          
          reti

; ------------------------------------------------------------
lap_ISR:
; ------------------------------------------------------------
          ldi       lapFlag, 1          ; readFlag = true
          
          reti

; ------------------------------------------------------------
;inc_time:                               ; change time
; ------------------------------------------------------------
;          push     r0
;          push     r1
;          ; read current time
;          lds       r1, centiseconds + 1
;          lds       r0, centiseconds
;
;          ; adjust current delay by speed adjust
;          sub       r0, r16
;          sbc       r1, r17
;
;          sts       tmCount + 1, r1
;          sts       tmCount, r0