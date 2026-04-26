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
.equ BTN_RESET = PB3                    ; Port B Pin 11, does not use the two dedicated external interrupts
                                        ; TODO: Configure reset button definitions + gpio init
                                        
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
; Includes
;--------------------------------------------------------
.include "lcd.inc"

;--------------------------------------------------------
main:
;--------------------------------------------------------
          ; init stack pointer, set the stack pointer to the top of SRAM
          ldi       r16, high(RAMEND)
          out       SPH, r16
          ldi       r16, low(RAMEND)
          out       SPL, r16

          ; Initialize SRAM variables to zero
          ldi r16, 0
          sts centiseconds, r16
          sts seconds, r16
          sts minutes, r16

          ; init timer, lcd and gpio registers
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
          breq      stop_logic          ; branch if stopwatch is stopped

          ;Logic when stopwatch is running
          
          ; reset LCD screen
          ;rcall     LCD_CLEAR
          rcall     LCD_HOME

          ;update centiseconds
          lds       r17, centiseconds    ; load into register from address
          inc       r17                  ; increases value

          cpi       r17, 100             ; compare to 100
          breq      update_seconds      ; branch to update other time values

          sts       centiseconds, r17    ; store values back into centisecond
          rjmp      output              ; back to loop if 100 centiseconds is not met

update_seconds:
          clr       r17
          sts       centiseconds, r17
          
          ; update seconds
          lds       r18, seconds         ; load into register from address
          inc       r18                  ; increases value

          cpi       r18, 60              ; compare to 60
          breq      update_minutes      ; branch to update other time values

          sts       seconds, r18
          rjmp      output              ; back to loop if 60 seconds is not met

update_minutes:
          clr       r18
          sts       seconds, r18

          ; update minutes
          lds       r19, minutes        ; load into register from address
          inc       r19                  ; increases value

;          cpi       r2, 60              ; compare to 60
          sts       minutes, r19         ; branch to update other time values

;          sts       seconds, r1
 ;         rjmp      end_loop            ; back to loop if 60 seconds is not met
          ; update
          

output:
          ; loads time values
          lds       r19, minutes
          lds       r18, seconds
          lds       r17, centiseconds

          ; print minutes
          mov       r30, r19
          rcall     LCD_PRINT_UINT16

          ; print colon
          ldi       ZH, high(colon << 1)
          ldi       ZL, low(colon << 1)
          rcall     LCD_WRITE_STRING_PM

          ; print seconds
          mov       r30, r18
          rcall     LCD_PRINT_UINT16

          ; print colon
          ldi       ZH, high(colon << 1)
          ldi       ZL, low(colon << 1)
          rcall     LCD_WRITE_STRING_PM

          ; print centiseconds
          mov       r30, r17
          rcall     LCD_PRINT_UINT16


stop_logic:
          tst       state
          brne      end_loop            ; 'redundant' check, not necessary


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

          ; Save a working register, copy SREG, then save to stack
          push      r20
          in        r20, SREG
          push      r20

          ldi       tickFlag, 1         ; tickFlag = true

          ; Load TCNT1H:TCNT1L with initial count, timer/compare registers
          ; possibly remove due to redundancy, can interrupt 10ms intervals by making it slightly longer for edge cases
          ;clr       r20
          ;sts       TCNT1H, r20
          ;sts       TCNT1L, r20

          ; Restore saved SREG and restore working register
          pop       r20
          out       SREG, r20
          pop       r20

          reti

; ------------------------------------------------------------
start_ISR:
; ------------------------------------------------------------
          
          ; Save a working register, copy SREG, then save to stack
          push      r20
          in        r20, SREG
          push      r20

          ldi       startFlag, 1        ; startFlag = true 

          ; Restore saved SREG and restore working register
          pop       r20
          out       SREG, r20
          pop       r20
          
          reti

; ------------------------------------------------------------
lap_ISR:
; ------------------------------------------------------------
          ; Save a working register, copy SREG, then save to stack
          push      r20
          in        r20, SREG
          push      r20

          ldi       lapFlag, 1          ; readFlag = true

          ; Restore saved SREG and restore working register
          pop       r20
          out       SREG, r20
          pop       r20
          
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